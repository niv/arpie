require 'rubygems'
require 'arpie'
require 'socket'

class MyHandler
  def reverse str
    str.reverse
  end
end

server = TCPServer.new(51210)

e = Arpie::ProxyServer.new(Arpie::MarshalProtocol.new, Arpie::SizedProtocol.new)

e.handle MyHandler.new

e.accept do
  server.accept
end

p = Arpie::ProxyClient.new(Arpie::MarshalProtocol.new, Arpie::SizedProtocol.new)
p.connect do |transport|
  TCPSocket.new("127.0.0.1", 51210)
end

puts p.reverse "hi"
# => "ih"
