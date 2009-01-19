module Arpie

  # A Endpoint is the server-side part of a RPC setup.
  # It accepts connections (via the acceptor), and handles
  # incoming RPC calls on them.
  #
  # There will be one Thread per connection, so order of
  # execution with multiple threads is not guaranteed.
  class Endpoint
    attr_reader :protocol

    # Create a new Endpoint with the given +Protocol+.
    # You will need to define a handler, and an acceptor
    # before the endpoint becomes operational.
    def initialize protocol
      @protocol = protocol
      @clients = []

      @last_answer = {}

      @on_connect = lambda {|endpoint, io| }
      @on_disconnect = lambda {|endpoint, io, transport_id, exception| }
      @on_handler_error = lambda {|endpoint, message, exception|
        $stderr.puts "Error in handler: #{exception.message.to_s}"
        $stderr.puts exception.backtrace.join("\n")
        $stderr.puts "Returning exception for this call."
        Exception.new("internal error")
      }
      @handler = lambda {|endpoint, message| raise ArgumentError, "No handler defined." }
    end

    # Provide an acceptor; this will be run in a a loop
    # to get IO objects.
    #
    # Example:
    #  listener = TCPServer.new(12345)
    #  my_endpoint.accept do
    #    listener.accept
    #  end
    def accept &acceptor #:yields: endpoint
      @acceptor = acceptor
      Thread.new { _acceptor_thread }
    end

    # Set a message handler, which is a proc that will receive
    # two parameters: the endpoint, and the message.
    # Its return value will be sent as the reply.
    #
    # Example:
    #  my_endpoint.handle do |endpoint, message|
    #    puts "Got a message: #{message.inspect}"
    #    "ok"
    #  end
    def handle &handler #:yields: endpoint, message
      raise ArgumentError, "need a block" unless block_given?
      @handler = handler
    end

    # Set an error handler.
    # The return value will be sent to the client.
    #
    # Default is to print the exception to stderr, and return
    # a generic exception that does not leak information.
    def on_handler_error &handler #:yields: endpoint, message, exception
      @on_handler_error = handler
      self
    end

    # Callback that gets invoked when a new client connects.
    # You can <tt>throw :kill_client</tt> here to stop this client
    # from connecting. Clients stopped this way will invoke
    # the on_disconnect handler normally.
    def on_connect &handler #:yields: endpoint, io
      @on_connect = handler
      self
    end

    # Callback that gets invoked when a client disconnects.
    # The exception is the error that occured (usually EOFError).
    def on_disconnect &handler #:yields: endpoint, io, transport_id, exception
      @on_disconnect = handler
      self
    end

    private

    def _handle message
      @handler.call(self, message)
    end

    def _acceptor_thread
      loop do
        client = @acceptor.call(self)
        @clients << client
        Thread.new { _read_thread(client) }
      end
    end

    def _read_thread client
      _transport_id = nil
      _exception = nil

      catch(:kill_client) {
        @on_connect.call(self, client)

        loop do
          message, transport_id, serial, answer = nil, 0, 0, nil

          begin
            message, transport_id, serial = @protocol.read_message(client)
          rescue => e
            _exception = e
            break
          end
          _transport_id ||= transport_id
          @last_answer[_transport_id] ||= [0, 0]

          if transport_id != _transport_id
            answer = Exception.new("You cannot change your transport_id once set (original id: #{_transport_id.inspect}, given id: #{transport_id.inspect})")

          elsif _transport_id != 0 && serial != 0 && @last_answer[_transport_id][0] == serial
            answer = @last_answer[_transport_id][1]

          else

            begin
              answer = _handle(message)
            rescue Exception => e
              answer = @on_handler_error.call(self, message, e)
            end
            @last_answer[_transport_id] = [serial, answer]
          end

          begin
            @protocol.write_message(client, answer, _transport_id, serial)
          rescue => e
            _exception = e
            break
          end
        end
      }

      @on_disconnect.call(self, client, _transport_id, _exception)
      @last_answer.delete(_transport_id)
      @clients.delete(client)
    end
  end
end
