require 'rubygems'
$:.unshift(File.join(File.dirname(__FILE__), "../lib/"))
require 'socket'
require 'arpie'
require 'benchmark'

include Arpie

# Data test size.
DATA_SIZE = 512

rpc_call = RPCall.new('ns.', 'meth', [1, 2, 3, 4])
$test_data = "a" * DATA_SIZE
$test_data.freeze

# Protocols to test:
PROTOCOLS = [
  [SizedProtocol.new],
  [MarshalProtocol.new, SizedProtocol.new],
  [YAMLProtocol.new]
]

ITERATIONS = 1000

$stderr.puts "Testing protocols with a data size of #{DATA_SIZE}, #{ITERATIONS} iterations"


Benchmark.bm {|b|
  r, w = IO.pipe
  PROTOCOLS.each {|p|
    a ||= []
    proto = ProtocolChain.new *p
    r, w = IO.pipe

    b.report("%-30s\n" % p.map{|x| x.class.to_s}.inspect) {
      ITERATIONS.times do
        proto.write_message(w, $test_data)
        proto.read_message(r)
      end
    }
  }
}
