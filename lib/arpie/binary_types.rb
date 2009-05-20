module Arpie
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
end

require 'arpie/binary/pack_type'
require 'arpie/binary/bytes_type'
require 'arpie/binary/fixed_type'
require 'arpie/binary/list_type'
