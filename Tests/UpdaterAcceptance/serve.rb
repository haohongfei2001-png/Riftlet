# Serve only isolated GUI test fixtures, only inside the test Mac.
require 'webrick'
root = File.realpath(ARGV.fetch(0))
abort 'missing QA fixtures' unless File.file?(File.join(root, 'none.xml'))
server = WEBrick::HTTPServer.new(Port: 48091, BindAddress: '127.0.0.1', DocumentRoot: root)
server.mount_proc('/stable.xml') do |_request, response|
  response['Cache-Control'] = 'no-store'
  response['Content-Type'] = 'application/rss+xml'
  response.body = File.binread(File.join(root, 'stable.xml'))
end
server.mount_proc('/interrupted.zip') do |_request, response|
  path = File.join(root, 'B.zip')
  response['Content-Length'] = File.size(path).to_s
  response['Connection'] = 'close'
  response.body = File.open(path, 'rb') { |f| f.read(4096) }
end
trap('TERM') { server.shutdown }
server.start
