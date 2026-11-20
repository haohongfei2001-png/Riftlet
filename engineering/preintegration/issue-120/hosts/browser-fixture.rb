#!/usr/bin/env ruby
# An isolated page-context diagnostic. This is not a BrowserHost writer, a
# live website, an Apple Events realm check or a signed-product attachment.
require 'json'
require 'socket'
require 'tmpdir'
require 'securerandom'
require 'timeout'
require 'open3'
require 'fileutils'
require 'uri'

bundle = File.realpath(ARGV.fetch(0))
info = File.join(bundle, 'Contents/Info.plist')
def plist(name, info)
  val, ok = Open3.capture2('/usr/libexec/PlistBuddy', '-c', "Print :#{name}", info)
  raise 'invalid Info.plist' unless ok.success?
  val.strip
end
id = plist('CFBundleIdentifier', info)
exe = File.join(bundle, 'Contents/MacOS', plist('CFBundleExecutable', info))
teams = {'com.google.Chrome'=>'EQHXZ8M8AV', 'com.microsoft.edgemac'=>'UBF8T346G9',
         'org.mozilla.firefox'=>'43AQ936H96', 'com.brave.Browser'=>'KL8N8XSYF4'}
safari = id == 'com.apple.Safari'
firefox_guest = id == 'org.mozilla.firefox' && ENV['RIFTLET_DISPOSABLE_FIREFOX_GUEST'] == 'yes'
abort 'Normal Firefox AX probe requires a disposable guest' if firefox_guest && `/usr/sbin/sysctl -n hw.model`.strip != 'VirtualMac2,1'
abort 'unrecognized browser' unless safari || teams.key?(id)
requirement = safari ? 'anchor apple and identifier "com.apple.Safari"' :
  "anchor apple generic and identifier \"#{id}\" and certificate leaf[subject.OU] = \"#{teams.fetch(id)}\""
abort 'signature mismatch' unless system('/usr/bin/codesign', '--verify', '--all-architectures', '-R='+requirement, bundle)
abort 'Gatekeeper assessment failed' unless system('/usr/sbin/spctl','--assess','--type','execute',bundle)
if safari
  abort 'Safari fixture requires a disposable guest' unless ENV['RIFTLET_DISPOSABLE_SAFARI_GUEST'] == 'yes' &&
    `/usr/sbin/sysctl -n hw.model`.strip == 'VirtualMac2,1'
  abort 'Safari already running' if system('/usr/bin/pgrep','-x','Safari',out:File::NULL)
end

def finish_group(pid)
  return if !pid || Process.waitpid(pid, Process::WNOHANG)
  Process.kill('TERM', -pid)
  Timeout.timeout(5) { Process.waitpid(pid) }
rescue Errno::ESRCH, Errno::ECHILD
rescue Timeout::Error
  Process.kill('KILL', -pid)
  Process.waitpid(pid)
end

fixture = File.binread(File.join(__dir__, 'fixture.html'))
Dir.mktmpdir('riftlet-120-profile-') do |dir|
  server = TCPServer.new('127.0.0.1', 0)
  url = "http://127.0.0.1:#{server.addr[1]}/fixture?#{SecureRandom.hex(16)}"
  query = URI.parse(url).query
  pid = guest_pid = receipt = nil
  begin
    if safari
      raise 'launch failed' unless system('/usr/bin/open','-g','-a',bundle,url)
      20.times do
        candidates = `/usr/bin/pgrep -x Safari`.split
        if candidates.length == 1
          guest_pid = Integer(candidates.first)
          break
        end
        sleep 0.2
      end
      raise 'new guest Safari not found' unless guest_pid
    else
      args = id == 'org.mozilla.firefox' ? ['-headless','-no-remote','-profile',dir,url] :
        ['--headless', '--no-first-run','--no-default-browser-check','--disable-background-networking',
         "--user-data-dir=#{dir}",url]
      args.delete('-headless') if firefox_guest
      pid = Process.spawn(exe, *args, out:File::NULL, err:File::NULL, pgroup:true)
    end
    Timeout.timeout(35) do
      until receipt
        sock = server.accept
        begin
          request = sock.gets.to_s.split
          headers = {}
          while (line = sock.gets) && line.strip != ''
            k, v = line.split(':',2)
            headers[k.downcase] = v.strip if v
          end
          body, type, status = '', 'text/plain', '404 Not Found'
          if request[0] == 'GET' && request[1] == "/fixture?#{query}"
            body, type, status = fixture, 'text/html', '200 OK'
          elsif request[0] == 'POST' && request[1] == "/receipt?#{query}"
            n = Integer(headers.fetch('content-length'))
            raise 'unexpected fixture payload size' unless (2..2048).cover?(n)
            receipt = JSON.parse(sock.read(n))
            status = '200 OK'
          end
          sock.write("HTTP/1.1 #{status}\r\nContent-Type: #{type}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
        ensure
          sock.close
        end
      end
    end
    expected = {'received'=>[82,49,50,48,0,255], 'events'=>['input','change'], 'fileName'=>'fixture.bin',
                'originalText'=>'synthetic draft','selection'=>[2,7],
                'legacyReplaceInvisible'=>true,'sameURLAfterEditorReplacement'=>true}
    receiver = nil
    if pid && (helper = ENV['RIFTLET_FIXTURE_RECEIVER'])
      data, ok = Open3.capture2(helper, bundle, pid.to_s)
      raise 'could not attribute isolated browser to runner' unless ok.success?
      receiver = JSON.parse(data)
    end
    ax = nil
    if firefox_guest
      data, ok = Open3.capture2(ENV.fetch('RIFTLET_FIREFOX_AX_PROBE'), pid.to_s)
      raise 'AX probe could not establish its own Firefox PID' unless ok.success?
      ax = JSON.parse(data)
    end
    mode = safari ? 'disposable ordinary Safari' : (firefox_guest ? 'disposable ordinary Firefox' : 'dedicated headless profile')
    puts JSON.generate({bundle:id,version:plist('CFBundleShortVersionString',info),fixtureReceiver:receiver,
                        nativePickerProbe:ax,mode:mode,
                        fixtureMatches:expected.all? { |k,v| receipt[k] == v }, result:receipt})
    exit 1 unless expected.all? { |k,v| receipt[k] == v }
  ensure
    server.close
    if safari && guest_pid
      now, ok = Open3.capture2('/bin/ps','-p',guest_pid.to_s,'-o','ucomm=')
      Process.kill('TERM', guest_pid) if ok.success? && now.strip == 'Safari'
    else
      finish_group(pid)
    end
  end
end
