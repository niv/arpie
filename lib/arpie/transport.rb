module Arpie

  # A Transport is a connection manager, and acts as the
  # glue between a user-defined medium (for example, a TCP
  # socket), and a protocol.
  #
  # See README for examples.
  class Transport
    attr_reader :protocol

    # The transport_id is used by remote endpoints to
    # identify reconnecting transports; it is part
    # of the transmitted serial.
    # This is simply a 64bit unsigned integer generated
    # with rand() on Transport instanciation; which may
    # or may not be workable.
    attr_reader :transport_uuid

    # How often should this Transport retry a connection.
    # 0 for never, greater than 0 for that many attempts,
    # nil for infinite (default).
    # Values other than nil will raise network exceptions
    # to the caller.
    attr_accessor :connect_retry

    # How long should the caller sleep after each reconnect
    # attempt. (default: 1.0). The default value is probably
    # okay. Do not set this to 0; that will produce
    # unnecessary load in case of network failure.
    attr_accessor :connect_sleep

    def initialize protocol
      @protocol = protocol
      @io = nil
      @connector = lambda { raise ArgumentError, "No connector specified, cannot connect to Endpoint." }
      @connect_retry = nil
      @connect_sleep = 1.0
      @serial = 0
      @on_pre_call = lambda {|transport, message, io, transport_uuid, serial, try| }
      @on_post_call = lambda {|transport, message, reply, io, transport_uuid, serial, try| }
      @on_error = lambda {|transport, exception| }
      generate_uuid
    end

    # Provide a connector block, which will be called
    # each time a connection is needed.
    # Set +connect_immediately+ to true to connect
    # immediately, instead on the first message.
    def connect connect_immediately = false, &connector
      @connector = connector
      _connect if connect_immediately
      self
    end

    # Set an error handler. It will be called with two
    # parameters, the transport, and the exception that occured.
    # Optional, and just for notification.
    def on_error &handler #:yields: transport, exception
      @on_error = handler
      self
    end

    def pre_call &handler #:yields: transport, message, io, transport_uuid, serial, try
      @on_pre_call = handler
      self
    end

    def post_call &handler #:yields: transport, message, reply, io, transport_uuid, serial, try
      @on_post_call = handler
      self
    end

    # Send a message and receive a reply in a synchronous
    # fashion. Will block until transmitted, or until
    # all reconnect attempts failed.
    def request message
      serial = @serial += 1
      reply = nil

      try = 0

      @on_pre_call.call(self, message, @io, @transport_uuid, serial, try) if @on_pre_call

      begin
        _connect
        @protocol.write_message(@io, message, @transport_uuid, serial)
        reply, transport_id, serial = @protocol.read_message(@io)
      rescue => e
        try += 1
        @on_error.call(self, e) if @on_error

        if @connect_retry == 0 || (@connect_retry && try > @connect_retry)
          raise EOFError, "Cannot send request: lost connection after #{try} attempts (#{e.message.to_s})"
        end

        sleep @connect_sleep
        begin; @io.close if @io; rescue; end
        @io = nil
        retry
      end

      @on_post_call.call(self, message, reply, @io, @transport_uuid, serial, try) if @on_post_call

      case reply
        when Exception
          raise reply
        else
          reply
      end
    end

    # Generate a new UUID for this transport. You usually do not
    # need to call this.
    def generate_uuid
      @transport_uuid = 1 + rand(0xfffffffffffffffe)
      puts "generated tid: #{transport_uuid}" if $DEBUG
      self
    end

    private

    def _connect
      @io ||= @connector.call(self)
    end
  end
end
