module Arpie

  # Raised by arpie when a Protocol thinks the stream got corrupted
  # (by calling bogon!).
  # This usually results in a dropped connection.
  class StreamError < IOError ; end
  # Raised by arpie when a Protocol needs more data to parse a packet.
  # Usually only of relevance to the programmer when using Protocol#from directly.
  class EIncomplete < Errno::EAGAIN ; end

  # @private
  # Used internally by arpie.
  class YieldResult < RuntimeError
    attr_reader :result
    def initialize result
      @result = result
    end
  end

  # Call this if you think the stream has been corrupted, or
  # non-protocol data arrived.
  # +message+ is the text to display.
  # +data+ is the optional misbehaving data for printing.
  # This breaks out of the caller.
  def bogon! data = nil, message = nil
    raise StreamError, "#{self.is_a?(Class) ? self.to_s : self.class.to_s}:" +
      " BOGON#{data.nil? ? "" : " " + data.inspect}" +
      "#{message.nil? ? "" : " -- #{message}" }"
  end

  # Tell the caller that the given chunk of data
  # is not enough to construct a whole message.
  # This breaks out of the caller.
  def incomplete!
    raise EIncomplete, "#{self.is_a?(Class) ? self : self.class} needs more data"
  end
end
