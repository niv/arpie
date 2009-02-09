module Arpie

  # A Client is a connection manager, and acts as the
  # glue between a user-defined medium (for example, a TCP
  # socket), and a protocol, with automatic reconnecting
  # and fault handling.
  #
  # See README for examples.
  class Client
    attr_reader :protocol

    # How often should this Client retry a connection.
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
      @on_pre_call = lambda {|client, message| }
      @on_post_call = lambda {|client, message, reply| }
      @on_error = lambda {|client, exception|
        $stderr.puts "Error in Transport IO: #{exception.message.to_s}"
        $stderr.puts exception.backtrace.join("\n")
        $stderr.puts "Set Transport#on_error &block to override this."
      }
      @event_queue = Queue.new
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
    # parameters, the client, and the exception that occured.
    # Optional, and just for notification.
    def on_error &handler #:yields: client, exception
      @on_error = handler
      self
    end

    # Callback that gets invoked before placing a call to the
    # Server. You can stop the call from happening by raising
    # an exception (which will be passed on to the caller).
    def pre_call &handler #:yields: client, message
      @on_pre_call = handler
      self
    end

    # Callback that gets invoked after receiving an answer.
    # You can raise an exception here; and it will be passed
    # to the caller, instead of returning the value.
    def post_call &handler #:yields: client, message, reply
      @on_post_call = handler
      self
    end

    # Send a message and receive a reply in a synchronous
    # fashion. Will block until transmitted, or until
    # all reconnect attempts failed.
    def request message
      reply = nil

      @on_pre_call.call(self, message) if @on_pre_call

      _io_retry do
        @protocol.write_message(@io, message)
        reply = @protocol.read_message(@io)
      end

      @on_post_call.call(self, message, reply) if @on_post_call

      case reply
        when Exception
          raise reply
        else
          reply
      end
    end

  private

    def _io_retry &block
      try = 0

      begin
        _connect
        yield
      rescue => e
        try += 1
        @on_error.call(self, e) if @on_error
        p e

        if @connect_retry == 0 || (@connect_retry && try > @connect_retry)
          raise EOFError, "Cannot read from io: lost connection after #{try} attempts (#{e.message.to_s})"
        end

        sleep @connect_sleep
        begin; @io.close if @io; rescue; end
        @io = nil
        retry
      end
    end

    def _connect
      @io ||= @connector.call(self)
    end
  end
end
