#!/usr/bin/env ruby

# this sorta is a web-server

UV.disable_stdio_inheritance

begin

@tty = UV::TTY.new(1, 1)

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
    console.log("onmessage", event.data);

    var msg = JSON.parse(event.data);

    if (msg.raw && msg.raw.length > 0) { // see: https://github.com/flori/json for discussion on `to_json_raw_object`
      var decoded = '';
      for (var i=0; i<msg.raw.length; i++) {
      //  //NOTE: what is the difference here?
        decoded += String.fromCodePoint(msg.raw[i]);
      //    decoded += String.fromCharCode(msg.raw[i]); // & 0xff ??
      }
      console.log(decoded);

      //var decoded = msg.raw;

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
@index ||= <<EOJS
  <!DOCTYPE html>
  <html>
    <head>
      <link rel='icon' href='data:;base64,iVBORw0KGgo='>
      <style>html, body { background: black; margin: 0; padding: 0; }</style>
      <script>#{hterm}</script>
    </head>
    <body>
      <form id='terminal' action='/terminal' data-socket='init' data-console='init'/>
      <script>#{rutty}</script>
    </body>
  </html>
EOJS
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
          puts "/"

          response = index

          c.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: #{response.length}\r\nConnection: close\r\n\r\n#{response}")

          c.shutdown

        when "/terminal?socket=init"
          puts "/terminal?socket=init"

          c.write("HTTP/1.1 200 OK\r\nConnection: keep-alive\r\nContent-Type: text/event-stream\r\n\r\nretry: 99999\r\n\r\n")

          @other_tty ||= nil

          @ps ||= begin
            ps = UV::Process.new({
              'file' => '/bin/bash',
              'args' => ['-i', '-l'] 
            })

            @other_tty = UV::TTY.new(1, 1)
            @other_tty.set_mode(0)

            ps.stdin_pipe = UV::Pipe.new(0).open(@other_tty.fileno)
            ps.stdout_pipe = UV::Pipe.new(0)
            ps.stderr_pipe = UV::Pipe.new(0)

            ps.spawn do |sig|
              puts "exit #{sig}"
            end

            ps
          end

          @ps.stderr_pipe.read_start do |b|
            puts b.inspect
          end

          @ps.stdout_pipe.read_start do |b|
            begin
              if b
                c.write("data: " + {'raw' => b.codepoints.reject { |c| c > 64 }}.to_json + "\r\n\r\n")
              end
            rescue UVError => uv_error
              puts uv_error.inspect
              c.shutdown
            end
          end

          @ps.kill(0)

        when "/terminal/resize"
          puts "/terminal/resize"

          c.write("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
          c.shutdown

        when "/terminal/stdin"
          puts "/terminal/stdin"

          c.write("HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n")
          c.shutdown

          puts phr.inspect
          puts ss[offset..-1]

      else
        puts :method, offset, phr.method.inspect
        puts phr.path.inspect
        puts phr.minor_version.inspect
        puts phr.headers.inspect
      end

    elsif offset == :parser_error
      puts :closed
      c.shutdown
    end
  }
}

UV.run
