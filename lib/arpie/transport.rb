module Arpie

  # A Transport is a connection manager, and acts as the
  # glue between a user-defined medium (for example, a TCP
  # socket), and a protocol.
  #
  # See README for examples.
  class Transport
    attr_reader :protocol

    def initialize protocol
      @protocol = protocol
      @io = nil
    end

    # Provide a connector block, which will be called
    # each time a connection is needed.
    # Set +connect_immediately+ to true to connect
    # immediately, instead on the first message.
    def connect connect_immediately = false, &connector
      @connector = connector
      _connect if connect_immediately
    end

    # Send a message and receive a reply.
    def request message
      _connect
      @protocol.write_message(@io, message)
      @protocol.read_message(@io)
    end

    private
    def _connect
      @io ||= @connector.call(self)
    end
  end
end
