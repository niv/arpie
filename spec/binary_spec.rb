require File.join(File.dirname(__FILE__), 'spec_helper')

describe Arpie::Binary do

  describe "empty:" do subject {
    [
      Class.new(Binary) do
      end,
      ""
    ]
  }
    include_examples "Binary Tests"
  end

  describe "basic sanity:" do subject {
    [
      Class.new(Binary) do
        field :a, :uint32
        field :b, :uint32
        field :c, :uint64
        field :s, :string, :length => 4
      end,
      [1, 2, 3, "abcd"].pack("I I Q a4")
    ]
  }

    include_examples "Binary Tests with data"
  end

  describe ".virtual:" do subject {
    [
      Class.new(Binary) do
        field :a, :uint8
        field :b, :uint8
        virtual :c, :uint8 do |o| o.a * o.b end
      end,
      [1, 2].pack("CC")
    ]
  }

    it "evaluates the block given" do
      b, co = @c.from(@d)
      b.c.should == b.a * b.b
    end

    include_examples "Binary Tests with data"
  end

  describe ".aliases:" do subject {
    [
      Class.new(Binary) do
        f :a, :uint8
        f :b, :uint8
        s "hio!"
        v :c, :uint8 do |o| o.a * o.b end
      end,
      [1, 2, "hio!"].pack("CCa4")
    ]
  }

    include_examples "Binary Tests with data"
  end

  describe ":default:" do subject {
    [
      Class.new(Binary) do
        field :a, :uint8
        field :b, :uint8, :default => 5, :optional => true
        v :c, :uint8 do |o| o.a * o.b end
      end,
      [1, 2].pack("CC")
    ]
  }

    it "does not use the default when a value was read" do
      b, con = @c.from([1, 2].pack("CC"))
      b.a.should == 1
      b.b.should == 2
    end

    it "uses the default when no value is present" do
      b, con = @c.from([1].pack("C"))
      b.a.should == 1
      b.b.should == 5
    end

    include_examples "Binary Tests with data"
  end


end
