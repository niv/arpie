require 'shellwords'
require 'yaml'

module Arpie
  MTU = 1024
  class StreamError < IOError ; end

  class RPCall < Struct.new(:ns, :meth, :argv, :uuid); end

  class ProtocolChain

    # Array of Protocols.
    attr_reader :chain

    # String holding all read, but yet unparsed bytes.
    attr_reader :buffer

    # The endpoint class of this Protocol.
    # Defaults to Arpie::Endpoint
    attr_accessor :endpoint_class

    # Create a new Chain. Supply an Array of Protocol
    # instances, where the leftmost is the innermost.
    #
    # Example:
    #   MarshalProtocol.new, SizedProtocol.new
    # would wrap marshalled data inside SizedProtocol.
    def initialize *protocols
      protocols.size > 0 or raise ArgumentError, "Specify at least one protocol."
      protocols[-1].class::CAN_SEPARATE_MESSAGES or
        raise ArgumentError,
          "The outermost protocol needs to be able to " +
          "separate messages in a stream (#{protocols.inspect} does not)."

      @endpoint_class = Arpie::Endpoint

      @chain = protocols
      @buffer = ""
    end

    # Convert the given +message+ to wire format by
    # passing it through all protocols in the chain.
    def to message
      @chain.inject(message) {|msg, p|
        p.to(msg)
      }
    end

    # Convert the given +binary+ to message format
    # by passing it through all protocols in the chain.
    # May rise EIncomplete or EStreamError, in which case
    # +binary+ does not satisfy one of the protocols.
    def from binary
      @chain.reverse.inject(binary) {|msg, p|
        p.from(msg) rescue case $!
          when ETryAgain
            retry

          else
            raise
        end
      }
    end

    # Read a message from +io+. Block until all protocols
    # agree that a message has been received.
    #
    # May rise EIncomplete when a protocol in the middle of
    # the chain cannot be satisfied
    #
    # Returns the message.
    def read_message io
      message = @buffer

      @chain.reverse.each_with_index {|p, p_index|
        message, cut_to_index = message, nil
        loop do
          case catch(:int) {
            message, cut_to_index = p.from(message)
            nil
          }
            when nil
              break

            when :incomplete
              raise $!, "#{e.to_s}; only the first protocol in the chain can request more data." if
                p_index != 0

              select([io])
              @buffer << io.readpartial(MTU) rescue raise $!.class,
                "#{$!.to_s}; unparseable bytes remaining in buffer: #{@buffer.size}"

            when :try_again
              # do nothing, loop over

            else
              raise "Unknown :int: #{cmd.inspect}"
          end
        end

        if p_index == 0
          if cut_to_index.nil? || cut_to_index < 0
            raise "Protocol '#{p.class.to_s}'implementation faulty: " +
              "from did return an invalid cut index: #{cut_to_index.inspect}."
          else
            @buffer[0, cut_to_index] = ""
          end
        end
      }

      message
    end

    # Write +message+ to +io+.
    def write_message io, message
      io.write(to message)
    end

    def reset
      @buffer = ""
    end
  end

  # A Protocol converts messages (which are arbitary objects)
  # to a suitable on-the-wire format, and back.
  class Protocol
    # Set this to true in child classes which implement
    # message separation within a stream.
    CAN_SEPARATE_MESSAGES = false

    # Convert obj to on-the-wire format.
    def to obj
      obj
    end

    # Convert +binary+ from on-the-wire-format.
    #
    # Returns [object, index].
    #
    # index is the index within +binary+ where
    # +object+ ends, and is mandatory when
    # CAN_SEPARATE_MESSAGES is true for this class.
    def from binary
      [binary, 0]
    end

    # Call this within Protocol#from to restart from the
    # beginning (of the current buffer).
    def again
      throw :int, :try_again
    end

    # Tell the protocol chain that the given chunk of data
    # is not enough to construct a whole message.
    # This breaks out of Protocol#from.
    def incomplete
      throw :int, :incomplete
    end

    # Call this if you think the stream has been corrupted, or
    # non-protocol data arrived.
    # This breaks out of Protocol#from.
    def stream_error
      raise StreamError, "#{self.class.to_s} thinks the data is bogus."
    end
  end


  # A sample binary protocol, which simply prefixes each message with the
  # size of the data to be expected.
  class SizedProtocol < Protocol
    CAN_SEPARATE_MESSAGES = true

    def from binary
      sz = binary.unpack('Q')[0] or incomplete
      binary.size >= sz + 8 or incomplete
      [binary[8, sz], 8 + sz]
    end

    def to object
      [object.size, object].pack('Qa*')
    end
  end

  # A procotol that simply Marshals all data sent over
  # this protocol. Served as an example, but a viable
  # choice for ruby-only production code.
  # Messages are arbitary objects.
  class MarshalProtocol < Protocol
    def to object
      Marshal.dump(object)
    end

    def from binary
      Marshal.load(binary)
    end
  end

  # A simple separator-based protocol. This can be used to implement
  # newline-delimited communication.
  class SeparatorProtocol < Protocol
    CAN_SEPARATE_MESSAGES = true
    attr_accessor :separator

    def initialize separator = "\n"
      @separator = separator
    end

    def from binary
      idx = binary.index(@separator) or incomplete
      [binary[0, idx], @separator.size + idx]
    end

    def to object
      object.to_s + @separator
    end
  end

  # A linebased-protocol, which does shellwords-escaping/joining
  # on the lines; messages sent are arrays of parameters.
  # Note that all parameters are expected to be strings.
  class ShellwordsProtocol < Protocol
    def to object
      Shellwords.join(object.map {|x| x.to_s })
    end

    def from binary
      Shellwords.shellwords(binary)
    end
  end

  # A protocol which encodes objects into YAML representation.
  # Messages are arbitary yaml-encodable objects.
  class YAMLProtocol < Protocol
    CAN_SEPARATE_MESSAGES = true

    def to object
      YAML.dump(object) + "...\n"
    end

    def from binary
      index = binary =~ /^\.\.\.$/x or incomplete
      [YAML.load(binary[0, index]), 4 + index]
    end
  end
end
