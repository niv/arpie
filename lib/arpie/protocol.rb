require 'shellwords'
require 'yaml'

module Arpie

  # A Protocol converts messages (which are arbitary objects)
  # to a suitable on-the-wire format, and back.
  class Protocol
    MTU = 1024

    private_class_method :new

    # The endpoint class of this Protocol.
    # Defaults to Arpie::Endpoint
    attr_accessor :endpoint_class

    def initialize
      @endpoint_class = Arpie::Endpoint
      @buffer = ""
      reset
    end

    # Read a message from +io+. Block until a message
    # has been received.
    # Returns the message.
    def read_message io
      until idx = complete?(@buffer) do
        select([io], nil, nil, 0.1) or next
        @buffer << io.readpartial(MTU)
      end

      message, @buffer = from(@buffer[0, idx]), @buffer[idx .. -1] || ""

      message
    end

    # Write a partial message part, as it is seen on the wire.
    # You do not need to call this usually; write_message does
    # the proper conversion for you.
    def write_raw_partial io, message
      io.write(message)
    end

    # Write +message+ to +io+.
    def write_message io, message
      io.write(to message)
    end

    # Convert obj to on-the-wire format.
    def to obj
      obj
    end

    # Convert obj from on-the-wire-format.
    def from obj
      obj
    end

    # Returns a Fixnum if the given obj contains a complete message.
    # The Fixnum is the index up to where the message runs; the rest
    # is assumed to be (part of) the next message.
    # Returns nil if obj does not describe a complete message (eg,
    # more data needs to be read).
    def complete? obj
      nil
    end

    # Reset all state buffers. This is usually called
    # when the underlying connection drops, and any half-read
    # messages need to be discarded.
    def reset
      @buffer = ""
    end
  end

  # A simple separator-based protocol. This can be used to implement
  # newline-delimited communication.
  class SeparatorProtocol < Protocol
    public_class_method :new

    attr_accessor :separator

    def initialize separator = "\n"
      super()
      @separator = separator
    end

    def complete? obj
      obj.index(@separator)
    end

    def from obj
      obj.gsub(/#{Regexp.escape(@separator)}$/, "")
    end

    def to obj
      obj + @separator
    end
  end

  # A linebased-protocol, which does shellwords-escaping/joining
  # on the lines; messages sent are arrays of parameters.
  # Note that all parameters are expected to be strings.
  class ShellwordsProtocol < SeparatorProtocol
    def to obj
      super Shellwords.join(obj)
    end

    def from obj
      Shellwords.shellwords(super obj)
    end
  end

  # A sample binary protocol, which simply prefixes each message with the
  # size of the data to be expected.
  class SizedProtocol < Protocol
    public_class_method :new

    def initialize
      super
      @max_message_size = 1024 * 1024
    end

    def complete? obj
      sz = obj.unpack("Q")[0]
      sz && obj.size >= sz + 8 ? sz + 8 : nil
    end

    def from obj
      sz, data = obj.unpack("Qa*")
      data
    end

    def to obj
      [obj.size, obj].pack("Qa*")
    end
  end

  # A procotol that simply Marshals all data sent over
  # this protocol. Served as an example, but a viable
  # choice for ruby-only production code.
  # Messages are arbitary objects.
  class MarshalProtocol < SizedProtocol
    def to obj
      super Marshal.dump(obj)
    end

    def from obj
      Marshal.load(super obj)
    end
  end

  # A protocol which encodes objects into YAML representation.
  # Messages are arbitary yaml-encodable objects.
  class YAMLProtocol < Arpie::Protocol
    public_class_method :new

    def complete? obj
      obj =~ /\.\.\.$/
    end

    def to obj
      YAML.dump(obj) + "...\n"
    end

    def from obj
      YAML.load(obj)
    end
  end

  # A RPC Protocol encapsulates RPCProtocol::Call
  # messages.
  class RPCProtocol < Protocol

    # A RPC call.
    class Call < Struct.new(:ns, :meth, :argv, :uuid); end
  end

  # A XMLRPC Protocol based on rubys xmlrpc stdlib.
  # This does not encode HTTP headers; usage together with
  # a real webserver is advised.
  class XMLRPCProtocol < RPCProtocol
    public_class_method :new

    require 'xmlrpc/create'
    require 'xmlrpc/parser'
    require 'xmlrpc/config'

    VALID_MODES = [:client, :server].freeze

    attr_reader :mode
    attr_accessor :writer
    attr_accessor :parser

    def initialize mode, writer = XMLRPC::Create, parser = XMLRPC::XMLParser::REXMLStreamParser
      super()
      raise ArgumentError, "Not a valid mode, expecting one of #{VALID_MODES.inspect}" unless
        VALID_MODES.index(mode)

      @mode = mode
      @writer = writer.new
      @parser = parser.new
    end

    def to obj
      case @mode
        when :client
          @writer.methodCall(obj.ns + obj.meth, *obj.argv)

        when :server
          case obj
            when Exception
              # TODO: wrap XMLFault
            else
              @writer.methodResponse(true, obj)
            end
      end
    end

    def from obj
      case @mode
        when :client
          @parser.parseMethodResponse(obj)[1]

        when :server
          vv = @parser.parseMethodCall(obj)
          RPCProtocol::Call.new('', vv[0], vv[1])
      end
    end

    def complete? obj
      case @mode
        when :client
          obj.index("</methodResponse>")
        when :server
          obj.index("</methodCall>")
      end
    end
  end

  # This simulates a very basic HTTP XMLRPC client/server.
  # It is not recommended to use this with production code.
  class HTTPXMLRPCProtocol < XMLRPCProtocol
    def to obj
      r = super
      case @mode
        when :client
          "GET / HTTP/1.[01]\r\nContent-Length: #{r.size}\r\n\r\n" + r
        when :server
          "HTTP/1.0 200 OK\r\nContent-Length: #{r.size}\r\n\r\n" + r
      end
    end

    def from obj
      # Simply strip all HTTP headers.
      header, obj = obj.split(/\r\n\r\n/, 2)
      super(obj)
    end


    def complete? obj
      # Complete if: has headers, has content-length, has data of content-length
      header, body = obj.split(/\r\n\r\n/, 2)

      header =~ /content-length:\s+(\d+)/i or return nil

      content_length = $1.to_i
      body.size == content_length ? header.size + 4 + body.size : nil
    end
  end
end
