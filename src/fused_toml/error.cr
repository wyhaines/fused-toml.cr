module FusedTOML
  # Invalid document. Byte offsets start at zero, lines and Unicode columns at one.
  class ParseError < Exception
    getter byte_offset : Int32, line : Int32, column : Int32
    getter previous_offset : Int32?

    def initialize(reason : String, source : String, @byte_offset : Int32, @previous_offset : Int32? = nil)
      @line, @column = location(source, byte_offset)
      if previous = @previous_offset
        line, column = location(source, previous)
        reason += " (first defined at #{line}:#{column})"
      end
      super("#{reason} at #{@line}:#{@column}")
    end

    private def location(source, limit)
      line = column = 1
      source.to_slice[0, limit].each do |byte|
        if byte == 10
          line += 1
          column = 1
        elsif byte & 0xc0 != 0x80
          column += 1
        end
      end
      {line, column}
    end
  end
end
