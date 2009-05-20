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
  #
  # In fact, this is the reason while Binary will not let you define fields with
  # with names like existing instance methods.
  class Binary
    extend Arpie
    class Field   < Struct.new(:name, :type, :opts, :inline_handler) ; end
    class Virtual < Struct.new(:name, :type, :opts, :handler) ; end


    @@types       ||= {}
    @@fields      ||= {}
    @@virtuals    ||= {}
    @@description ||= {}
    @@hooks       ||= {}

    #:stopdoc:
    @@anonymous ||= {}
    def self.__anonymous
      @@anonymous[self]
    end
    def self.__anonymous= x
      @@anonymous[self] = x
    end
    #:startdoc:

    def initialize
      @fields = {}
      @@fields[self.class] ||= []

      # set up our own class handlers, create anon classes, set up default values
      @@fields[self.class].each {|field|
        if field.inline_handler
          @fields[field.name] = field.inline_handler.new

        elsif field.type.is_a?(Class)
          @fields[field.name] = field.type.new

        elsif field.opts[:default]
          @fields[field.name] = field.opts[:default]
        end
      }
      if block_given?
        yield self
      end
    end

    def inspect #:nodoc:
      desc = " " + @@description[self.class].inspect if @@description[self.class]
      # Anonymous is special
      klass = self.class.respond_to?(:__anonymous) && self.class.__anonymous ?
        "Anon#{self.class.__anonymous.inspect}" :
        self.class.to_s

      fields = []
      @@fields[self.class].each {|field|
        fields << "%s=>%s" % [field.name.inspect, @fields[field.name].inspect]
      }
      fields = '{' + fields.join(", ") + '}'

      "#<#{klass}#{desc} #{fields}>"
    end

    def method_missing m, *a
      m.to_s =~ /^(.+?)(=?)$/ or super
      at = $1.to_sym
      if self.class.field?(at)
        if $2 == "="
          a.size == 1 or raise ArgumentError
          if !a[0].is_a?(Class) && inline = self.class.get_field(at)[3]
            a[0], __nil = inline.from(a[0], {})
          end
          @fields[at] = a[0]
        else
          @fields[at]
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
      @@virtuals[on_object.class].select {|virtual|
        virtual.name == name
      }[0].handler.call(on_object)
    end

    # This registers a new type with this binary.
    def self.register_type handler, *type_aliases
      type_aliases.each do |type|
        @@types[type] = handler
      end
    end

    # Returns true if this Binary has the named +field+.
    def self.field? field
      @@fields[self] or return false
      @@fields[self].select {|_field|
        _field.name == field
      }.size > 0
    end

    def self.get_field field
      @@fields[self] or raise ArgumentError, "No such field: #{field.inspect}"
      @@fields[self].each {|_field|
        _field.name == field and return _field
      }
      raise ArgumentError, "No such field: #{field.inspect}"
    end

    # Returns true if this Binary has the named +virtual+.
    def self.virtual? virtual
      @@virtuals[self] or return false
      @@virtuals[self].select {|_virtual|
        _virtual.name == virtual
      }.size > 0
    end

    # Returns the BinaryType handler class for +type+, which can be a
    # symbol (:uint8), or a Arpie::Binary.
    def self.get_type_handler type
      if type.class === Arpie::Binary
        type
      else
        @@types[type] or raise ArgumentError,
          "#{self}: No such field type: #{type.inspect}"
      end
    end

    def self.describe_all_types
      ret = []
      strf = "%-15s %-8s %s"
      ret << strf % %w{TYPE WIDTH HANDLER}
      @@types.sort{|a,b| a[0].to_s <=> b[0].to_s}.each {|type, handler|
        ret << strf % [type.inspect, (handler.binary_size({}) rescue nil), handler.inspect]
      }
      ret.join("\n")
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
          @@virtuals[self].each {|virtual|
            width = self.get_type_handler(virtual.type).binary_size(virtual.opts)
            ret << sprf % [ "",
              virtual.name,
              virtual.type,
              width,
              "",
              virtual.opts[:description]
            ]
          }
          ret << ""
        end
        if @@fields[self] && @@fields[self].size > 0
          ret << sprf % %w{Fields:   NAME TYPE WIDTH OF DESCRIPTION}
          @@fields[self].each {|field|
            width = self.get_type_handler(field.type).binary_size(field.opts)
            ret << sprf % [ "",
              field.name,
              field.type,
              (field.opts[:length] || field.opts[:sizeof] || width),
              field.opts[:of] ? field.opts[:of].inspect : "",
              field.opts[:description]
            ]
            ret << sprf_of % [ "",
              field.opts[:of_opts].inspect
            ] if field.opts[:of_opts]
          }
        end
        ret.join("\n")
      end
    end

    # Specify that this Binary has a field of type +type+.
    # See the class documentation for usage.
    def self.field name, type = nil, opts = {}, &block
      @@fields[self] ||= []
      handler = get_type_handler(type)

      raise ArgumentError, "#{name.inspect} already exists as a virtual" if virtual?(name)
      raise ArgumentError, "#{name.inspect} already exists as a field" if field?(name)
      raise ArgumentError, "#{name.inspect} already exists as a instance method" if instance_methods.index(name.to_s)
      raise ArgumentError, "#{name.inspect}: cannot inline classes" if block_given? and type.class === Arpie::Binary

      @@fields[self].each {|field|
        raise ArgumentError, "#{name.inspect}: :optional fields cannot be followed by required fields" if
          field[:opts].include?(:optional)
      } unless opts[:optional]


      type.nil? && !block_given? and raise ArgumentError,
        "You need to specify an inline handler if no type is given."
      inline_handler = nil

      if block_given?
        inline_handler = Class.new(Arpie::Binary)
        inline_handler.__anonymous = [name, type, opts]
        inline_handler.instance_eval(&block)
      end

      if type.nil?
        type, inline_handler = inline_handler, nil
      end

      if handler.respond_to?(:required_opts)
        missing_required = handler.required_opts.keys - opts.keys
        raise ArgumentError, "#{self}: #{name.inspect} as type #{type.inspect} " +
          "requires options: #{missing_required.inspect}" if missing_required.size > 0
        handler.required_opts.each {|k,v|
          v.nil? and next
          v.call(opts[k]) or raise ArgumentError, "#{self}: Invalid value given for opt key #{k.inspect}."
        }
      end

      opts[:description] ||= opts[:desc] if opts[:desc]
      opts.delete(:desc)

      @@fields[self] << Field.new(name.to_sym, type, opts, inline_handler)
    end

    # Set up a new virtual field
    def self.virtual name, type, opts = {}, &handler
      raise ArgumentError, "You need to pass a block with virtuals" unless block_given?
      raise ArgumentError, "#{name.inspect} already exists as a virtual" if virtual?(name)
      raise ArgumentError, "#{name.inspect} already exists as a field" if field?(name)
      raise ArgumentError, "#{name.inspect} already exists as a instance method" if instance_methods.index(name.to_s)

      @@virtuals[self] ||= []
      opts[:description] ||= opts[:desc]
      opts.delete(:desc)
      @@virtuals[self] << Virtual.new(name.to_sym, type, opts, handler)
    end


    def self.binary_size opts = {}
      @@fields[self] ||= []
      total = @@fields[self].inject(0) {|sum, field|
        klass = get_type_handler(field.type)
        sz = klass.binary_size(field.opts)
        sz or raise "cannot binary_size dynamic Binary definitions"
        sum + sz
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
      @@fields[self] ||= []
      binary = * self.call_hooks(:pre_from, binary)

      consumed_bytes = 0
      obj = new
      @@fields[self].each {|field| # name, klass, kopts, inline_handler|
        field.opts[:binary] = binary
        field.opts[:object] = obj
        handler = get_type_handler(field.type)

        attrib, consumed = binary, nil

        attrib, consumed =
          handler.from(binary[consumed_bytes .. -1], field.opts) rescue case $!
          when EIncomplete
            if field.opts[:optional]
              attrib, consumed = field.opts[:default], handler.binary_size(field.opts)
            else
              raise $!,
                "#{$!.to_s}, #{self}#from needs more data for " +
                "#{field.name.inspect}. (data: #{binary[consumed_bytes .. -1].inspect})"
            end
          when StreamError
            bogon! binary[consumed_bytes .. -1], "#{self}#from: #{field.name.inspect}: #{$!.to_s}"
          else
            raise
        end
        consumed_bytes += consumed

        obj.send((field.name.to_s + "=").to_sym, attrib)
        field.opts.delete(:binary)
        field.opts.delete(:object)
      }

      binary, obj, consumed_bytes = self.call_hooks(:post_from, binary, obj, consumed_bytes)
      [obj, consumed_bytes]
    end

    # Recursively convert the given Binary object to wire format.
    def self.to object, opts = {}
      object.nil? and raise ArgumentError, "cannot #to nil"
      @@fields[self] ||= []
      r = []
      object = * self.call_hooks(:pre_to, object)

      @@fields[self].each {|field| # name, klass, kopts, inline_handler|
        field.opts[:object] = object
        handler = get_type_handler(field.type)
        val = object.send(field.name)

        if field.inline_handler
          val = val.to
        end

        # r << (val.respond_to?(:to) ? val.to(opts) : handler.to(val, kopts)) rescue case $!
        r << handler.to(val, field.opts) rescue case $!
          when StreamError
            raise $!, "#{self}#from: #{field.name.inspect}: #{$!.to_s}"
          else
            raise
        end
        field.opts.delete(:object)
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
    include Arpie

    def binary_size opts
      nil
    end

    def required_opts
      {}
    end

    # Return [object, len]
    def from binary, opts
      raise NotImplementedError
    end

    # Return [binary]
    def to object, opts
      raise NotImplementedError
    end

    def check_limit value, limit
      case limit
        when nil
          true
        when Range, Array
          limit.include?(value)
        else
          raise ArgumentError, "unknown limit definition: #{limit.inspect}"
      end or bogon! nil, "not in :limit => #{limit.inspect}"
    end

  end

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
        when 'A', 'a', 'C', 'c', 'Z', 'x' : count
        when 'B', 'b' : (count / 8.0).ceil
        when 'D', 'd', 'E', 'G' : count * 8
        when 'e', 'F', 'f', 'g' : count * 4
        when 'H', 'h' : (count / 2.0).ceil
        when 'I', 'i', 'L', 'l', 'N', 'V' : count * 4
        when 'n', 'S', 's', 'v' : count * 2
        when 'Q', 'q' : count * 8
        when 'X' : count * -1
        else raise ArgumentError, "#{directive} is not supported"
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

  class BytesBinaryType < BinaryType
    def all_opts; [:sizeof, :length] end

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
            binary.size
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
  Binary.register_type(BytesBinaryType.new("Z"), :nstring)

  Binary.register_type(BytesBinaryType.new("M"), :quoted_printable)
  Binary.register_type(BytesBinaryType.new("m"), :base64)
  Binary.register_type(BytesBinaryType.new("u"), :uuencoded)


  class ListBinaryType < BinaryType

    def binary_size opts
      if opts[:sizeof]
        len_handler = Binary.get_type_handler(opts[:sizeof])
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
      type_of = Binary.get_type_handler(opts[:of])
      type_of.respond_to?(:binary_size) &&
        type_of_binary_size = type_of.binary_size(opts[:of_opts]) or raise ArgumentError,
        "can only encode known-width fields"

      list = []
      consumed = 0
      length = nil

      if opts[:sizeof]
        len_handler = Binary.get_type_handler(opts[:sizeof])
        length, ate = len_handler.from(binary, opts[:sizeof_opts])
        consumed += ate

      elsif opts[:length]
        length = case opts[:length]
          when :all
            binary.size / type_of_binary_size
          when Symbol
            opts[:object].send(opts[:length])
          else
            opts[:length]
          end
      else
        raise ArgumentError, "need one of [:sizeof, :length]"
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
      object.is_a?(Array) or bogon! object, "require Array"

      type_of = Binary.get_type_handler(opts[:of])

      if opts[:sizeof]
        len_handler = Binary.get_type_handler(opts[:sizeof])
        ([len_handler.to(object.size, opts[:sizeof_opts])] + object.map {|o|
          type_of.to(o, opts[:of_opts])
        }).join('')

      elsif opts[:length]
        length = case opts[:length]
          when :all
            object.size
          when Symbol
            object.size
          else
            opts[:length]
        end

        object.size == length or bogon! object,
          "Array#size does not match required fixed width: " +
          "have #{object.size}, require #{length.inspect}"

        object.map {|o|
          type_of.to(o, opts[:of_opts])
        }.join('')

      else
        raise ArgumentError, "need one of [:sizeof, :length]"
      end

    end
  end
  Binary.register_type(ListBinaryType.new, :list)

  class FixedBinaryType < BinaryType
    def required_opts ; {:value => proc {|v| v.is_a?(String)}} end
    def binary_size opts
      opts[:value].size
    end

    def from binary, opts
      sz = opts[:value].size
      existing = binary.unpack("a#{sz}")[0]
      existing == opts[:value] or bogon! nil, ":fixed did not match data in packet"

      [opts[:value], opts[:value].size]
    end

    def to object, opts
      opts[:value]
    end
  end
  Binary.register_type(FixedBinaryType.new, :fixed)
end
