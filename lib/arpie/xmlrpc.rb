require 'xmlrpc/create'
require 'xmlrpc/parser'
require 'xmlrpc/config'

module Arpie

  class XMLRPCProtocol < Protocol
    private_class_method :new

    attr_accessor :writer
    attr_accessor :parser

    def setup
      @writer ||= XMLRPC::Create.new
      @parser ||= XMLRPC::XMLParser::REXMLStreamParser.new
    end
    private :setup

  end

  # A XMLRPC Protocol based on rubys xmlrpc stdlib.
  # This does not encode HTTP headers; usage together with
  # a real webserver is advised.
  class XMLRPCClientProtocol < XMLRPCProtocol
    public_class_method :new

    def to object
      setup
      raise ArgumentError, "Can only encode Arpie::RPCall" unless
        object.is_a?(Arpie::RPCall)

      @writer.methodCall((object.ns.nil? ? '' : object.ns + '.') + object.meth, *object.argv)
    end

    def from binary
      setup
      yield @parser.parseMethodResponse(binary)[1]
    end
  end

  class XMLRPCServerProtocol < XMLRPCProtocol
    public_class_method :new

    def to object
      setup
      case object
        when Exception
          # TODO: wrap XMLFault
          raise NotImplementedError, "Cannot encode exceptions"

        else
          @writer.methodResponse(true, object)
      end
    end

    def from binary
      setup
      vv = @parser.parseMethodCall(binary)
      ns, meth = vv[0].split('.')
      meth.nil? and begin meth, ns = ns, nil end
      yield RPCall.new(ns, meth, vv[1])
    end
  end

  # This simulates a very basic HTTP XMLRPC client/server.
  # It is not recommended to use this with production code.
  class HTTPTestProtocol < Protocol
    CAN_SEPARATE_MESSAGES = true

    private_class_method :new

    def from binary
      # Simply strip all HTTP headers.
      binary && binary.size > 0 or incomplete!
      header, body_and_rest = binary.split(/\r\n\r\n/, 2)
      header && body_and_rest or incomplete!

      header =~ /^\s*content-length:\s+(\d+)$\s*/xi or stream_error! "No content-length was provided."
      content_length = $1.to_i

      content_length <= 0 
      body_and_rest.size >= content_length or incomplete!

      body = body_and_rest[0, content_length]

      yield body

      header.size + 4 + content_length
    end
  end

  class HTTPClientTestProtocol < HTTPTestProtocol
    public_class_method :new

    def to object
      "GET / HTTP/1.[01]\r\nContent-Length: #{object.size}\r\n\r\n" + object
    end
 
  end

  class HTTPServerTestProtocol < HTTPTestProtocol
    public_class_method :new

    def to object
      "HTTP/1.0 200 OK\r\nContent-Length: #{object.size}\r\n\r\n" + object
    end
  end
end
