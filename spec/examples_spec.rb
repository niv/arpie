EXPATH = File.dirname(__FILE__) + "/../examples"

describe "examples" do
  for rb in Dir[EXPATH + "/*.rb"] do
    describe rb do specify {
      ret = `ruby -I#{File.dirname(__FILE__) + "/../lib"} #{rb}`
      $?.should == 0
      ret.strip.should == "ih"
    } end
  end
end
