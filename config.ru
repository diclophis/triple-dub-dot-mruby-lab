# this sorta is a web-server

begin

@tty = UV::TTY.new(1, 1)
#@tty.set_mode(0)
#@tty.reset_mode
#winsize = @tty.get_winsize

def puts(*args)
  @tty.write(args.join(" ") + "\n")
end

rescue => e
  def puts(*args)
  end
end

puts ARGV.inspect

s = UV::TCP.new

if UV::Signal.const_defined?(:SIGINT)
  puts :wtf
  UV::Signal.new.start(UV::Signal::SIGINT) do
    puts :interupted
    UV.default_loop.stop
  end
end

s.bind(UV.ip4_addr('0.0.0.0', (ARGV[0] && ARGV[0].to_i) || 8888))

puts "bound to #{s.getsockname}"

s.listen(5) { |x|
  return if x != 0

  c = s.accept
  puts "connected (peer: #{c.getpeername})"

  phr = Phr.new

  ss = String.new
      c.read_start { |b|
            ss += b.to_s
            offset = phr.parse_request(ss)

puts offset

            if offset.is_a?(Fixnum)
              puts :method, offset, phr.method.inspect
              puts phr.path.inspect
              puts phr.minor_version.inspect
              puts phr.headers.inspect
              #phr.decode_chunked(buffer)
              #puts phr.inspect
              c.write("Content-Type: text/plain\r\n\r\nOK")
              c.close
            elsif offset == :parser_error
              c.close
            end
      }
}

UV.run
