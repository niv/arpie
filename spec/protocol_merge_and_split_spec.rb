require File.join(File.dirname(__FILE__), 'spec_helper')

class Splitter < Arpie::Protocol
  def from binary
    yield binary.size

    binary.each_char do |c|
      yield c
    end
  end
end

class BufferedSplitter < Arpie::Protocol
  def from binary
    unless defined? @buf
      yield binary.size * 2
      @buf = true
    end

    binary.each_char do |c|
      yield c
    end
  end
end


class Merger < Arpie::Protocol
  def from binary
    unless @expect
      @expect = binary or incomplete!
      return
    end

    assemble! binary, :d, :size => @expect
  end

  def assemble binaries, token, meta
    binaries.size >= meta[:size] or incomplete!
    yield binaries.join('')
  end
end

describe "Merger::Splitter::Sized" do subject { [Splitter, Arpie::SizedProtocol] }
  it_should_behave_like "ProtocolChainSetup"

  it "should split messages correctly" do
    chain_write(t = 'test')
    chain_read.should == t.size
    for i in 1..t.size do
      chain_read.should == t[i-1, 1]
    end
  end
end

describe "Merger::Splitter::Sized" do subject { [Merger, Splitter, Arpie::SizedProtocol] }
  it_should_behave_like "ProtocolChainSetup"

  it "should assemble split messages correctly" do
    chain_write(t = 'test')
    chain_read.should == t
  end
end

describe "Merger::BufferedSplitter::Sized" do subject { [Merger, BufferedSplitter, Arpie::SizedProtocol] }
  it_should_behave_like "ProtocolChainSetup"

  it "should re-read io for more data if assembly fails" do
    @chain.write_message(@w, "split")
    Thread.new { sleep 0.1; @chain.write_message(@w, "split") }
    chain_read.should == "splitsplit"
  end
end
