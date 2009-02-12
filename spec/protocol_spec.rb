require File.join(File.dirname(__FILE__), 'spec_helper')

describe "Protocol", :shared => true do
  it_should_behave_like "IO Mockup"

  it "should read written binary data correctly" do
    subject.write_message(@w, "x")
    subject.read_message(@r).should == "x"
  end

  it "should read multiple written messages correctly" do
    for i in 1...10 do
      subject.write_message(@w, "x#{i}")
    end

    for i in 10...1 do
      subject.read_message(@r).should == "x#{i}"
    end
  end
end

describe "ObjectProtocol", :shared => true do
  it_should_behave_like "Protocol"

  it "should read written objects correctly" do
    subject.write_message(@w, a = [1, 2.4, false, true, nil, "string"])
    subject.write_message(@w, b = {1 => "hi", 2 => "test", 3 => "bloh"})

    subject.read_message(@r).should == a
    subject.read_message(@r).should == b
  end
end

describe Arpie::SizedProtocol do
  it_should_behave_like "Protocol"
end

describe Arpie::SeparatorProtocol do
  it_should_behave_like "Protocol"

  it "should encode special characters"
end

describe Arpie::ShellwordsProtocol do
  it_should_behave_like "IO Mockup"

  it "should read written arguments correctly" do
    subject.write_message(@w, a = ["I am a", "multiword", "shell arg"])
    subject.read_message(@r).should == a
  end

  it "should accept non-string arguments" do
    subject.write_message(@w, a = ["I am a", "number: ", 12])
    subject.read_message(@r).should == ["I am a", "number: ", "12"]
  end
end

describe Arpie::YAMLProtocol do
  it_should_behave_like "ObjectProtocol"
end

describe Arpie::MarshalProtocol do
  it_should_behave_like "ObjectProtocol"
end
