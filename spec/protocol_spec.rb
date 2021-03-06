require File.join(File.dirname(__FILE__), 'spec_helper')

shared_examples "ProtocolChain" do
  include_examples "ProtocolChainSetup"

  it "should convert without io correctly" do
    v = @chain.to @testdata_a
    from = @chain.from(v[0])
    from[0].should == @testdata_a
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
    unless @testdata_a.is_a?(Array)
      message = @testdata_a * (Arpie::MTU + 10)
      chain_write(message)
      chain_read.should == message
    end
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

shared_examples "ObjectProtocolChain" do
  include_examples "ProtocolChain"
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

shared_examples "RPCProtocolChain" do
  include_examples "RPCProtocolChainSetup"

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
  include_examples "ProtocolChain"
end

describe "Sized::Sized" do subject { [Arpie::SizedProtocol, Arpie::SizedProtocol] }
  include_examples "ProtocolChain"
end

describe "Sized::Marshal::Sized" do subject { [Arpie::SizedProtocol, Arpie::MarshalProtocol, Arpie::SizedProtocol] }
  include_examples "ProtocolChain"
end

describe "Zlib::Marshal::Sized" do subject { [Arpie::ZlibProtocol, Arpie::MarshalProtocol, Arpie::SizedProtocol] }
  include_examples "ProtocolChain"
end

# Shellwords is a bit of a special case, because it only encodes arrays.
describe "Shellwords::Separator" do subject { [Arpie::ShellwordsProtocol, Arpie::SeparatorProtocol] }
  include_examples "ProtocolChain"
  before do
    @testdata_a, @testdata_b = ['I am test', '1'], ['I am test', '2']
  end
end

describe "YAML::Sized" do subject { [Arpie::YAMLProtocol, Arpie::SizedProtocol] }
  include_examples "ObjectProtocolChain"
end
