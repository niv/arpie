module Arpie

  # The RPC call encapsulation used by ProxyEndpoint and Proxy.
  class ProxyCall < Struct.new(:method, :argv); end

  # A Endpoint which supports arbitary objects as handlers,
  # instead of a proc.
  #
  # Note that this will only export public instance method
  # of the class as they are defined.
  class ProxyEndpoint < Endpoint
    def handle handler
      @handler = handler
      @interface = @handler.class.public_instance_methods(false)
    end

    private

    def _handle message
      @interface.index(message.method.to_s) or raise NoMethodError,
        "Unknown method."
      @handler.send(message.method, *message.argv)
    end
  end

  # A Proxy is a wrapper around a transport, which transparently tunnels
  # method calls to the remote ProxyEndpoint.
  class Proxy

    # Create a new Proxy.
    def initialize transport
      @transport = transport
    end

    def method_missing method, *argv # :nodoc:
      call = ProxyCall.new(method, argv)
      ret = @transport.request(call)
      case ret
        when Exception
          raise ret
        else
          ret
      end
    end
  end
end
