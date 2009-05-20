require 'rubygems'

Thread.abort_on_exception = true

unless Object.const_defined?('Arpie')
  $:.unshift(File.join(File.dirname(__FILE__), "../lib/"))
  require 'arpie'
end
include Arpie

describe "IO Mockup", :shared => true do
  before do
    @r, @w = IO.pipe
  end

  def chain_write *m
    m.each {|mm|
      @chain.write_message(@w, mm)
    }
    @w.close
  end

  def chain_read
    @chain.read_message(@r)
  end

  def chain_r_w *m
    chain_write *m
    chain_read
  end
end

describe "ProtocolChainSetup", :shared => true do
  it_should_behave_like "IO Mockup"

  before do
    @chain = Arpie::ProtocolChain.new(* subject.map {|x| x.new })
    @testdata_a = "xa"
    @testdata_b = "xb"
  end

  # Make sure that no stray buffer contents remain.
  after do
    @chain.buffer.size.should == 0
    @chain.messages.size.should == 0
  end
end

describe "RPCProtocolChainSetup", :shared => true do
  it_should_behave_like "IO Mockup"

  before do
    @client = Arpie::ProtocolChain.new(* subject[0].map {|x| x.new })
    @server = Arpie::ProtocolChain.new(* subject[1].map {|x| x.new })
    @testdata_a = "xa"
    @testdata_b = "xb"
  end
end



describe "Binary Setup", :shared => true do
  before do
    @c = subject[0]
    @d = subject[1]
  end
end

describe "Binary Tests", :shared => true do
  it_should_behave_like "Binary Setup"

  it "reads and packs the given example binary" do
    dd, b = @c.from(@d)
    dd.to.should == @d
  end
end

describe "Binary Tests with data", :shared => true do
  it_should_behave_like "Binary Tests"

  it "should raise EIncomplete when not enough data is available" do
    proc { @c.from("")}.should raise_error Arpie::EIncomplete
  end

  it "returns the proper cutoff position" do
    dd, b = @c.from(@d + "xxyzz")
    b.should == @d.size
  end

  it "returns a valid binary size"
end
