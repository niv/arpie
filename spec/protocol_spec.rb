require File.join(File.dirname(__FILE__), 'spec_helper')

describe "ProtocolChainSetup", :shared => true do
  it_should_behave_like "IO Mockup"

  before do
    @chain = Arpie::ProtocolChain.new(*subject)
  end
end

describe "ProtocolChain", :shared => true do
  it_should_behave_like "ProtocolChainSetup"

  it "should convert without io correctly" do
    v = @chain.to "x"
    @chain.from(v).should == ["x"]
  end

  it "should read written binary data correctly" do
    chain_write("x")
    chain_read.should == "x"
    @chain.buffer.size.should == 0
    @chain.messages.size.should == 0
  end

  it "should read multiple written messages correctly" do
    write = []
    for i in 1...10 do
      write << "x#{i}"
    end
    chain_write(*write)

    for i in 1...10 do
      chain_read.should == "x#{i}"
    end

    @chain.buffer.size.should == 0
    @chain.messages.size.should == 0
  end

  it "should not clobber the buffer before the first read" do
    chain_write("hi")
    @chain.buffer.size.should == 0
    @chain.messages.size.should == 0
  end

  it "should parse a io-written buffer correctly" do
    write = []
    for i in 1...10 do
      write << "x#{i}"
    end
    chain_write(*write)

    @chain.from(@r.readpartial(4096)).should == %w{x1 x2 x3 x4 x5 x6 x7 x8 x9}
  end

  it "should read messages greater than MTU correctly" do
    chain_write(message = ("M" * (Arpie::MTU + 10)))
    chain_read.should == message
  end

  it "should not fail on interleaved io streams" do
    r2, w2 = IO.pipe
    chain_write("1" * 2048)
    @chain.write_message(w2, "2" * 2048)
    w2.close
    chain_read.should == "1" * 2048
    @chain.read_message(r2).should == "2" * 2048
  end
end

describe "ObjectProtocolChain", :shared => true do
  it_should_behave_like "ProtocolChain"
  # Now, lets try some variations.

  it "should read written objects correctly" do
    chain_write(
      a = [1, 2.4, false, true, nil, "string"],
      b = {1 => "hi", 2 => "test", 3 => "bloh"}
    )

    chain_read.should == a
    chain_read.should == b
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
