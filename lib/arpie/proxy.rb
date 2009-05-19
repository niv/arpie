require 'uuidtools'

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

    # Set this to false to disable replay protection.
    attr_accessor :uuid_tracking

    # The maximum number of method call results to remember.
    # Defaults to 100, which should be enough for everyone. ;)
    attr_accessor :max_uuids

    def initialize *va
      super
      @uuids = {}
      @max_uuids = 100
      @uuid_tracking = true
    end

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
        endpoint.write_message NoMethodError.new("No such method: #{message.meth.inspect}")
        return
      end

      begin
        # Prune old serials. This can probably be optimized, but works well enough for now.
        if @uuid_tracking && message.uuid
          uuid, serial = * message.uuid

          raise ArgumentError,
            "Invalid UUID given, expect [uuid/64bit, serial/numeric]." unless
              uuid.is_a?(Integer) && serial.is_a?(Integer)

          # Limit to sane values.
          uuid   &= 0xffffffffffffffff
          serial &= 0xffffffffffffffff

          timestamps = @uuids.values.map {|v| v[0] }.sort
          latest_timestamp = timestamps[-@max_uuids]
          @uuids.reject! {|uuid, (time, value)|
            time < latest_timestamp
          } if latest_timestamp

          endpoint.write_message((@uuids[message.uuid] ||=
            [Time.now, @handler.send(message.meth, *message.argv)])[1])

        else
          endpoint.write_message @handler.send(message.meth, *message.argv)
        end
      rescue IOError
        raise

      rescue Exception => e
        endpoint.write_message RuntimeError.new("Internal Error")
        raise
      end
    end
  end

  # A Proxy is a wrapper around a Client, which transparently tunnels
  # method calls to the remote ProxyServer.
  # Note that the methods of Client cannot be proxied.
  class ProxyClient < RPCClient
    attr_accessor :namespace

    # Set to false to disable replay protection.
    # Default is true.
    attr_accessor :replay_protection

    # The current serial for this transport.
    attr_accessor :serial

    # The generated uuid for this Client.
    # nil if no call has been made yet.
    attr_accessor :uuid

    def initialize *protocols
      super
      @protocol, @namespace = protocol, ""
      @serial = 0
      @uuid_generator = lambda {|client, method, argv|
        UUIDTools::UUID.random_create.to_i
      }
      @replay_protection = true
    end

    # Set up a new UUID generator for this proxy client.
    # Make sure that this yields really random numbers.
    # The default uses the uuidtools gem and is usually okay.
    #
    # This gets called exactly once for each created ProxyClient.
    def uuid_generator &handler #:yields: client, method, argv
      @uuid_generator = handler
      self
    end

    def method_missing meth, *argv # :nodoc:
      serial = nil
      if @replay_protection
        serial = [
          @uuid ||= @uuid_generator.call(self, meth, argv),
          @serial += 1
        ]
      end

      call = Arpie::RPCall.new(@namespace, meth, argv, serial)
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
