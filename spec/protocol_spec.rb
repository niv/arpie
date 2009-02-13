require File.join(File.dirname(__FILE__), 'spec_helper')

describe "ProtocolChain", :shared => true do
  it_should_behave_like "IO Mockup"

  before do
    @chain = Arpie::ProtocolChain.new(*subject)
  end

  it "should read written binary data correctly" do
    @chain.write_message(@w, "x")
    @chain.read_message(@r).should == "x"
    @chain.buffer.size.should == 0
  end

  it "should read multiple written messages correctly" do
    for i in 1...10 do
      @chain.write_message(@w, "x#{i}")
    end

    for i in 1...10 do
      @chain.read_message(@r).should == "x#{i}"
    end

    @chain.buffer.size.should == 0
  end
end

describe "ObjectProtocolChain", :shared => true do
  it_should_behave_like "ProtocolChain"
  # Now, lets try some variations.

  it "should read written objects correctly" do
    @chain.write_message(@w, a = [1, 2.4, false, true, nil, "string"])
    @chain.write_message(@w, b = {1 => "hi", 2 => "test", 3 => "bloh"})

    @chain.read_message(@r).should == a
    @chain.read_message(@r).should == b
  end
end

# Now, lets try some variations.

describe [Arpie::SizedProtocol] do
  it_should_behave_like "ProtocolChain"
end

describe [Arpie::SizedProtocol, Arpie::SizedProtocol] do
  it_should_behave_like "ProtocolChain"
end

describe [Arpie::SizedProtocol, Arpie::MarshalProtocol, Arpie::SizedProtocol] do
  it_should_behave_like "ProtocolChain"
end

describe [Arpie::ShellwordsProtocol, Arpie::SeparatorProtocol] do
  it_should_behave_like "ProtocolChain"
end


describe [Arpie::YAMLProtocol] do
  it_should_behave_like "ObjectProtocolChain"
end
