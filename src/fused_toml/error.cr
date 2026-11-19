module FusedTOML
  # Invalid document. Byte offsets start at zero, lines and Unicode columns at one.
  class ParseError < Exception
    getter byte_offset : Int32, line : Int32, column : Int32
    getter previous_offset : Int32?, previous_line : Int32?, previous_column : Int32?

    def initialize(reason : String, source : String, @byte_offset : Int32, @previous_offset : Int32? = nil)
      @line, @column = location(source, byte_offset)
      if previous = @previous_offset
        @previous_line, @previous_column = location(source, previous)
        reason += " (first defined at #{@previous_line}:#{@previous_column})"
      end
      super("#{reason} at #{@line}:#{@column}")
    end

    private def location(source, limit)
      line = column = 1
      bytes = source.to_slice
      index = 0
      while index < limit
        byte = bytes[index]
        index += 1
        if byte == 10
          line += 1
          column = 1
        else
          # A byte budget can end inside a Unicode scalar. All of its bytes
          # belong to the same column, even if IO supplied just one probe byte.
          extra = case byte
                  when 0xc2..0xdf then 1
                  when 0xe0..0xef then 2
                  when 0xf0..0xf4 then 3
                  else                 0
                  end
          extra.times do
            break if index >= bytes.size || bytes[index] & 0xc0 != 0x80
            return {line, column} if index == limit
            index += 1
          end
          column += 1
        end
      end
      {line, column}
    end
  end
end
