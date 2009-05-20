module Arpie
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
      type_of_binary_size = nil
      if type_of.respond_to?(:binary_size)
        type_of_binary_size = type_of.binary_size(opts[:of_opts]) rescue nil
      end

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
            if type_of_binary_size
              binary.size / type_of_binary_size
            else
              nil
            end

          when Symbol
            opts[:object].send(opts[:length])

          else
            opts[:length]

          end
      else
        raise ArgumentError, "need one of [:sizeof, :length]"
      end

      cc, ate = nil, nil



      if length.nil?
        loop do
          nextdata = binary[consumed .. -1]
          break if !nextdata || nextdata == ""
          cc, ate = type_of.from(binary[consumed .. -1], opts[:of_opts])
          list << cc
          consumed += ate
        end

      else
        for i in 0...length do
          cc, ate = type_of.from(binary[consumed .. -1], opts[:of_opts])
          list << cc
          consumed += ate
        end
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
end
