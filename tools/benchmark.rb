require 'rubygems'
require 'socket'
require 'arpie'
require 'benchmark'
require 'drb'
require 'xmlrpc/server'
require 'xmlrpc/client'

class Wrap
  def reverse x
    x.reverse
  end
end

include Arpie

server = TCPServer.new(51210)

endpoint = ProxyEndpoint.new MarshalProtocol.new
endpoint.handle Wrap.new

endpoint.accept do
  server.accept
end

$transport = Transport.new MarshalProtocol.new
$transport.connect(false) do |transport|
  TCPSocket.new("127.0.0.1", 51210)
end
$proxy = Proxy.new $transport

Benchmark.bm {|b|

  puts ""
  puts "native DRb"
  drbserver = DRb.start_service nil, Wrap.new
  drbobject = DRbObject.new nil, DRb.uri

  b.report("   1") { 1.times { drbobject.reverse "benchmark" } }
  b.report("1000") { 1000.times { drbobject.reverse "benchmark" } }

  puts ""
  puts "ruby xmlrpc/server - too slow to benchmark"
  #server = XMLRPC::Server.new(51211, "127.0.0.1", 4, nil, false)
  #server.add_handler(XMLRPC::iPIMethods("wrap"), Wrap.new)
  #server_thread = Thread.new { server.serve }
  #client = XMLRPC::Client.new( "127.0.0.1", "/", 51211)
  #b.report("   1") {    1.times { client.call("wrap.reverse", "benchmark") } }
  #b.report("1000") { 1000.times { client.call("wrap.reverse", "benchmark") } }
  #server.shutdown
  #server_thread.join

  puts ""
  puts "Arpie: proxied MarshalProtocol"
  b.report("   1") {    1.times { $proxy.reverse "benchmark" } }
  b.report("1000") { 1000.times { $proxy.reverse "benchmark" } }
}
