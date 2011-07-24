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

    it "uses the default for new binaries" do
      new = @c.new
      new.b.should == 5
    end

    include_examples "Binary Tests with data"
  end

  describe ":fixed:" do subject {
    [
      Class.new(Binary) do
        field :a, :fixed, :value => "abc"
      end,
      ["abc"].pack("a*")
    ]
  }

    it "does not use the default for new binaries when using :fixed" do
      @c.new.a.should == nil
    end

    it "fails on parsing invalid values" do
      proc { @c.from("abd") }.should raise_error Arpie::StreamError
    end

    it "fails on setting invalid values" do
      proc {
        c = @c.new
        c.a = "abd"
        c.to
      }.should raise_error Arpie::StreamError
    end

    include_examples "Binary Tests with data"
  end

  describe "static:" do subject {
    [
      Class.new(Binary) do
        static :a, "abc"
      end,
      ["abc"].pack("a*")
    ]
  }

    it "uses the default for new binaries" do
      new = @c.new.to.should == "abc"
    end

    it "fails on parsing invalid values" do
      proc { @c.from("abd") }.should raise_error Arpie::StreamError
    end

    it "fails on setting invalid values" do
      proc {
        c = @c.new
        c.a = "abd"
        c.to
      }.should raise_error Arpie::StreamError
    end

    include_examples "Binary Tests with data"
  end

end
