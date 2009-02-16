require File.join(File.dirname(__FILE__), 'spec_helper')

describe "ProtocolChain", :shared => true do
  it_should_behave_like "IO Mockup"

  before do
    @chain = Arpie::ProtocolChain.new(*subject)
  end

  it "should convert without io correctly" do
    v = @chain.to "x"
    @chain.from(v).should == ["x"]
  end

  it "should read written binary data correctly" do
    @chain.write_message(@w, "x")
    @chain.read_message(@r).should == "x"
    @chain.buffer.size.should == 0
    @chain.messages.size.should == 0
  end

  it "should read multiple written messages correctly" do
    for i in 1...10 do
      @chain.write_message(@w, "x#{i}")
    end

    for i in 1...10 do
      @chain.read_message(@r).should == "x#{i}"
    end

    @chain.buffer.size.should == 0
    @chain.messages.size.should == 0
  end

  it "should not clobber the buffer before the first read" do
    @chain.write_message(@w, "hi")
    @chain.buffer.size.should == 0
    @chain.messages.size.should == 0
  end

  it "should parse a io-written buffer correctly" do
    for i in 1...10 do
      @chain.write_message(@w, "x#{i}")
    end
    @chain.from(@r.readpartial(4096)).should == %w{x1 x2 x3 x4 x5 x6 x7 x8 x9}
  end

  it "should read messages greater than MTU correctly" do
    @chain.write_message(@w, message = ("M" * (Arpie::MTU + 10)))
    @chain.read_message(@r).should == message
  end

  it "should not fail on interleaved io streams" do
    r2, w2 = IO.pipe
    @chain.write_message(@w, "1" * 2048)
    @chain.write_message(w2, "2" * 2048)
    @chain.read_message(@r).should == "1" * 2048
    @chain.read_message(r2).should == "2" * 2048
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
