require 'eventmachine'

module Arpie
  module EventMachine
    # A EventMachine protocol implementing a simple protocol
    # chain handler. To use, simply include it in your EM
    # Connection moduleas you would any other EM protocol.
    #
    # The module expects a list of protocols given along with
    # the module initializer:
    #   EM::start_server host, port, ArpieProtocol,
    #     Arpie::MarshalProtocol.new, Arpie::SizedProtocol.new
    #
    # To receive messages, override <tt>receive(message)</tt>, which will
    # be called once for each message decoded with the given
    # protocols.
    #
    # To send messages back over the same connection, simply call
    # <tt>send(message)</tt>.
    #
    # Note that this module isn't included by requiring just 'arpie'.
    # You will need to require 'arpie/em'.
    module ArpieProtocol
      attr_reader :chain

      def initialize *protocols
        @chain = Arpie::ProtocolChain.new(*protocols)
      end

      # Receive a message. Override this in your implemention.
      def receive message
      end

      def receive_data data
        begin
          for msg in @chain.from(data)
            receive msg
          end
        rescue Arpie::EIncomplete
          nil
        end
      end

      # Send a message, encoding it with the given
      # protocols.
      def send message
        for msg in @chain.to(message)
          send_data(msg)
        end
      end
    end
  end # module EventMachine
end # module Arpie
