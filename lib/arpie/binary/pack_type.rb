module Arpie
  class PackBinaryType < BinaryType
    attr_reader :pack_string

    def binary_size opts
      opts = @force_opts.merge(opts || {})
      PackBinaryType.length_of(@pack_string + (opts[:length] || 1).to_s)
    end

    def self.length_of format
      length = 0
      format.scan(/(\S_?)\s*(\d*)/).each do |directive, count|
        count = count.to_i
        count = 1 if count == 0

        length += case directive
        when 'A', 'a', 'C', 'c', 'Z', 'x'
          count
        when 'B', 'b'
          (count / 8.0).ceil
        when 'D', 'd', 'E', 'G'
          count * 8
        when 'e', 'F', 'f', 'g'
          count * 4
        when 'H', 'h'
          (count / 2.0).ceil
        when 'I', 'i', 'L', 'l', 'N', 'V'
          count * 4
        when 'n', 'S', 's', 'v'
          count * 2
        when 'Q', 'q'
          count * 8
        when 'X'
          count * -1
        else
          raise ArgumentError, "#{directive} is not supported"
        end
      end

      length
    end

    def initialize pack_string, force_opts = {}
      @pack_string = pack_string
      @force_opts = force_opts
    end

    def from binary, opts
      opts = @force_opts.merge(opts || {})
      binary && binary.size >= binary_size(opts) or incomplete!
      len = opts[:length] || 1
      pack_string = @pack_string + len.to_s
      value = binary.unpack(pack_string)[0]
      value += opts[:mod] if opts[:mod]
      check_limit value, opts[:limit]

      [value, binary_size(opts)]
    end

    def to object, opts
      opts = @force_opts.merge(opts || {})
      object.nil? and bogon! nil,"nil object given"
      object -= opts[:mod] if opts[:mod]
      len = opts[:length] || 1
      pack_string = @pack_string + len.to_s
      [object].pack(pack_string)
    end

  end

  Binary.register_type(PackBinaryType.new('c'), :uint8)
  Binary.register_type(PackBinaryType.new("c"), :int8)
  Binary.register_type(PackBinaryType.new("C"), :uint8)
  Binary.register_type(PackBinaryType.new("s"), :int16)
  Binary.register_type(PackBinaryType.new("S"), :uint16)
  Binary.register_type(PackBinaryType.new("i"), :int32)
  Binary.register_type(PackBinaryType.new("I"), :uint32)
  Binary.register_type(PackBinaryType.new("q"), :int64)
  Binary.register_type(PackBinaryType.new("Q"), :uint64)

  Binary.register_type(PackBinaryType.new("l"), :long32)
  Binary.register_type(PackBinaryType.new("L"), :ulong32)

  Binary.register_type(PackBinaryType.new("n"), :nint16)
  Binary.register_type(PackBinaryType.new("N"), :nint32)
  Binary.register_type(PackBinaryType.new("v"), :lint16)
  Binary.register_type(PackBinaryType.new("V"), :lint32)

  Binary.register_type(PackBinaryType.new("d"), :double)
  Binary.register_type(PackBinaryType.new("E"), :ldouble)
  Binary.register_type(PackBinaryType.new("G"), :ndouble)

  Binary.register_type(PackBinaryType.new("f"), :float)
  Binary.register_type(PackBinaryType.new("e"), :lfloat)
  Binary.register_type(PackBinaryType.new("g"), :nfloat)

  Binary.register_type(PackBinaryType.new("B"), :msb_bitfield)
  Binary.register_type(PackBinaryType.new("b"), :lsb_bitfield)

  class BitBinaryType < Arpie::BinaryType
    def from binary, opts
      len = opts[:length] || 1
      len = binary.size if len == :all
      binary.size >= len or incomplete!
      b = binary.split("")[0,len].map {|x|
        x == "1"
      }
      b = b[0] if b.size == 1
      [b, len]
    end

    def to object, opts
      object = [object] if object.is_a?(TrueClass) || object.is_a?(FalseClass)
      object.map {|x| x == true ? "1" : "0" }.join("")
    end
  end

  Arpie::Binary.register_type(BitBinaryType.new, :bit)
end
