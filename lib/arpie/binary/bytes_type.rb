module Arpie
  class BytesBinaryType < BinaryType
    def initialize pack_string, force_opts = {}
      @pack_string = pack_string
      @force_opts = force_opts
    end

    def binary_size opts
      opts = @force_opts.merge(opts || {})
      if opts[:sizeof]
        len_handler = Binary.get_type_handler(opts[:sizeof])
        len_handler.binary_size(opts[:sizeof_opts])
      elsif opts[:length]
        opts[:length]
      else
        nil
      end
    end

    def from binary, opts
      opts = (opts || {}).merge(@force_opts)
      if opts[:sizeof]
        len_handler = Binary.get_type_handler(opts[:sizeof])
        len, len_size = len_handler.from(binary, opts[:sizeof_opts])
        binary.size >= len_size + len or incomplete!

        [binary.unpack("x#{len_size} #{@pack_string}#{len}")[0], len_size + len]

      elsif opts[:length]
        len = case opts[:length]
          when :all
            if @pack_string == "Z"
              npos = binary.index("\000") or raise EIncomplete
              npos + 1
            else
              binary.size
            end
          when Symbol
            opts[:object].send(opts[:length])
          else
            opts[:length]
          end
        binary.size >= len or incomplete!
        [binary.unpack("#{@pack_string}#{len}")[0], len]

      else
        raise ArgumentError, "need one of [:sizeof, :length]"
      end

    end

    def to object, opts
      opts = (opts || {}).merge(@force_opts)
      if opts[:sizeof]
        len_handler = Binary.get_type_handler(opts[:sizeof])
        len_handler.respond_to?(:pack_string) or raise ArgumentError,
          "#{self.class}#to: needs a PackStringType parameter for length"

        [object.size, object].pack("#{len_handler.pack_string} #{@pack_string}*")

      elsif opts[:length]
        len = case opts[:length]
          when :all
            "*"
          when Symbol
            "*"
          else
            opts[:length]
        end
        [object].pack("#{@pack_string}#{len}")

      else
        raise ArgumentError, "need one of [:sizeof, :length]"
      end

    end
  end

  Binary.register_type(BytesBinaryType.new("a", :length => 1), :char)
  Binary.register_type(BytesBinaryType.new("a"), :bytes)
  Binary.register_type(BytesBinaryType.new("A"), :string)
  Binary.register_type(BytesBinaryType.new("Z", :length => :all), :nstring)

  Binary.register_type(BytesBinaryType.new("M"), :quoted_printable)
  Binary.register_type(BytesBinaryType.new("m"), :base64)
  Binary.register_type(BytesBinaryType.new("u"), :uuencoded)
end
