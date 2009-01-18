module Arpie

  # A Protocol converts messages (which are arbitary objects)
  # to a suitable on-the-wire format, and back.
  class Protocol
    private_class_method :new

    # Read a message from +io+. Block until a message
    # has been received.
    def read_message io
    end

    # Write a message to +io+.
    def write_message io, message
    end
  end

  # A sample binary protocol, upon which others can expand.
  # The on the wire format is simply the data, prefixed
  # with data.size.
  class SizedProtocol < Protocol
    def initialize
      @max_message_size = 1024 * 1024
    end

    def read_message io
      sz = io.read(8)
      expect = sz.unpack("Q")[0]
      data = io.read(expect)
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
