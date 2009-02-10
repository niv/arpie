require 'rubygems'
require 'socket'
require 'arpie'
require 'benchmark'

include Arpie

# Data test size.
DATA_SIZE = 512

rpc_call = RPCProtocol::Call.new('ns.', 'meth', [1, 2, 3, 4])
$test_data = "a" * DATA_SIZE
$test_data.freeze

# Protocols to test:
PROTOCOLS = {
  MarshalProtocol => $test_data,
  SizedProtocol => $test_data,
  ShellwordsProtocol => $test_data,
  SeparatorProtocol => $test_data,
  YAMLProtocol => $test_data,
#   XMLRPCProtocol => [rpc_call, :server],
#  HTTPXMLRPCProtocol => [rpc_call, :client],
}

ITERATIONS = 1000

$stderr.puts "Testing protocols with a data size of #{DATA_SIZE}, #{ITERATIONS} iterations"


Benchmark.bm {|b|
  r, w = IO.pipe
  PROTOCOLS.each {|p, (d, a)|
    a ||= []
    proto = p.new(*a)
    r, w = IO.pipe

    b.report("%-30s" % p.to_s) {
      ITERATIONS.times do
        proto.write_message(w, d)
        proto.read_message(r)
      end
    }
  }
}
