require 'shellwords'
require 'yaml'

module Arpie

  # A Protocol converts messages (which are arbitary objects)
  # to a suitable on-the-wire format, and back.
  class Protocol
    MTU = 1024

    private_class_method :new

    attr_reader :message

    def initialize
      @message = nil
      @buffer = ""
      reset
    end

    # Reads data from +io+. Returns true, if a whole
    # message has been read, or false if more data is needed.
    # The read message can be retrieved via Protocol#message.
    def read_partial io
      @buffer << io.readpartial(MTU)

      if idx = complete?(@buffer)
        @message = from @buffer[0, idx]
        @buffer = @buffer[idx, -1] || ""
        return true
      end

      return false
    end

    # Read a message from +io+. Block until a message
    # has been received.
    # Returns the message.
    def read_message io
      select([io]) until read_partial(io)
      @message
    end

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
      @message = nil
      @buffer = ""
    end

    def endpoint_klass
      Arpie::Endpoint
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
      obj.size == sz + 8 ? sz + 8 : nil
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
end
