module Arpie
  class FixedBinaryType < BinaryType
    def binary_size opts
      opts[:value].size
    end

    def from binary, opts
      opts[:value] or raise ArgumentError, "Requires option :value"
      sz = opts[:value].size
      existing = binary.unpack("a#{sz}")[0]
      existing == opts[:value] or bogon! nil, ":fixed did not match data in packet"

      [opts[:value], opts[:value].size]
    end

    def to object, opts
      opts[:value] or raise ArgumentError, "Requires option :value"
      object == opts[:value] or bogon! nil, ":fixed did not match data in structure"
      opts[:value]
    end
  end

  class Binary
    # Create a static field.
    # This is an alias for:
    #  field :name, :fixed, :value => content
    #
    # If no name is specified, it is assumed that the user will
    # never want to access it and a suitable one is autogenerated.
    def self.static content, name = nil
      name ||= "static-%x" % content.hash
      field name, :fixed, :value => content
    end

    # An alias for +static+.
    def self.s *va, &b
      static *va, &b
    end
  end

  Binary.register_type(FixedBinaryType.new, :fixed)
end