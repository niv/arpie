require 'rubygems'

Thread.abort_on_exception = true

unless Object.const_defined?('Arpie')
  $:.unshift(File.join(File.dirname(__FILE__), "../lib/"))
  require 'arpie'
end
include Arpie

shared_examples "IO Mockup" do
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

shared_examples "ProtocolChainSetup" do
  include_examples "IO Mockup"

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

shared_examples "RPCProtocolChainSetup" do
  include_examples "IO Mockup"

  before do
    @client = Arpie::ProtocolChain.new(* subject[0].map {|x| x.new })
    @server = Arpie::ProtocolChain.new(* subject[1].map {|x| x.new })
    @testdata_a = "xa"
    @testdata_b = "xb"
  end
end



shared_examples "Binary Setup" do
end

shared_examples "Binary Tests" do
  include_examples "Binary Setup"

  before do
    @c = subject[0]
    @d = subject[1]
  end

  it "reads and packs the given example binary" do
    dd, b = @c.from(@d)
    dd.to.should == @d
  end
end

shared_examples "Binary Tests with data" do
  include_examples "Binary Tests"

  it "should raise EIncomplete when not enough data is available" do
    proc { @c.from("")}.should raise_error Arpie::EIncomplete
  end

  it "returns the proper cutoff position" do
    dd, b = @c.from(@d + "xxyzz")
    b.should == @d.size
  end

  it "returns a valid binary size"
end
