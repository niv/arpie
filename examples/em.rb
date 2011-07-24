require 'rubygems'
require 'arpie'
require 'arpie/em'

EM::run {
  EM::start_server "127.0.0.1", 51210, Arpie::EventMachine::ArpieProtocol,
    Arpie::SeparatorProtocol.new do |c|
      def c.receive message
        puts message.reverse
        EM::stop_event_loop
      end
    end

  EM::connect "127.0.0.1", 51210, Arpie::EventMachine::ArpieProtocol,
    Arpie::SeparatorProtocol.new do |c|
      c.send "hi"
    end
}
