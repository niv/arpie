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

  def chain_write *m
    m.each {|mm|
      @chain.write_message(@w, mm)
    }
    @w.close
  end

  def chain_read
    @chain.read_message(@r)
  end

  def chain_r_w *m
    chain_write *m
    chain_read
  end
end
