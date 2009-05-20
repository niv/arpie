require File.join(File.dirname(__FILE__), 'spec_helper')

describe FixedBinaryType do

  it "always returns the fixed size" do
    subject.from("aaaa", :value => "aaaa").should == ["aaaa", 4]
  end

  it "always encodes to fixed size" do
    subject.to("aaaa", :value => "aaaa").should == "aaaa"
  end

  it "returns the proper binary size" do
    subject.binary_size(:value => "aaaa").should == 4
  end

  it "should raise error on mismatch in #from" do
    proc { subject.from("aaa", :value => "aaaa") }.should raise_error StreamError
  end

  it "raises error on mismatch in #to" do
    proc { subject.to("aaa", :value => "aaaa") }.should raise_error StreamError
  end

  it "raiseserror on missing option" do
    proc { subject.from("aaa", {}) }.should raise_error ArgumentError
    proc { subject.to("aaa", {}) }.should raise_error ArgumentError
  end
end
