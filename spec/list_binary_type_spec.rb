require File.join(File.dirname(__FILE__), 'spec_helper')

describe "ListBinaryType" do
  describe "length as virtual" do
    class Inner < Arpie::Binary
      field :sz, :uint8
      field :ls, :list, :of => :uint8, :length => :sz
    end

    class Outer < Arpie::Binary
      field :totalsz, :uint8

      field :bytes, :bytes, :length => :totalsz do
        field :content, :list, :of => Inner,
          :length => :all
      end

      field :end, :uint8
    end

    it "reads correctly when all bytes are eaten" do
      c, consumed = Outer.from [8,   2, 0, 1,   4, 0, 1, 2, 3, 0xff].pack("C*")
      consumed.should == 10
      c.bytes.content.size.should == 2
      c.bytes.content[0].ls.should == [0, 1]
      c.bytes.content[1].ls.should == [0, 1, 2, 3]
      c.end.should == 0xff
    end

    it "raises EIncomplete when partial data remains" do
      proc { Outer.from [8, 0, 1, 2, 3, 4, 5, 6, 7,  4, 1, 2 ].pack("C*") }.should raise_error Arpie::EIncomplete
    end

    it "fails on invalid length specification" do
      klass = Class.new(Arpie::Binary) do
        list :maxonly, :of => :char,
          :sizeof => :int8
      end

      proc { klass.from("\xff") }.should raise_error StreamError
    end
  end
end
