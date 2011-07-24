require 'rubygems'
require 'arpie'
require 'socket'

server = TCPServer.new(51210)

e = Arpie::Server.new(Arpie::MarshalProtocol.new, Arpie::SizedProtocol.new)

e.handle do |server, ep, msg|
  ep.write_message msg.reverse
end

e.accept do
  server.accept
end

c = Arpie::Client.new(Arpie::MarshalProtocol.new, Arpie::SizedProtocol.new)
c.connect do
  TCPSocket.new("127.0.0.1", 51210)
end

c.write_message "hi"
puts c.read_message
# => "ih"
