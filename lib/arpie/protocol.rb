module Arpie

  # A Protocol converts messages (which are arbitary objects)
  # to a suitable on-the-wire format, and back.
  class Protocol
    private_class_method :new

    # Read a message from +io+. Block until a message
    # has been received.
    # Returns the message.
    def read_message io
    end

    # Write +message+ to +io+
    def write_message io, message
    end

    def endpoint_klass
      Arpie::Endpoint
    end
  end

  # A sample binary protocol, upon which others can expand.
  class SizedProtocol < Protocol
    def initialize
      @max_message_size = 1024 * 1024
    end

    def read_message io
      sz = io.read(8) or raise EOFError, "eof on io while reading header"
      raise EOFError if sz.nil?
      expect = sz.unpack("Q")[0]

      raise EOFError if expect < 0 || expect > @max_message_size


      data = io.read(expect) or raise EOFError, "eof on io while reading data"
      raise EOFError if sz.nil? || data.size != expect

      data
    end

    def write_message io, message
      io.write([message.size, message].pack("Qa*"))
    end
  end


  # A procotol that simply Marshals all data sent over
  # this protocol. Served as an example, but a viable
  # choice for ruby-only production code.
  class MarshalProtocol < SizedProtocol
    public_class_method :new

    def read_message io
      Marshal.load super(io)
    end

    def write_message io, message
      super io, Marshal.dump(message)
    end
  end
end
