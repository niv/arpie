require File.join(File.dirname(__FILE__), 'spec_helper')

require 'socket'
require 'timeout'

describe "ClientServer", :shared => true do
  before(:all) do
    @tcp_server = TCPServer.new('127.0.0.1', 56000)
  end

  before do
    @handler_errors = 0
    $evaluate_calls = 0
    @client = Arpie::Client.new(Arpie::MarshalProtocol.new)
    @server = Arpie::Server.new(Arpie::MarshalProtocol.new)
    @client.connect do TCPSocket.new('127.0.0.1', 56000) end
    @server.accept do @tcp_server.accept end
    @server.on_handler_error do |s, e, p, x|
      @handler_errors += 1
    end

    @server.handle do |s, e, m|
      e.write_message m
    end
  end
end

describe "ProxyClientServer", :shared => true do
  before(:all) do
    @tcp_server = TCPServer.new('127.0.0.1', 56001)
  end

  before do
    @handler_errors = 0
    $evaluate_calls = 0
    @client = Arpie::ProxyClient.new(Arpie::MarshalProtocol.new)
    @server = Arpie::ProxyServer.new(Arpie::MarshalProtocol.new)
    @client.connect do TCPSocket.new('127.0.0.1', 56001) end
    @server.accept do @tcp_server.accept end
    @server.on_handler_error do |s, e, p, x|
      @handler_errors += 1
    end

    @server.handle((Class.new do
      def evaluate_calls
        $evaluate_calls += 1
      end
      def raise_something
        raise "test"
      end
    end).new)
  end
end

describe Arpie::Client do
  it_should_behave_like "ClientServer"
end

describe Arpie::EventedClient do
  it_should_behave_like "ClientServer"

  before do
    @client = Arpie::EventedClient.new(Arpie::MarshalProtocol.new)
    @handler_calls = 0
    @queue = Queue.new
    @client.handle do
      @queue.push true
      @handler_calls += 1
    end
    @client.connect do TCPSocket.new('127.0.0.1', 56000) end
  end

  it "should not allow reading messages" do
    @client.should_not respond_to :read_message
  end

  it "should call the handler for incoming messages" do
    @client.write_message "test"
    lambda {Timeout.timeout(1.0) { @queue.pop } }.should_not raise_error TimeoutError
  end
end

describe Arpie::Server do
  it_should_behave_like "ClientServer"
end

describe "ProxyServer" do
  it_should_behave_like "ProxyClientServer"
  it "should raise handler errors to the client" do
    lambda { @client.raise_something }.should(raise_error RuntimeError, "Internal Error")
    @handler_errors.should == 1
  end

  it "should not re-evaluate for already-seen uuids" do
    @client.evaluate_calls
    @client.evaluate_calls
    @client.uuid_generator do 100 end
    @client.evaluate_calls
    @client.evaluate_calls
    $evaluate_calls.should == 3
  end

  it "should not call handler errors for missing methods" do
    lambda { @client.missing }.should raise_error NoMethodError
    $evaluate_calls.should == 0
  end
end
