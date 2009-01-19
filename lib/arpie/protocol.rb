module Arpie

  # A Protocol converts messages (which are arbitary objects)
  # to a suitable on-the-wire format, and back.
  class Protocol
    private_class_method :new

    # Read a message from +io+. Block until a message
    # has been received.
    # Returns [message, transport_id, serial].
    def read_message io
    end

    # Write +message+ to +io+, with an optional +serial+.
    def write_message io, message, transport_id = 0, serial = 0
    end
  end

  # A sample binary protocol, upon which others can expand.
  class SizedProtocol < Protocol
    def initialize
      @max_message_size = 1024 * 1024
    end

    def read_message io
      sz = io.read(24) or raise EOFError, "eof on io while reading header"
      raise EOFError if sz.nil?
      expect, t_id, serial = sz.unpack("QQQ")

      raise EOFError if expect < 0 || expect > @max_message_size

      data = io.read(expect) or raise EOFError, "eof on io while reading data"
      raise EOFError if sz.nil? || data.size != expect

      $stderr.puts "read: #{data.inspect}, tid = #{t_id}, serial = #{serial}" if $DEBUG
      [data, t_id, serial]
    end

    def write_message io, message, transport_id = 0, serial = 0
      $stderr.puts "write: #{message.inspect}, tid = #{transport_id}, serial = #{serial}" if $DEBUG
      io.write([message.size, transport_id, serial, message].pack("QQQa*"))
    end
  end


  # A procotol that simply Marshals all data sent over
  # this protocol. Served as an example, but a viable
  # choice for ruby-only production code.
  class MarshalProtocol < SizedProtocol
    public_class_method :new

    def read_message io
      message, transport_id, serial = super(io)
      [Marshal.load(message), transport_id, serial]
    end

    def write_message io, message, transport_id = 0, serial = 0
      super io, Marshal.dump(message), transport_id, serial
    end
  end
end
