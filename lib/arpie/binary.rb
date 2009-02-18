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
  #
  # On confusing names:
  #
  # Arpie uses the term +binary+ to refer to on-the-wire data bit/byte binary format.
  # A +Binary+ (uppercase) is a object describing the format. If you're reading +binary+,
  # think "raw data"; if you're reading +Binary+ or +object+, think Arpie::Binary.
  #
  # Another warning:
  #
  # Do not use +Kernel+ methods as field names. It'll confuse method_missing.
  # Example:
  #  field :test, :uint8
  # => in `test': wrong number of arguments (ArgumentError)
  class Binary
    @@fields ||= {}
    @@attributes ||= {}
    @@description ||= {}

    def initialize attributes = {}
      @attributes = attributes
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
      if klass.class === Arpie::Binary
        klass
      else
        @@fields[klass] or raise ArgumentError,
          "#{self}: No such field type: #{klass.inspect}"
      end
    end

    # You can use this to provide a short description of this Binary.
    # It will be shown when calling Binary.inspect.
    def self.describe text
      @@description[self] = text
    end

    # Specify that this Binary has a field of type +klass+.
    # See the class documentation for usage.
    def self.field name, klass = nil, opts = {}
      @@attributes[self] ||= []

      klass.nil? && !block_given? and raise ArgumentError,
        "You need to specify an inline handler if no type is given."
      inline_handler = nil

      @@attributes[self].select {|x|
        x[0].to_sym == name.to_sym
      }.size > 0 and raise ArgumentError, "#{self}: attribute #{name.inspect} already defined"

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

      @@attributes[self] << [name.to_sym, klass, opts, inline_handler]
    end


    def self.binary_size opts = {}
      @@attributes[self] ||= []
      total = @@attributes[self].inject(0) {|sum, attribute|
        klass = get_field_handler attribute[1]
        sum += klass.binary_size(opts)
      }

      puts "total for #{self}: #{total}"
      total
    end

    # Parse the given +binary+, which is a string, and return an instance of this class.
    # Will raise Arpie::EIncomplete when not enough data is available in +binary+ to construct
    # a complete Binary.
    def self.from binary, opts = {}
      @@attributes[self] ||= []
      at = {}

      consumed_bytes = 0
      @@attributes[self].each {|name, klass, opts, inline_handler|

        handler = get_field_handler klass
        at[name], consumed =
          handler.from(binary[consumed_bytes .. -1], opts) rescue case $!
          when EIncomplete
            raise $!, "#{$!.to_s}, #{self}#from needs more data for #{name.inspect}"
          else
            raise
        end
        consumed_bytes += consumed

        if inline_handler
           at[name], __nil = inline_handler.from(at[name])
        end
      }

      [new(at), consumed_bytes]
    end

    # Recursively convert the given Binary object to wire format.
    def self.to object, opts = {}
      @@attributes[self] ||= []
      r = []

      @@attributes[self].each {|name, klass, opts, inline_handler|

        handler = get_field_handler klass
        val = object.send(name) or raise "#{self.class}: attribute #{name.inspect} is nil, cannot #to"

        if inline_handler
          p val
          val = val.to
        end

        r << handler.to(val, opts)
      }

      r = r.join('')
      object.respond_to?(:post_to) && r = object.send(:post_to, r)
      r
    end

    def to opts = {}
      self.class.to(self, opts)
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
    def from binary, opts
      raise NotImplementedError
    end

    # Return [binary]
    def to object, opts
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

    def from binary, opts
      binary.size >= @binary_size or incomplete!
      [binary.unpack(@pack_string)[0], @binary_size]
    end

    def to object, opts
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

    def from binary, opts
      opts = (opts || {}).merge(@force_opts)
      if opts[:sizeof]
        len_handler = Binary.get_field_handler(opts[:sizeof])
        len, len_size = len_handler.from(binary, {})
        binary.size >= len_size + len or incomplete!

        [binary.unpack("x#{len_size} #{@pack_string}#{len}")[0], len_size + len]

      elsif opts[:length]
        len = case opts[:length]
          when :all
            binary.size
          else
            opts[:length]
          end
        binary.size >= len or incomplete!
        [binary.unpack("#{@pack_string}#{len}")[0], len]

      else
        raise ArgumentError, "#{self.class}: Need one of [:sizeof, :length]"
      end

    end

    def to object, opts
      opts = (opts || {}).merge(@force_opts)
      if opts[:sizeof]
        len_handler = Binary.get_field_handler(opts[:sizeof])
        len_handler.respond_to?(:pack_string) or raise ArgumentError,
          "#{self.class}#to: needs a PackStringType parameter for length"

        [object.size, object].pack("#{len_handler.pack_string} #{@pack_string}*")

      elsif opts[:length]
        len = case opts[:length]
          when :all
            "*"
          else
            opts[:length]
        end
        [object].pack("#{@pack_string}#{len}")

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

    def from binary, opts
      type_of = Binary.get_field_handler(opts[:of])
      type_of.respond_to?(:binary_size) &&
        type_of_binary_size = type_of.binary_size(opts[:of_opts]) or raise ArgumentError,
        "#{self.class} can only encode known-width fields."

      list = []
      consumed = 0

      if opts[:sizeof]
        len_handler = Binary.get_field_handler(opts[:sizeof])
        len, ate = len_handler.from(binary, opts[:sizeof_opts])
        consumed += ate
        cc, ate = nil, nil
        for i in 0...len do
          cc, ate = type_of.from(binary[consumed .. -1], opts[:of_opts])
          list << cc
          consumed += ate
        end

      elsif opts[:length]
        cc, ate = nil, nil
        for i in 0...opts[:length] do
          cc, ate = type_of.from(binary[consumed .. -1], opts[:of_opts])
          list << cc
          consumed += ate
        end
      else
        raise ArgumentError, "#{self.class}: Need one of [:sizeof, :length]"
      end

      [list, consumed]
    end

    def to object, opts
      object.is_a?(Array) or raise ArgumentError, "#{self.class}#to: require Array."

      type_of = Binary.get_field_handler(opts[:of])

      if opts[:sizeof]
        len_handler = Binary.get_field_handler(opts[:sizeof])
        ([len_handler.to(object.size, opts[:sizeof_opts])] + object.map {|o|
          type_of.to(o, opts[:of_opts])
        }).join('')

      elsif opts[:length]
        object.size == opts[:length] or raise ArgumentError,
          "#{self.class}#to: Array#size does not match required fixed width: " +
          "have #{object.size}, require #{opts[:length]}"

        object.map {|o|
          type_of.to(o, opts[:of_opts])
        }.join('')

      else
        raise ArgumentError, "#{self.class}: Need one of [:sizeof, :length]"
      end

    end
  end

  Binary.register_field(ListBinaryType.new, :list)
end
