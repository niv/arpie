require File.join(File.dirname(__FILE__), 'spec_helper')

EXPATH = File.dirname(__FILE__) + "/../examples"

describe "examples" do
  for rb in Dir[EXPATH + "/*.rb"] do
    describe rb do specify {
      ret = `ruby -I#{File.dirname(__FILE__) + "/../lib"} #{rb}`
      $?.exitstatus.should == 0
    } end
  end
end
