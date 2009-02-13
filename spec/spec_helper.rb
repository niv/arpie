require 'rubygems'

Thread.abort_on_exception = true

unless Object.const_defined?('Arpie')
  $:.unshift(File.join(File.dirname(__FILE__), "../lib/"))
  require 'arpie'
end

describe "IO Mockup", :shared => true do
  before do
    @r, @w = IO.pipe
  end
end
