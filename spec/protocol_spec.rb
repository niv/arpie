require File.join(File.dirname(__FILE__), 'spec_helper')

describe "ProtocolChain", :shared => true do
  it_should_behave_like "ProtocolChainSetup"

  it "should convert without io correctly" do
    v = @chain.to @testdata_a
    @chain.from(v).should == [@testdata_a]
  end

  it "should read written binary data correctly" do
    chain_write(@testdata_a)
    chain_read.should == @testdata_a
  end

  it "should read multiple written messages correctly" do
    write = []
    for i in 0...4 do
      write << (i % 2 == 0 ? @testdata_a : @testdata_b)
    end
    chain_write(*write)

    for i in 0...4 do
      chain_read.should == (i % 2 == 0 ? @testdata_a : @testdata_b)
    end
  end

  it "should not clobber the buffer before the first read" do
    chain_write(@testdata_a)
  end

  it "should parse a io-written buffer correctly" do
    write = []
    for i in 0...4 do
      write << (i % 2 == 0 ? @testdata_a : @testdata_b)
    end
    chain_write(*write)

    @chain.from(@r.readpartial(4096)).should == [@testdata_a, @testdata_b, @testdata_a, @testdata_b]
  end

  it "should read messages greater than MTU correctly" do
    chain_write(message = (@testdata_a * (Arpie::MTU + 10)))
    chain_read.should == message
  end

  it "should not fail on interleaved io streams" do
    r2, w2 = IO.pipe
    chain_write(@testdata_a)
    @chain.write_message(w2, @testdata_b)
    w2.close
    chain_read.should == @testdata_a
    @chain.read_message(r2).should == @testdata_b
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

describe "RPCProtocolChain", :shared => true do
  it_should_behave_like "RPCProtocolChainSetup"

  it "should send namespace-less RPC calls correctly encoded" do
    call = Arpie::RPCall.new(nil, 'meth', [1, 2, 3])
    @client.write_message(@w, call)
    @w.close
    @server.read_message(@r).should == call
  end

  it "should send namespaced RPC calls correctly encoded" do
    call = Arpie::RPCall.new('ns', 'meth', [1, 2, 3])
    @client.write_message(@w, call)
    @w.close
    @server.read_message(@r).should == call
  end

  it "should encode result values correctly" do
    for r in inp = [1, 2.4, false, true, "string", {"1"=>"hash"}, [1,2,3]]
      @server.write_message(@w, r)
    end
    @w.close

    for r in inp
      @client.read_message(@r).should == r
    end
  end
end

# Now, lets try some variations.

describe "Sized" do subject { [Arpie::SizedProtocol] }
  it_should_behave_like "ProtocolChain"
end

describe "Sized::Sized" do subject { [Arpie::SizedProtocol, Arpie::SizedProtocol] }
  it_should_behave_like "ProtocolChain"
end

describe "Sized::Marshal::Sized" do subject { [Arpie::SizedProtocol, Arpie::MarshalProtocol, Arpie::SizedProtocol] }
  it_should_behave_like "ProtocolChain"
end

# Shellwords is a bit of a special case, because it only encodes arrays.
describe "Shellwords::Separator" do subject { [Arpie::ShellwordsProtocol, Arpie::SeparatorProtocol] }
  it_should_behave_like "ProtocolChain"
  before do
    @testdata_a, @testdata_b = ['I am test', '1'], ['I am test', '2']
  end
end

describe "HTTPTest" do subject { [Arpie::HTTPClientTestProtocol] }
  it_should_behave_like "ProtocolChain"
end

describe "HTTPTest" do subject { [Arpie::HTTPServerTestProtocol] }
  it_should_behave_like "ProtocolChain"
end

describe "YAML" do subject { [Arpie::YAMLProtocol] }
  it_should_behave_like "ObjectProtocolChain"
end

describe "XMLRPC::Sized" do subject {
    [
      [Arpie::XMLRPCClientProtocol, Arpie::SizedProtocol],
      [Arpie::XMLRPCServerProtocol, Arpie::SizedProtocol]
    ]
  }
  it_should_behave_like "RPCProtocolChain"
end

describe "XMLRPC::HTTPTest" do subject {
    [
      [Arpie::XMLRPCClientProtocol, Arpie::HTTPClientTestProtocol],
      [Arpie::XMLRPCServerProtocol, Arpie::HTTPServerTestProtocol]
    ]
  }
  it_should_behave_like "RPCProtocolChain"
end

