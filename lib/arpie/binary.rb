module Arpie

  # A Binary is a helper to convert arbitary bitlevel binary data
  # to and from ruby Struct-lookalikes.
  #
  # Here's an example:
  #
  #  class Test < Arpie::Binary
  #    describe "I am a test"
  #
  #    field :a, :uint8
  #    field :b, :bytes, :sizeof => :nint16
  #  end
  #
  # This will allow you to parse binary blocks consisting of:
  # - a byte
  # - a network-order int (16 bit)
  # - a string which length' is the given int
  # Rinse and repeat.
  #
  # For all available data types, please look into the source
  # file of this class at the bottom.
  #
  # Writing new types is easy enough, (see BinaryType).
  class Binary
    @@fields ||= {}
    @@attributes ||= {}
    @@description ||= {}

    attr_reader :consumed_bytes # :nodoc:

    def initialize attributes = {}, consumed_bytes = nil
      @attributes, @consumed_bytes, = attributes, consumed_bytes
      if block_given?
        yield self
      end
    end

    def inspect #:nodoc:
      desc = " " + @@description[self.class].inspect if @@description[self.class]
      "#<#{self.class.to_s}#{desc} #{@attributes.inspect}>"
    end

    def method_missing m, *a
      m.to_s =~ /^(.+?)(=?)$/ or super
      at = $1.to_sym
      self.class.attribute?(at) or super
      if $2 == "="
        a.size == 1 or raise ArgumentError
        @attributes[at] = a[0]
      else
        @attributes[at]
      end
    end

    # This registers a new field with this binary.
    def self.register_field handler, *klass_aliases
      klass_aliases.each do |klass|
        @@fields[klass] = handler
      end
    end

    # Returns true if this Binary has the named +attribute+.
    def self.attribute? attribute
      @@attributes[self] or return false
      @@attributes[self].select {|name,klass,opts|
        name.to_sym == attribute.to_sym
      }.size > 0
    end

    # Returns the BinaryType handler class for type +klass+.
    def self.get_field_handler klass
      @@fields[klass] or raise ArgumentError, "#{self}: No such field type: #{klass.inspect}"
    end

    # You can use this to provide a short description of this Binary.
    # It will be shown when calling Binary.inspect.
    def self.describe text
      @@description[self] = text
    end

    # Specify that this Binary has a field of type +klass+.
    # See the class documentation for usage.
    def self.field name, klass = nil, opts = {}
      klass.nil? && !block_given? and raise ArgumentError,
        "You need to specify an inline handler if no type is given."
      inline_handler = nil

      if block_given?
        yield inline_handler = Class.new(Arpie::Binary)
      end

      if klass.nil?
        klass, inline_handler = inline_handler, nil
      end

      if klass.is_a?(BinaryType)
        handler = get_field_handler klass
        (opts.keys & handler.required_opts) == handler.required_opts or raise ArgumentError,
          "#{self}: #{name.inspect} as type #{klass.inspect} requires options: #{handler.required_opts.inspect}"
      end

      @@attributes[self] ||= []
      @@attributes[self] << [name.to_sym, klass, opts, inline_handler]
    end

    # Parse the given +binary+, which is a string, and return an instance of this class.
    # Will raise Arpie::EIncomplete when not enough data is available in +binary+ to construct
    # a complete Binary.
    def self.from binary
      @@attributes[self] ||= []
      at = {}

      consumed_bytes = 0
      @@attributes[self].each {|name, klass, opts, inline_handler|

        if klass.is_a?(Symbol)
          handler = get_field_handler klass

          at[name], consumed =
            handler.from(self, binary[consumed_bytes .. -1], opts) rescue case $!
              when EIncomplete
                raise $!, "#{$!.to_s}, #{self}#from needs more data for #{name.inspect}"
              else
                raise
            end

            if inline_handler
              at[name] = inline_handler.from(at[name])
            end

          consumed_bytes += consumed

        elsif klass.is_a?(Class) # Arpie::Binary
          at[name] = klass.from(binary[consumed_bytes .. -1])
          consumed_bytes += at[name].consumed_bytes

        else
          raise ArgumentError, "Unknown field-type #{klass.inspect}"

        end
      }
      new at, consumed_bytes
    end

    # Recursively convert this Binary to wire format.
    def to
      r = []
      @@attributes[self.class].each {|name, klass, opts, inline_handler|
        handler = self.class.get_field_handler klass

        if klass.is_a?(Symbol)
          val = self.respond_to?(name) ?
            self.send(name) :
            val = @attributes[name] or raise "#{self.class}: attribute #{name.inspect} is nil, cannot #to"

          if inline_handler
            val = val.to
          end

          r << handler.to(self, val, opts)

        elsif klass.is_a?(Class)
          r << klass.to

        else
          raise ArgumentError, "Unknown field-type #{klass.inspect}"

        end
      }

      r = r.join('')
      self.respond_to?(:post_to) && r = self.send(:post_to, r)
      r
    end
  end

  class BinaryType
    def binary_size opts
      nil
    end

    def incomplete!
      raise EIncomplete
    end

    def required_opts
      []
    end

    # Return [object, len]
    def from for_klass, binary, opts
      raise NotImplementedError
    end

    # Return [binary]
    def to for_object, object, opts
      raise NotImplementedError
    end
  end

  class PackBinaryType < BinaryType
    attr_reader :pack_string

    def binary_size opts
      @binary_size
    end

    def self.length_of format
      length = 0
      format.scan(/(\S_?)\s*(\d*)/).each do |directive, count|
        count = count.to_i
        count = 1 if count == 0

        length += case directive
        when 'A', 'a', 'C', 'c', 'Z', 'x' : count
        when 'B', 'b' : (count / 8.0).ceil
        when 'D', 'd', 'E', 'G' : count * 8
        when 'e', 'F', 'f', 'g' : count * 4
        when 'H', 'h' : (count / 2.0).ceil
        when 'I', 'i', 'L', 'l', 'N', 'V' : count * 4
        when 'n', 'S', 's', 'v' : count * 2
        when 'Q', 'q' : count * 8
        when 'X' : count * -1
        else raise ArgumentError, "#{self}: #{directive} is not supported"
        end
      end

      length
    end

    def initialize pack_string
      @pack_string = pack_string
      @binary_size = self.class.length_of(pack_string)
    end

    def from for_klass, binary, opts
      binary.size >= @binary_size or incomplete!
      [binary.unpack(@pack_string)[0], @binary_size]
    end

    def to for_object, object, opts
      [object].pack(@pack_string)
    end
  end

  Binary.register_field(PackBinaryType.new('c'), :uint8)
  Binary.register_field(PackBinaryType.new("c"), :int8)
  Binary.register_field(PackBinaryType.new("C"), :uint8)
  Binary.register_field(PackBinaryType.new("s"), :int16)
  Binary.register_field(PackBinaryType.new("S"), :uint16)
  Binary.register_field(PackBinaryType.new("i"), :int32)
  Binary.register_field(PackBinaryType.new("I"), :uint32)
  Binary.register_field(PackBinaryType.new("q"), :int64)
  Binary.register_field(PackBinaryType.new("Q"), :uint64)

  Binary.register_field(PackBinaryType.new("l"), :long64)
  Binary.register_field(PackBinaryType.new("L"), :ulong64)

  Binary.register_field(PackBinaryType.new("n"), :nint16)
  Binary.register_field(PackBinaryType.new("N"), :nint32)
  Binary.register_field(PackBinaryType.new("v"), :lint16)
  Binary.register_field(PackBinaryType.new("V"), :lint32)

  Binary.register_field(PackBinaryType.new("d"), :double)
  Binary.register_field(PackBinaryType.new("E"), :ldouble)
  Binary.register_field(PackBinaryType.new("G"), :ndouble)

  Binary.register_field(PackBinaryType.new("f"), :float)
  Binary.register_field(PackBinaryType.new("e"), :lfloat)
  Binary.register_field(PackBinaryType.new("g"), :nfloat)

  class BytesBinaryType < BinaryType
    def all_opts; [:sizeof, :length] end

    def initialize pack_string, force_opts = {}
      @pack_string = pack_string
      @force_opts = force_opts
    end

    def binary_size opts
      opts = @force_opts.merge(opts || {})
      if opts[:sizeof]
        len_handler = Binary.get_field_handler(opts[:sizeof])
        len_handler.binary_size(opts[:sizeof_opts])
      elsif opts[:length]
      opts[:length]
      else
        nil
      end
    end

    def from for_klass, binary, opts
      opts = (opts || {}).merge(@force_opts)
      if opts[:sizeof]
        len_handler = Binary.get_field_handler(opts[:sizeof])
        len, len_size = len_handler.from(for_klass, binary, {})
        binary.size >= len_size + len or incomplete!

        [binary.unpack("x#{len_size} a#{len}")[0], len_size + len]

      elsif opts[:length]
        len = case opts[:length]
          when :all
            binary.size
          else
            opts[:length]
          end
        binary.size >= len or incomplete!
        [binary.unpack("a#{len}")[0], len]

      else
        raise ArgumentError, "#{self.class}: Need one of [:sizeof, :length]"
      end

    end

    def to for_object, object, opts
      opts = (opts || {}).merge(@force_opts)
      if opts[:sizeof]
        len_handler = Binary.get_field_handler(opts[:sizeof])
        len_handler.respond_to?(:pack_string) or raise ArgumentError,
          "#{self.class}#to: needs a PackStringType parameter for length"

        [object.size, object].pack("#{len_handler.pack_string} a*")

      elsif opts[:length]
        len = case opts[:length]
          when :all
            "*"
          else
            opts[:length]
        end
        [object].pack("a#{len}")

      else
        raise ArgumentError, "#{self.class}: Need one of [:sizeof, :length]"
      end

    end
  end

  Binary.register_field(BytesBinaryType.new("a", :length => 1), :char)
  Binary.register_field(BytesBinaryType.new("a"), :bytes)
  Binary.register_field(BytesBinaryType.new("A"), :string)
  Binary.register_field(BytesBinaryType.new("Z"), :nstring)

  Binary.register_field(BytesBinaryType.new("M"), :quoted_printable)
  Binary.register_field(BytesBinaryType.new("m"), :base64)
  Binary.register_field(BytesBinaryType.new("u"), :uuencoded)


  class ListBinaryType < BinaryType

    def binary_size opts
      if opts[:sizeof]
        len_handler = Binary.get_field_handler(opts[:sizeof])
        len_handler.binary_size(opts[:sizeof_opts])
      elsif opts[:length]
        opts[:length]
      else
        nil
      end
    end

    def from for_klass, binary, opts
      type_of = Binary.get_field_handler(opts[:of])
      type_of.respond_to?(:binary_size) &&
        type_of_binary_size = type_of.binary_size(opts[:of_opts]) or raise ArgumentError,
        "#{self.class} can only encode known-width fields."

      list = []
      consumed = 0

      if opts[:sizeof]
        len_handler = Binary.get_field_handler(opts[:sizeof])
        len, ate = len_handler.from(for_klass, binary, opts[:sizeof_opts])
        consumed += ate
        for i in 0...len do
          cc, ate = type_of.from(for_klass, binary[consumed, type_of_binary_size], opts[:of_opts])
          list << cc
          consumed += ate
        end

      elsif opts[:length]
        for i in 0...opts[:length] do
          cc, ate = type_of.from(for_klass, binary[consumed, type_of_binary_size], opts[:of_opts])
          list << cc
          consumed += ate
        end
      else
        raise ArgumentError, "#{self.class}: Need one of [:sizeof, :length]"
      end

      [list, consumed]
    end

    def to for_object, object, opts
      object.is_a?(Array) or raise ArgumentError, "#{self.class}#to: require Array."

      type_of = Binary.get_field_handler(opts[:of])

      if opts[:sizeof]
        len_handler = Binary.get_field_handler(opts[:sizeof])

        ([len_handler.to(for_object, object.size, opts[:of_opts])] + object).map {|o|
          type_of.to(for_object, o, opts[:of_opts])
        }.join('')

      elsif opts[:length]
        object.size == opts[:length] or raise ArgumentError,
          "#{self.class}#to: Array#size does not match required fixed width: " +
          "have #{object.size}, require #{opts[:length]}"

        object.map {|o|
          type_of.to(for_object, o, opts[:of_opts])
        }.join('')

      else
        raise ArgumentError, "#{self.class}: Need one of [:sizeof, :length]"
      end

    end
  end

  Binary.register_field(ListBinaryType.new, :list)
end
