module Arpie

  # Raised by arpie when a Protocol thinks the stream got corrupted
  # (by calling bogon!).
  # This usually results in a dropped connection.
  class StreamError < IOError ; end
  # Raised by arpie when a Protocol needs more data to parse a packet.
  # Usually only of relevance to the programmer when using Protocol#from directly.
  class EIncomplete < RuntimeError ; end

  # :stopdoc:
  # Used internally by arpie.
  class ETryAgain < RuntimeError ; end
  class YieldResult < RuntimeError
    attr_reader :result
    def initialize result
      @result = result
    end
  end
  # :startdoc:

  # Call this if you think the stream has been corrupted, or
  # non-protocol data arrived.
  # +message+ is the text to display.
  # +data+ is the optional misbehaving data for printing.
  # This breaks out of the caller.
  def bogon! data = nil, message = nil
    raise StreamError, "#{self.to_s}#{message.nil? ? " thinks the data is bogus" : ": " + message }#{data.nil? ? "" : ": " + data.inspect}."
  end

  # Tell the caller that the given chunk of data
  # is not enough to construct a whole message.
  # This breaks out of the caller.
  def incomplete!
    raise EIncomplete, "#{self} needs more data."
  end
end
