module Arpie

  # The RPC call encapsulation used by ProxyEndpoint and Proxy.
  class ProxyCall < Struct.new(:meth, :argv); end

  # A Endpoint which supports arbitary objects as handlers,
  # instead of a proc.
  #
  # Note that this will only export public instance method
  # of the class as they are defined.
  class ProxyEndpoint < Endpoint
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

    def _handle message
      if !@handler.respond_to?(message.meth) || (@interface && !@interface.index(message.meth))
        raise NoMethodError, "No such method: #{message.meth.inspect}"
      end

      @handler.send(message.meth, *message.argv)
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

    def method_missing meth, *argv # :nodoc:
      call = ProxyCall.new(meth, argv)
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
