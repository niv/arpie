module Arpie

  # A Endpoint which supports arbitary objects as handlers,
  # instead of a proc.
  #
  # Note that this will only export public instance method
  # of the class as they are defined.
  class ProxyServer < Server

    # An array containing symbols of method names that the
    # handler should be allowed to call. Defaults to
    # all public instance methods the class defines (wysiwyg).
    # Set this to nil to allow calling of ALL methods, but be
    # warned of the security implications (instance_eval, ..).
    attr_accessor :interface

    # Set a class handler. All public instance methods will be
    # callable over RPC (with a Proxy object) (see attribute interface).
    def handle handler
      @handler = handler
      @interface = handler.class.public_instance_methods(false).map {|x|
        x.to_sym
      }
      self
    end

    private

    def _handle endpoint, message
      if !@handler.respond_to?(message.meth.to_sym) ||
          (@interface && !@interface.index(message.meth.to_sym))
        raise NoMethodError, "No such method: #{message.meth.inspect}"
      end

      ret = @handler.send(message.meth, *message.argv)
      endpoint.write_message(ret)
    end
  end

  # A Proxy is a wrapper around a Client, which transparently tunnels
  # method calls to the remote ProxyServer.
  # Note that the methods of Client cannot be proxied.
  class ProxyClient < RPCClient

    def initialize protocol, namespace = ""
      @protocol, @namespace = protocol, namespace
    end

    def method_missing meth, *argv # :nodoc:
      call = RPCProtocol::Call.new(@namespace, meth, argv)
      ret = self.request(call)
      case ret
        when Exception
          raise ret
        else
          ret
      end
    end
  end
end
