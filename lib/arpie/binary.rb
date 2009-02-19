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
    @@virtuals ||= {}
    @@description ||= {}
    @@hooks ||= {}

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

      if self.class.attribute?(at)
        if $2 == "="
          a.size == 1 or raise ArgumentError
          if !a[0].is_a?(Class) && inline = self.class.get_attribute(at)[3]
            a[0], __nil = inline.from(a[0], {})
          end
          @attributes[at] = a[0]
        else
          @attributes[at]
        end

      elsif self.class.virtual?(at)
        if $2 == "="
          raise ArgumentError
        else
          Binary.call_virtual(self, at)
        end

      else
        super
      end
    end

    def self.call_virtual(on_object, name)
      @@virtuals[on_object.class].select {|x|
        x[0] == name
      }[0][3].call(on_object)
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

    def self.get_attribute attribute
      @@attributes[self] or raise ArgumentError, "No such attribute: #{attribute.inspect}"
      @@attributes[self].each {|a|
        a[0].to_sym == attribute.to_sym and return a
      }
      raise ArgumentError, "No such attribute: #{attribute.inspect}"
    end

    # Returns true if this Binary has the named +virtual+.
    def self.virtual? virtual
      @@virtuals[self] or return false
      @@virtuals[self].select {|name,klass,handler|
        name.to_sym == virtual.to_sym
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
    # When called without a parameter, (non-recursively) print out a
    # pretty description of this data type as it would appear on the wire.
    def self.describe text = nil
      unless text.nil?
        @@description[self] = text
      else
        ret = []
        ret << "%-10s %s" % ["Binary:", @@description[self]]
        ret << ""

        sprf    = "%-10s %-25s %-15s %-15s %-15s %s"
        sprf_of = "%68s %s"
        if @@virtuals[self] && @@virtuals[self].size > 0
          ret << sprf % ["Virtuals:", "NAME", "TYPE", "WIDTH", "", "DESCRIPTION"]
          @@virtuals[self].each {|v|
            name, klass, opts, handler = *v
            width = self.get_field_handler(klass).binary_size({})
            ret << sprf % [ "",
              name,
              klass,
              width,
              "",
              opts[:description]
            ]
          }
          ret << ""
        end
        if @@attributes[self] && @@attributes[self].size > 0
          ret << sprf % %w{Fields:   NAME TYPE WIDTH OF DESCRIPTION}
          @@attributes[self].each {|a|
            name, klass, opts, inline_handler = *a
            width = self.get_field_handler(klass).binary_size(opts)
            ret << sprf % [ "",
              name,
              klass,
              (opts[:length] || opts[:sizeof] || width),
              opts[:of] ? opts[:of].inspect : "",
              opts[:description]
            ]
            ret << sprf_of % [ "",
              opts[:of_opts].inspect
            ] if opts[:of_opts]
          }
        end
        ret.join("\n")
      end
    end

    # Specify that this Binary has a field of type +klass+.
    # See the class documentation for usage.
    def self.field name, klass = nil, opts = {}
      raise ArgumentError, "#{name.inspect} already exists as a virtual" if virtual?(name)
      raise ArgumentError, "#{name.inspect} already exists as a field" if attribute?(name)

      @@attributes[self] ||= []

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

      opts[:description] ||= opts[:desc]
      opts.delete(:desc)

      @@attributes[self] << [name.to_sym, klass, opts, inline_handler]
    end

    # Set up a new virtual field
    def self.virtual name, klass, opts = {}, &handler
      raise ArgumentError, "You need to pass a block with virtuals" unless block_given?
      raise ArgumentError, "#{name.inspect} already exists as a virtual" if virtual?(name)
      raise ArgumentError, "#{name.inspect} already exists as a field" if attribute?(name)

      @@virtuals[self] ||= []
      opts[:description] ||= opts[:desc]
      opts.delete(:desc)
      @@virtuals[self] << [name.to_sym, klass, opts, handler]
    end


    def self.binary_size opts = {}
      @@attributes[self] ||= []
      total = @@attributes[self].inject(0) {|sum, attribute|
        name, klass, kopts, handler = *attribute
        klass = get_field_handler klass
        sum += klass.binary_size(kopts)
      }

      total
    end

    def self.add_hook(hook, handler)
      @@hooks[self] ||= {}
      @@hooks[self][hook] ||= []
      @@hooks[self][hook] << handler
    end

    def self.call_hooks(hook, *va)
      @@hooks[self] ||= {}
      @@hooks[self][hook] ||= []
      @@hooks[self][hook].each {|handler|
        va = *handler.call(*va)
      }
      va
    end

    # Parse the given +binary+, which is a string, and return an instance of this class.
    # Will raise Arpie::EIncomplete when not enough data is available in +binary+ to construct
    # a complete Binary.
    def self.from binary, opts = {}
      @@attributes[self] ||= []
      binary = * self.call_hooks(:pre_from, binary)

      consumed_bytes = 0
      obj = new
      @@attributes[self].each {|name, klass, kopts, inline_handler|
        kopts[:binary] = binary
        kopts[:object] = obj
        handler = get_field_handler klass

        attrib, consumed = binary, nil

        attrib, consumed =
          handler.from(binary[consumed_bytes .. -1], kopts) rescue case $!
          when EIncomplete
            raise $!, "#{$!.to_s}, #{self}#from needs more data for #{name.inspect}. (data: #{binary[consumed_bytes .. -1].inspect})"
          else
            raise
        end
        consumed_bytes += consumed

        obj.send((name.to_s + "=").to_sym, attrib)
        kopts.delete(:binary)
        kopts.delete(:object)
      }

      binary, obj, consumed_bytes = self.call_hooks(:post_from, binary, obj, consumed_bytes)
      [obj, consumed_bytes]
    end

    # Recursively convert the given Binary object to wire format.
    def self.to object, opts = {}
      @@attributes[self] ||= []
      r = []
      object = * self.call_hooks(:pre_to, object)

      @@attributes[self].each {|name, klass, kopts, inline_handler|
        kopts[:object] = object
        handler = get_field_handler klass
        val = object.send(name) or raise "#{self.class}: attribute #{name.inspect} is nil, cannot #to"

        if inline_handler
          val = val.to
        end

        r << handler.to(val, kopts)
        kopts.delete(:object)
      }

      r = r.join('')
      _obj, r = self.call_hooks(:post_to, object, r)
      r
    end

    def to opts = {}
      self.class.to(self, opts)
    end

    # Add a hook that gets called before converting a binary to
    # Binary representation.
    # Arguments to the handler: +binary+
    # Note that all handlers need to return their arguemts as they were
    # passed, as they will replace the original values.
    def self.pre_to &handler
      self.add_hook(:pre_to, handler)
    end
    # Add a hook that gets called after converting a binary to
    # Binary representation.
    # Arguments to the handler: +object+, +binary+, +consumed_bytes+.
    # Note that all handlers need to return their arguemts as they were
    # passed, as they will replace the original values.
    def self.post_to &handler
      self.add_hook(:post_to, handler)
    end
    # Add a hook that gets called before converting a Binary to
    # wire format.
    # Arguments to the handler: +object+
    # Note that all handlers need to return their arguemts as they were
    # passed, as they will replace the original values.
    def self.pre_from &handler
      self.add_hook(:pre_from, handler)
    end
    # Add a hook that gets called after converting a Binary to
    # wire format.
    # Arguments to the handler: +binary+, +object+
    # Note that all handlers need to return their arguemts as they were
    # passed, as they will replace the original values.
    def self.post_from &handler
      self.add_hook(:post_from, handler)
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
          when Symbol
            opts[:object].send(opts[:length])
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
        case opts[:length]
          when Symbol
            opts[:object] ? opts[:object].send(opts[:length]) : nil
          else
            opts[:length]
        end
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
      length = nil

      if opts[:sizeof]
        len_handler = Binary.get_field_handler(opts[:sizeof])
        length, ate = len_handler.from(binary, opts[:sizeof_opts])
        consumed += ate

      elsif opts[:length]
        length = case opts[:length]
          when Symbol
            opts[:object].send(opts[:length])
          else
            opts[:length]
          end
      else
        raise ArgumentError, "#{self.class}: Need one of [:sizeof, :length]"
      end

      cc, ate = nil, nil
      for i in 0...length do
        cc, ate = type_of.from(binary[consumed .. -1], opts[:of_opts])
        list << cc
        consumed += ate
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
        length = case opts[:length]
          when Symbol
            opts[:object].send(opts[:length])
          else
            opts[:length]
        end

        object.size == length or raise ArgumentError,
          "#{self.class}#to: Array#size does not match required fixed width: " +
          "have #{object.size}, require #{length.inspect}"

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
