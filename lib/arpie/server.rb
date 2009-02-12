module Arpie

  # Endpoint wraps client IO objects. One Endpoint
  # per client. This is provided as a convenience
  # mechanism for protocols to store
  # protocol-and-client-specific data.
  class Endpoint
    attr_reader :io

    attr_reader :protocol

    def initialize protocol, io
      @protocol, @io = protocol, io
      @protocol.reset
    end

    def read_message
      @protocol.read_message(@io)
    end

    def write_message message
      @protocol.write_message(@io, message)
    end
    alias_method :<<, :write_message

  end

  # A Server is the server-side part of a RPC setup.
  # It accepts connections (via the acceptor), and handles
  # incoming RPC calls on them.
  #
  # There will be one Thread per connection, so order of
  # execution with multiple threads is not guaranteed.
  class Server
    attr_reader :protocol

    attr_reader :endpoints

    # Create a new Server with the given +Protocol+.
    # You will need to define a handler, and an acceptor
    # before it becomes operational.
    def initialize protocol
      @protocol = protocol
      @endpoints = []

      @on_connect = lambda {|server, endpoint| }
      @on_disconnect = lambda {|server, endpoint, exception| }
      @on_handler_error = lambda {|server, endpoint, message, exception|
        $stderr.puts "Error in handler: #{exception.message.to_s}"
        $stderr.puts exception.backtrace.join("\n")
        $stderr.puts "Returning exception for this call."
        Exception.new("internal error")
      }
      @handler = lambda {|server, endpoint, message| raise ArgumentError, "No handler defined." }
    end

    # Provide an acceptor; this will be run in a a loop
    # to get IO objects.
    #
    # Example:
    #  listener = TCPServer.new(12345)
    #  my_server.accept do
    #    listener.accept
    #  end
    def accept &acceptor #:yields: server
      @acceptor = acceptor
      Thread.new { _acceptor_thread }
      self
    end

    # Set a message handler, which is a proc that will receive
    # three parameters: the server, the endpoint, and the message.
    #
    # Example:
    #  my_server.handle do |server, endpoint, message|
    #    puts "Got a message: #{message.inspect}"
    #    endpoint.write_message "ok"
    #  end
    def handle &handler #:yields: server, endpoint, message
      raise ArgumentError, "No handler given; need a block or proc." unless handler
      @handler = handler
      self
    end

    # Set an error handler.
    # The return value will be sent to the client.
    #
    # Default is to print the exception to stderr, and return
    # a generic exception that does not leak information.
    def on_handler_error &handler #:yields: server, endpoint, message, exception
      raise ArgumentError, "No handler given; need a block or proc." unless handler
      @on_handler_error = handler
      self
    end

    # Callback that gets invoked when a new client connects.
    # You can <tt>throw :kill_client</tt> here to stop this client
    # from connecting. Clients stopped this way will invoke
    # the on_disconnect handler normally.
    def on_connect &handler #:yields: server, endpoint
      raise ArgumentError, "No handler given; need a block or proc." unless handler
      @on_connect = handler
      self
    end

    # Callback that gets invoked when a client disconnects.
    # The exception is the error that occured (usually a EOFError).
    def on_disconnect &handler #:yields: server, endpoint, exception
      raise ArgumentError, "No handler given; need a block or proc." unless handler
      @on_disconnect = handler
      self
    end

  private

    def _handle endpoint, message
      @handler.call(self, endpoint, message)
    end

    def _acceptor_thread
      loop do
        client = @acceptor.call(self)
        c = @protocol.endpoint_class.new(@protocol.clone, client)
        Thread.new { _read_thread(c) }
      end
    end

    def _read_thread endpoint
      @endpoints << endpoint
      _exception = nil

      catch(:kill_client) {
        @on_connect.call(self, endpoint)

        loop do
          message, answer = nil, nil

          begin
            message = endpoint.read_message
          rescue IOError => e
            _exception = e
            break
          end

          begin
            answer = _handle(endpoint, message)
          rescue Exception => e
            answer = @on_handler_error.call(self, endpoint, message, e)
          end
        end
      }

      @on_disconnect.call(self, endpoint, _exception)
      @endpoints.delete(endpoint)
    end
  end
end
