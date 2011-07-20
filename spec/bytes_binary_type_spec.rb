require File.join(File.dirname(__FILE__), 'spec_helper')

describe "BytesBinaryType" do
  describe "sizeof and length" do subject {
    [
      Class.new(Arpie::Binary) do
        field :s, :string, :sizeof => :uint8
        field :d, :string, :length => 5
      end,
      [4, "abcd", "12345"].pack("C a4 a5")
    ]
  }

    include_examples "Binary Tests with data"
  end

  describe "virtual length" do subject {
    [
      Class.new(Arpie::Binary) do
        field :v, :uint8
        field :d, :string, :length => :v
      end,
      [4, "abcd"].pack("C a4")
    ]
  }

    include_examples "Binary Tests with data"
  end

  describe "length as virtual should not update the virtual" do subject {
    [
      Class.new(Arpie::Binary) do
        field :data_length, :uint8
        field :data, :bytes, :length => :data_length
      end,
      [4, "abcd"].pack("C a4")
    ]
  }

    include_examples "Binary Tests with data"

    it "does not change virtuals on data change" do
      dd, b = @c.from(@d + "xxyzz")
      dd.data += "a"
      expect = [4, "abcda"].pack("Ca*")
      dd.to.should == expect
    end
  end
end
