#!/usr/bin/env ruby
require 'socket'
require 'securerandom'
require 'open3'
require 'timeout'
require 'json'

abort 'Requires the reserved disposable Safari guest' unless ENV['RIFTLET_DISPOSABLE_SAFARI_GUEST'] == 'yes' &&
  `/usr/sbin/sysctl -n hw.model`.strip == 'VirtualMac2,1'
safari = '/Applications/Safari.app'
abort 'Safari already running' if system('/usr/bin/pgrep', '-x', 'Safari', out: File::NULL)
abort 'Unverified system browser' unless system('/usr/bin/codesign', '--verify', '--all-architectures',
                                                '-R=anchor apple and identifier "com.apple.Safari"', safari)
server = TCPServer.new('127.0.0.1', 0)
token = SecureRandom.hex(24)
route, report = ['/fixture', '/receipt'].map { |path| "#{path}?#{token}" }
url = "http://127.0.0.1:#{server.addr[1]}#{route}"
pins, ok = Open3.capture2(File.expand_path(ARGV.fetch(0)), url)
abort 'Cannot export exact compiled pins' unless ok.success?
script = pins + "\n" + File.read(File.join(__dir__, 'probe.js'))
raise 'unexpected embedded script end' if script.downcase.include?('</script')
page = "<!doctype html><meta charset=utf-8><title>Riftlet QA</title><textarea autofocus></textarea><script>#{script}</script>"
receipt = pid = birth = nil
snapshots = {}
stages = %w[original editor history reload]
begin
  raise 'Launch Services error' unless system('/usr/bin/open', '-a', safari, url)
  Timeout.timeout(12) do
    until pid
      ids = `/usr/bin/pgrep -x Safari`.split
      raise 'ambiguous Safari process' if ids.length > 1
      unless ids.empty?
        pid = Integer(ids.first)
        birth = `/bin/ps -p #{pid} -o lstart=`.strip
        raise 'missing Safari process birth' if birth.empty?
      end
      sleep 0.1 unless pid
    end
  end
  Timeout.timeout(30) do
    until receipt
      sock = server.accept
      begin
        method, target = sock.gets.to_s.split
        headers = {}
        while (line = sock.gets) && !line.strip.empty?
          k, v = line.split(':', 2)
          headers[k.downcase] = v.strip if v
        end
        body, status = '', '404 Not Found'
        if method == 'GET' && target == route
          body, status = page, '200 OK'
        elsif method == 'POST' && (stage = stages.find { |s| target == "/checkpoint/#{s}?#{token}" })
          raise 'duplicate or out-of-order checkpoint' unless stage == stages[snapshots.size]
          observation, ok = Open3.capture2(File.expand_path(ARGV.fetch(0)), '--native-window')
          snapshots[stage] = ok.success? ? observation.strip : nil
          status = '200 OK'
        elsif method == 'POST' && target == report
          n = Integer(headers.fetch('content-length'))
          raise 'invalid receipt size' unless (2..4096).cover?(n)
          receipt = JSON.parse(sock.read(n))
          status = '200 OK'
        end
        sock.write("HTTP/1.1 #{status}\r\nContent-Type: text/html\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'; script-src 'unsafe-inline'; connect-src 'self'\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
      ensure
        sock.close
      end
    end
  end
  originals = snapshots.fetch('original', nil)
  receipt['nativeWindowsObserved'] = snapshots.values.count { |id| !id.nil? }
  receipt['sameNativeReceiverAndWindow'] = !originals.nil? && stages.all? { |stage| snapshots[stage] == originals }
  puts JSON.generate(receipt)
  witness = ['bound', 'probe_ran|notReached']
  expected = { 'original' => witness, 'oldFenceAfterEditorABA' => 'refused',
    'editorBind' => 'bound', 'editorRestored' => true, 'historyBind' => 'bound', 'pushedSameURL' => true,
    'afterEditor' => witness, 'afterHistory' => witness, 'historyReadWithinLifetime' => true,
    'originalEntryRestored' => true, 'oldFenceAfterHistoryABA' => 'refused', 'reloadBind' => 'bound',
    'oldFenceAfterReload' => 'refused', 'newDocument' => witness, 'newGlobalAfterReload' => true,
    'reloadNavigation' => true, 'nativeWindowsObserved' => 4, 'sameNativeReceiverAndWindow' => true }
  exit 1 unless expected.all? { |key, value| receipt[key] == value }
ensure
  server.close
  if pid
    name, ok = Open3.capture2('/bin/ps','-p',pid.to_s,'-o','ucomm=')
    if ok.success? && name.strip == 'Safari' && !birth.to_s.empty? && `/bin/ps -p #{pid} -o lstart=`.strip == birth
      Process.kill('TERM', pid)
      Timeout.timeout(10) { sleep 0.1 while system('/usr/bin/pgrep', '-x', 'Safari', out: File::NULL) }
    end
  end
end
