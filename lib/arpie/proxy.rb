module Arpie

  # The RPC call encapsulation used by ProxyEndpoint and Proxy.
  class ProxyCall < Struct.new(:method, :argv); end

  # A Endpoint which supports arbitary objects as handlers,
  # instead of a proc.
  #
  # Note that this will only export public instance method
  # of the class as they are defined.
  class ProxyEndpoint < Endpoint
  
    # Set a class handler. All instance methods will be
    # callable over RPC (with a Proxy object).
    # Consider yourself warned of the security implications:
    #  proxy.instance_eval ..
    def handle handler
      @handler = handler
    end

    private

    def _handle message
      @handler.send(message.method, *message.argv)
    end
  end

  # A Proxy is a wrapper around a transport, which transparently tunnels
  # method calls to the remote ProxyEndpoint.
  class Proxy
    attr_reader :transport

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
