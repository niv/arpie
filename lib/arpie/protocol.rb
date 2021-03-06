require 'shellwords'
require 'psych' if RUBY_VERSION =~ /^1.9/
require 'yaml'
require 'zlib'

module Arpie
  MTU = 1024

  # A ProtocolChain wraps one or more Protocols to provide a parser
  # list, into which io data can be fed and parsed packets received; and
  # vice versa.
  class ProtocolChain
    include Arpie

    # Array of Protocols.
    attr_reader :chain

    # String holding all read, but yet unparsed bytes.
    attr_reader :buffer

    # A buffer holding all parsed, but unreturned messages.
    attr_reader :messages

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

      @chain = protocols
      @buffer = ""
      @messages = []
    end

    # Convert the given +message+ to wire format by
    # passing it through all protocols in the chain.
    def to message
      messages = [message]
      @chain.each {|p|
        for_next = []
        messages.each {|msg|
          p.to(msg) do |a|
            for_next << a
          end
        }

        messages = for_next
      }
      messages
    end

    # Convert the given +binary+ to message format
    # by passing it through all protocols in the chain.
    # May raise EStreamError or EIncomplete, in the case that
    # +binary+ does not satisfy one of the protocols.
    #
    # Returns an array of messages, even if only one message
    # was contained.
    def from binary
      r, w = IO.pipe
      w.write(binary)
      w.close
      results = []
      results << read_message(r) until false rescue begin
        r.close
        return results
      end
      raise "Interal error: should not reach this."
    end

    # Read a message from +io+. Block until all protocols
    # agree that a message has been received.
    #
    # Returns the message.
    def read_message io
      return @messages.shift if @messages.size > 0

      messages = [@buffer]
      chain = @chain.reverse
      p_index = 0

      while p_index < chain.size do p = chain[p_index]
        cut_to_index = nil
        messages_for_next = []

        messages.each_with_index do |message, m_index|
          cut_to_index = p.from(message) do |object|
            messages_for_next << object
          end rescue case $!
            when YieldResult
              messages_for_next.concat($!.result)
              next

            when EIncomplete
              if messages.size - 1 - m_index > 0
                next
              else
                raise
              end

            else
              raise
          end
        end rescue case $!
          when EIncomplete
            if p_index == 0
              select([io])
              @buffer << io.readpartial(MTU) rescue raise $!.class,
                "#{$!.to_s}; unparseable bytes remaining in buffer: #{@buffer.size}"
              retry

            else
              p_index = 0
              messages_for_next = []
              messages = [@buffer]
              next # of loop protocol chain
            end

          else
            raise
        end

        if messages_for_next.size == 0
          # Get back to IO level and retry reading more crud
          messages_for_next = [@buffer]
          p_index = -1
        end

        messages = messages_for_next

        if p_index == 0
          if cut_to_index.nil? || cut_to_index < 0
            raise "Protocol '#{p.class.to_s}' implementation faulty: " +
              "from did return an invalid cut index: #{cut_to_index.inspect}."
          else
            @buffer[0, cut_to_index] = ""
          end
        end

        p_index += 1
      end # loop chain

      message = messages.shift
      @messages = messages
      message
    end


    # Write +message+ to +io+.
    def write_message io, *messages
      binary = messages.map {|m| to(m)}
      io.write(binary.flatten.join(""))
    end

    def reset
      @buffer = ""
    end
  end

  # A Protocol converts messages (which are arbitary objects)
  # to a suitable on-the-wire format, and back.
  class Protocol
    include Arpie

    # Set this to true in child classes which implement
    # message separation within a stream.
    CAN_SEPARATE_MESSAGES = false

    # @private
    # The stowbuffer hash used by assemble! No need to touch this, usually.
    attr_reader :stowbuffer
    # @private
    # The meta-information hash used by assemble! No need to touch this, usually.
    attr_reader :metabuffer

    # Convert obj to on-the-wire format.
    def to obj
      yield obj
    end

    # Extract message(s) from +binary+.
    #
    # Yields each message found, with all protocol-specifics stripped.
    #
    # Should call +incomplete+ when no message can be read yet.
    #
    # Must not block by waiting for multiple messages if a message
    # can be yielded directly.
    #
    # Must not return without calling +incomplete+ or yielding a message.
    #
    # Must return the number of bytes these message(s) occupied in the stream,
    # for truncating of the same.
    # Mandatory when CAN_SEPARATE_MESSAGES is true for this class, but ignored
    # otherwise.
    def from binary, &block #:yields: message
      yield binary
      0
    end

    # Stow away a message in this protocols buffer for later reassembly.
    # Optional argument: a token if you are planning to reassemble multiple
    # interleaved/fragmented message streams.
    #
    # If you pass a block, that block will be called; if no block is given,
    # Protocol#assemble will be invoked.
    #
    # Any leftover binaries passed into assemble! that get not returned in
    # the assembler will be discarded; they are assumed to be syntax or framework.
    #
    # +binary+   is the binary packet you want to add to the assembly
    # +token+    is a object which can be used to identify multiple concurrent assemblies (think Hash.keys)
    # +meta+     is a hash containing meta-information for this assembly
    #            each call to assemble! will merge these hashes, and pass them
    #            on to Protocol#assemble
    def assemble! binary, token = :default, meta = {} # :yields: binaries, metadata
      @stowbuffer ||= {}
      @stowbuffer[token] ||= []
      @stowbuffer[token] << binary

      @metabuffer ||= {}
      @metabuffer[token] ||= {}
      @metabuffer[token].merge!(meta)

      assembled = nil

      if block_given?
        assembled = yield(@stowbuffer[token], @metabuffer[token])

      else
        # This raises EIncomplete when not enough messages are there,
        # and passes it straight on to #read_message
        assembled = assemble(@stowbuffer[token], @metabuffer[token])
      end

      @stowbuffer.delete(token)
      @metabuffer.delete(token)
      raise YieldResult, [assembled]
    end

    # Called when we're trying to reassemble a stream of packets.
    #
    # Call incomplete! when not enough data is here to reassemble this stream,
    # and yield all results of the reassembled stream.
    def assemble binaries, meta
      raise NotImplementedError, "Tried to assemble! something, but no assembler defined."
    end
  end

  # A sample binary protocol, which simply prefixes each message with the
  # size of the data to be expected.
  class SizedProtocol < Protocol
    CAN_SEPARATE_MESSAGES = true

    def from binary
      sz = binary.unpack('Q')[0] or incomplete!
      binary.size >= sz + 8 or incomplete!
      yield binary[8, sz]
      8 + sz
    end

    def to object
      yield [object.size, object].pack('Qa*')
    end
  end

  # A procotol that simply Marshals all data sent over
  # this protocol. Served as an example, but a viable
  # choice for ruby-only production code.
  # Messages are arbitary objects.
  class MarshalProtocol < Protocol
    def to object
      yield Marshal.dump(object)
    end

    def from binary
      yield Marshal.load(binary)
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
      idx = binary.index(@separator) or incomplete!
      yield binary[0, idx]

      @separator.size + idx
    end

    def to object
      yield object.to_s + @separator
    end
  end

  # A linebased-protocol, which does shellwords-escaping/joining
  # on the lines; messages sent are arrays of parameters.
  # Note that all parameters are expected to be strings.
  class ShellwordsProtocol < Protocol
    def to object
      raise ArgumentError, "#{self.class.to_s} can only encode arrays." unless
        object.is_a?(Array)
      yield Shellwords.join(object.map {|x| x.to_s })
    end

    def from binary
      yield Shellwords.shellwords(binary)
    end
  end

  # A protocol which encodes objects into YAML representation.
  # Messages are arbitary yaml-encodable objects.
  class YAMLProtocol < Protocol
    def to object
      yield YAML.dump(object)
    end

    def from binary
      yield YAML.load(binary)
      binary.size
    end
  end

  # A transparent zlib stream de/compression protocol.
  class ZlibProtocol < Protocol
    def initialize
      @inflater = Zlib::Inflate.new
      @deflater = Zlib::Deflate.new
    end

    def to object
      yield @deflater.deflate(object) + @deflater.flush
    end

    def from binary
      yield @inflater.inflate(binary)
      binary.size
    end
  end
end
