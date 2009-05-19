require 'rubygems'
require 'socket'
$:.unshift(File.join(File.dirname(__FILE__), "../lib/"))
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

endpoint = ProxyServer.new MarshalProtocol.new, SizedProtocol.new
endpoint.handle Wrap.new

endpoint.accept do
  server.accept
end

$proxy = ProxyClient.new MarshalProtocol.new, SizedProtocol.new
$proxy.connect(true) do
  TCPSocket.new("127.0.0.1", 51210)
end

Benchmark.bm {|b|

  puts ""
  puts "native DRb"
  drbserver = DRb.start_service nil, Wrap.new
  drbobject = DRbObject.new nil, DRb.uri

  b.report("   1") { 1.times { drbobject.reverse "benchmark" } }
  b.report("1000") { 1000.times { drbobject.reverse "benchmark" } }

  puts ""
  puts "Arpie: proxied MarshalProtocol with replay protection through uuidtools"
  b.report("   1") {    1.times { $proxy.reverse "benchmark" } }
  b.report("1000") { 1000.times { $proxy.reverse "benchmark" } }

  puts ""
  puts "Arpie: proxied MarshalProtocol without replay protection"
  $proxy.replay_protection = false
  b.report("   1") {    1.times { $proxy.reverse "benchmark" } }
  b.report("1000") { 1000.times { $proxy.reverse "benchmark" } }
}
