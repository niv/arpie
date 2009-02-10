module Arpie

  # The RPC call encapsulation used by ProxyEndpoint and Proxy.
  class ProxyCall < Struct.new(:ns, :meth, :argv); end

  # A Endpoint which supports arbitary objects as handlers,
  # instead of a proc.
  #
  # Note that this will only export public instance method
  # of the class as they are defined.
  class ProxyServer < Server
    attr_accessor :interface

    # Set a class handler. All instance methods will be
    # callable over RPC (with a Proxy object).
    # Consider yourself warned of the security implications:
    #  proxy.instance_eval ..
    # Optional interface parameter is an array of method
    # names (as symbols). If given, only those will be
    # accessible for Transports.
    def handle handler, interface = nil
      @handler = handler
      @interface = interface
      self
    end

    private

    def _handle endpoint, message
      if !@handler.respond_to?(message.meth) || (@interface && !@interface.index(message.meth))
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
      call = ProxyCall.new(@namespace, meth, argv)
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
