require 'socket'
require 'uri'
require 'json'
root = File.realpath(ARGV.fetch(0))
nonce = ARGV.fetch(1)
abort unless nonce.match?(/\A[a-f0-9]{32}\z/)
server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
File.write(File.join(root, 'port'), port)
allowed = %w[fixture.html fixture.js receiver.js]
loop do
  socket = server.accept
  begin
    first = socket.gets
    next unless first
    method, path, = first.split
    headers = {}
    while (line = socket.gets) && line.strip != ''
      k,v = line.split(':',2)
      headers[k.downcase] = v.strip if v
    end
    part = path.split('?').first.delete_prefix("/#{nonce}/")
    valid = method == 'GET' && path.start_with?("/#{nonce}/") && headers['host'] == "127.0.0.1:#{port}" && allowed.include?(part)
    body = valid ? File.binread(File.join(root,part)) : ''
    kind = part == 'fixture.html' ? 'text/html; charset=utf-8' : 'text/javascript'
    csp = "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; connect-src 'none'; frame-ancestors 'none'"
    socket.write("HTTP/1.1 #{valid ? '200 OK' : '404 Not Found'}\r\nContent-Type: #{kind}\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\nContent-Security-Policy: #{csp}\r\n\r\n")
    socket.write(body)
  rescue Errno::EPIPE, Errno::ECONNRESET
  ensure
    socket.close
  end
end
