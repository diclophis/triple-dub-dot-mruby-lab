# this sorta is a web-server

@tty = UV::TTY.new(1, 1)
@tty.set_mode(0)
@tty.reset_mode
winsize = @tty.get_winsize

def puts(*args)
  @tty.write(args.join(" ") + "\n")
end

puts ARGV

=begin
buffer = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhallo"

phr = Phr.new
offset = phr.parse_response buffer
puts phr.minor_version
puts phr.status
puts phr.msg
puts phr.headers
body = buffer[offset..-1]
puts body
phr.reset

buffer = "POST / HTTP/1.1\r\nHost: www.google.com\r\nContent-Length: 5\r\nConnection: close\r\n\r\nhallo"
offset = phr.parse_request buffer
puts :method, phr.method
puts phr.path
puts phr.minor_version
puts phr.headers
body = buffer[offset..-1]
puts body
phr.reset

buffer = "b\r\nhello world\r\n0\r\n"
phr.decode_chunked(buffer)
puts buffer
phr.reset


#raise "running mruby #{i} #{winsize}"
=end

t = UV::Timer.new

if UV::Signal.const_defined?(:SIGPIPE)
  UV::Signal.new.start(UV::Signal::SIGPIPE) do
    puts "connection closed"
    t.stop
  end
end

s = UV::TCP.new
s.bind(UV::ip4_addr('0.0.0.0', 8888))
puts "bound to #{s.getsockname}"
s.listen(5) {|x|
  return if x != 0
  c = s.accept
  puts "connected (peer: #{c.getpeername})"
  c.write "helloworld\r\n"
  t.start(1000, 1000) {|x|
    puts "helloworld\n"
    begin
      c.write "helloworld\r\n"
    rescue UVError
      puts "disconnected"
      c.close
      c = nil
      t.stop
      t = nil
    end
  }
}

UV::run()
