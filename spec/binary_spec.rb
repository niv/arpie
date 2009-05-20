require File.join(File.dirname(__FILE__), 'spec_helper')

describe "Binary" do

  describe "empty:" do subject {
    [
      Class.new(Binary) do
      end,
      ""
    ]
  }
    it_should_behave_like "Binary Tests"
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

    it_should_behave_like "Binary Tests with data"
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

    it_should_behave_like "Binary Tests with data"

    it "evaluates the block given" do
      b, co = @c.from(@d)
      b.c.should == b.a * b.b
    end

  end
end
