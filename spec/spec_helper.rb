require 'rubygems'

Thread.abort_on_exception = true

unless Object.const_defined?('Arpie')
  $:.unshift(File.join(File.dirname(__FILE__), "../lib/"))
  require 'arpie'
end

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

