#!/usr/bin/env ruby

# this sorta is a web-server

UV.disable_stdio_inheritance

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

def rutty
return <<EOJS
var Rutty = function(argv, terminal) {
  this.terminalForm = terminal;
  this.socket = terminal.dataset.socket;
  this.consoleUid = terminal.dataset.console;
  this.argv_ = argv;
  this.io = null;
  this.sendingSweep = null;
  this.pendingString = [];
  this.sendingResize = null;
  this.pendingResize = [];
  this.source = new EventSource(this.terminalForm.action + '?socket=' + this.socket); //TODO: fix socket params passing, put in session somehow
  this.source.onopen = function(event) {
    this.io.terminal_.reset(); //TODO: resume, needs to keep some buffer
  }.bind(this);
  this.source.onmessage = function(event) {
    var msg = JSON.parse(event.data);

    if (msg.raw && msg.raw.length > 0) { // see: https://github.com/flori/json for discussion on `to_json_raw_object`
      var decoded = '';
      for (var i=0; i<msg.raw.length; i++) {
        //NOTE: what is the difference here?
        decoded += String.fromCodePoint(msg.raw[i]); // & 0xff ??
        //decoded += String.fromCharCode(msg.raw[i]); // & 0xff ??
      }

      this.io.writeUTF16(decoded);
    }
  }.bind(this);
  this.source.onerror = function(e) {
    this.source.close();
    this.io.writeUTF16('Stream close...');
    this.connected = false;
  }.bind(this);
  this.connected = true;
};

Rutty.prototype.run = function() {
  this.io = this.argv_.io.push();

  this.io.onVTKeystroke = this.sendString_.bind(this);
  this.io.sendString = this.sendString_.bind(this);
  this.io.onTerminalResize = this.onTerminalResize.bind(this);
};

Rutty.prototype.sendString_ = function(str) {
  if (!this.connected || !this.consoleUid) {
    return;
  }

  if (this.sendingSweep === null) {
    this.sendingSweep = true;

    var oReq = new XMLHttpRequest();
    oReq.onload = function(e) {
      this.sendingSweep = null;
      if (this.pendingString.length > 0) {
        var joinedPendingStdin = this.pendingString.join('');
        this.pendingString = [];
        this.sendString_(joinedPendingStdin);
      }
    }.bind(this);
    oReq.onerror = function(e) {
      this.source.close();
      this.connected = false;
    }.bind(this);

    var formData = new FormData();
    var in_d = JSON.stringify({data: str});
    formData.append('in', in_d);
    formData.append('socket', this.socket);
    oReq.open('POST', this.terminalForm.action + '/stdin', true);
    oReq.send(formData);
  } else {
    this.pendingString.push(str);
  }
};

Rutty.prototype.onTerminalResize = function(cols, rows) {
  if (!this.connected || !this.consoleUid) {
    return;
  }

  if (this.sendingResize) {
    //clearTimeout(this.sendingResize);
    //this.sendingResize.abort();
    this.pendingResize.push([cols, rows]);
  } else {
    var oReq = new XMLHttpRequest();
    oReq.onload = function(e) {
      this.sendingResize = null;
      if (this.pendingResize.length > 0) {
        var lastResize = this.pendingResize.pop();
        this.pendingResize = [];
        this.onTerminalResize(lastResize[0], lastResize[1]); // only send the latest pendingResize
      }
    }.bind(this);

    var formData = new FormData();
    formData.append('rows', rows);
    formData.append('cols', cols);
    formData.append('socket', this.socket); //TODO: figure out socket params passing, use session
    oReq.open('POST', this.terminalForm.action + '/resize', true);
    oReq.send(formData);

    this.sendingResize = oReq;
  }
};

var initTerminal = function(terminalElement) {
  if (terminalElement.dataset.status != 'close') {
    var child = null;
    while(terminalElement.firstChild) {
      child = terminalElement.removeChild(terminalElement.firstChild);
    }

    var term = null;
    var ws = null;

    lib.init(function() {

      term = new hterm.Terminal();
      term.decorate(terminalElement);

      term.setWidth(20);
      term.setHeight(10);

      term.setCursorPosition(0, 0);
      term.setCursorVisible(true);
      term.prefs_.set('ctrl-c-copy', true);
      term.prefs_.set('use-default-window-copy', true);

      var aRutty = function(argv) {
        return new Rutty(argv, terminalElement);
      };

      term.runCommandClass(aRutty);

      term.command.onTerminalResize(
        term.screenSize.width,
        term.screenSize.height
      );
    });
  }
};

window.addEventListener('load', function(documentLoadedEvent) {
  var terminal = document.getElementById("terminal");
  initTerminal(terminal);
  console.log('foo');
});
EOJS
end

def index
  "<html>" +
    "<head>" +
      "<link rel='icon' href='data:;base64,iVBORw0KGgo='>" +
      "<style>html, body { background: black; margin: 0; padding: 0; }</style>" +
      "<script src='hterm'></script>" +
    "</head>" +
    "<body>" +
      "<form id='terminal' action='/terminal' data-socket='init' data-console='init'/>" +
      "<script>#{rutty}</script>" +
    "</body>" +
  "</html>"
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

    if offset.is_a?(Fixnum)

      case phr.path
        when "/"
          puts "index"
          response = index

          c.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n#{response}")
          c.close

        when "/hterm"
          puts "/hterm"
          response = hterm

          c.write("HTTP/1.1 200 OK\r\nContent-Type: text/javascript\r\nContent-Length: #{response.length}\r\nConnection: close\r\n\r\n")
          
          response.each_char do |chr|
            c.write(chr)
          end

          c.close

        when "/terminal?socket=init"
          c.write("HTTP/1.1 200 OK\r\nConnection: keep-alive\r\nContent-Type: text/event-stream\r\n\r\nretry: 15000\r\n\r\n")

          ps = UV::Process.new({
            'file' => '/usr/local/bin/htop',
            'args' => [] 
          })

          other_tty = UV::TTY.new(0, 1)
          other_tty.set_mode(0)
          winsize = other_tty.get_winsize
          puts winsize

          ps.stdin_pipe = UV::Pipe.new(0).open(other_tty.fileno) #(1)
          ps.stdout_pipe = UV::Pipe.new(0)

          ps.spawn do |sig|
            puts "exit #{sig}"
            c.close
          end

          ps.stdout_pipe.read_start do |b|
            c.write("data: #{{'raw' => b.codepoints}.to_json}\r\n\r\n")
          end

          ps.kill(0)

        when "/terminal/resize"
          c.write("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
          c.close

      else
        puts :method, offset, phr.method.inspect
        puts phr.path.inspect
        puts phr.minor_version.inspect
        puts phr.headers.inspect
      end

=begin
      ps = UV::Process.new({
        'file' => 'htop',
        'args' => [] 
      })
      ps.stdin_pipe = UV::Pipe.new(0)
      ps.stdout_pipe = UV::Pipe.new(0)

      ps.spawn do |sig|
        puts "exit #{sig}"
      end

      ps.stdout_pipe.read_start do |b|
        puts b
      end

      #c.write("Content-Type: text/plain\r\n\r\nOK")
      #c.close
=end
    elsif offset == :parser_error
      puts :closed
      c.close
    end
  }
}

UV.run
