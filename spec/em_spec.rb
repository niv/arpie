require File.join(File.dirname(__FILE__), 'spec_helper')

require 'eventmachine'

describe 'Eventmachine usecase' do
  specify do
    $m = nil

    EM::run {
      EM::start_server "127.0.0.1", 19400, Arpie::EventMachine::ArpieProtocol,
          Arpie::SeparatorProtocol.new do |proto|
        def proto.receive(message)
          $m = message
          EventMachine::stop_event_loop
        end
      end

      EM::connect "127.0.0.1", 19400, Arpie::EventMachine::ArpieProtocol,
          Arpie::SeparatorProtocol.new do |proto|

        proto.send("hi")
      end
    }

    $m.should == "hi"
  end
end
