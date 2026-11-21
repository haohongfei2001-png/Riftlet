# Only use inside the dedicated macOS QA login. This helper addresses an owned
# window and tab by native ID. JavaScript executes only after checking the exact
# loopback fixture URL. The word processor and other user apps are never targeted.
require 'open3'
require 'json'
require 'uri'
root=File.realpath(ARGV.shift)
family, action=ARGV.shift(2)
bundle,proc_name = {'chrome'=>['com.google.Chrome','Google Chrome'],'edge'=>['com.microsoft.edgemac','Microsoft Edge']}.fetch(family)
endpoint = 'http://127.0.0.1:' + Integer(File.read(File.join(root,'port'))).to_s + '/' + File.read(File.join(root,'nonce')).strip + '/fixture.html'
def native(bundle,body,*args)
  source="on run argv\nwith timeout of 4 seconds\ntell application id \"#{bundle}\"\n#{body}\nend tell\nend timeout\nend run"
  out, err, rc=Open3.capture3('/usr/bin/osascript','-',*args,stdin_data:source)
  raise("Apple Event rejected (#{err[/\((-?\d+)\)/,1] || 'unknown'})") unless rc.success?
  out.strip
end
def read_int(text)
  raise 'invalid native identity' unless /\A[1-9]\d*\z/.match?(text)
  Integer(text)
end
pid_list=IO.popen(['/usr/bin/pgrep','-x',proc_name], &:read).split
raise 'expected one isolated ordinary browser' unless pid_list.length==1
pid=read_int(pid_list.first)
args=IO.popen(['/bin/ps','-p',pid.to_s,'-o','args='], &:read)
raise 'ordinary browser required' if args.include?('--remote-debugging') || args.include?('--headless')
field=File.join(root,family+'.json')
if action=='create'
  raise 'already requested for this family' if File.exist?(field)
  File.write(field,JSON.generate({status:'creationRequested',pid:pid}))
  ids=native(bundle,"set w to make new window\nreturn (id of w as string) & \",\" & (id of active tab of w as string)")
  w,t=ids.split(',').map { |s| read_int(s) }
  File.write(field,JSON.generate({pid:pid,window:w,tab:t}))
  native(bundle,'set URL of tab id (item 2 of argv as integer) of window id (item 1 of argv as integer) to (item 3 of argv)',w.to_s,t.to_s,endpoint)
  puts JSON.generate({family:family,pid:pid,window:w,tab:t,headless:false,debug:false})
  exit
end
old=JSON.parse(File.read(field))
raise 'original browser process changed' unless old['pid']==pid
raise 'native window creation did not return an identity' if old['status']=='creationRequested'
w,t = old.values_at('window','tab').map { |n| read_int(n.to_s).to_s }
if action=='close'
  r=native(bundle,<<~AS,w,t,endpoint)
    set w to window id (item 1 of argv as integer)
    if (count of tabs of w) is not 1 then error "window changed"
    set t to active tab of w
    if (id of t as string) is not (item 2 of argv) then error "tab changed"
    if URL of t is not (item 3 of argv) then error "fixture replaced"
    close w
    return "closed"
  AS
  puts r
  exit
end
expr=ARGV.join(' ')
raise 'missing fixture operation' if expr.empty?
js="JSON.stringify((()=>{ if(location.href!==#{JSON.generate(endpoint)}) return {status:'ROUTE_CHANGED'}; return (#{expr}); })())"
result=native(bundle,<<~AS,w,t,endpoint,js)
  set w to window id (item 1 of argv as integer)
  set t to tab id (item 2 of argv as integer) of w
  if URL of t is not (item 3 of argv) then error "fixture URL changed"
  return execute t javascript (item 4 of argv)
AS
puts JSON.generate(JSON.parse(result))
