module FusedTOML
  private class Parser
    # Copy plain strings once. Only escapes and CRLF normalization need a builder.
    private def string(*, multiline_allowed = true) : String
      quote = peek
      @pos += 1
      multiline = multiline_allowed && peek == quote && peek(1) == quote
      if multiline
        @pos += 2
        newline
      end
      basic = quote == '"'
      start = @pos
      builder = nil
      loop do
        @pos = ASCIIStringScanner.find_special(@bytes, @pos, @bytes.size) if basic
        fail_at("unterminated string") if eof?
        char = peek
        if char == quote
          run = 1
          if multiline
            while run < 5 && peek(run) == quote
              run += 1
            end
            if run < 3
              @pos += run
              next
            end
          end
          finish = @pos + (multiline ? run - 3 : 0)
          @pos += run
          if builder
            builder.write(@bytes[start, finish - start])
            return builder.to_s
          end
          return @source.byte_slice(start, finish - start)
        elsif basic && char == '\\'
          builder ||= String::Builder.new
          builder.write(@bytes[start, @pos - start])
          @pos += 1
          escape(builder, multiline)
          start = @pos
        elsif multiline && char == '\r'
          builder ||= String::Builder.new
          builder.write(@bytes[start, @pos - start])
          newline
          builder << '\n'
          start = @pos
        else
          check_control unless multiline && char == '\n'
          @pos += 1
        end
      end
    end

    private def escape(builder, multiline)
      char = peek
      if multiline && char.in?(' ', '\t', '\r', '\n')
        spaces
        fail_at("expected newline in continuation") unless newline
        loop do
          spaces
          break unless newline
        end
        return
      end
      fail_at("unterminated escape") if eof?
      @pos += 1
      case char
      when '"', '\\' then builder << char
      when 'b'       then builder << '\b'
      when 'e'       then builder << '\e'
      when 'f'       then builder << '\f'
      when 'n'       then builder << '\n'
      when 'r'       then builder << '\r'
      when 't'       then builder << '\t'
      when 'x'       then builder << hex_scalar(2)
      when 'u'       then builder << hex_scalar(4)
      when 'U'       then builder << hex_scalar(8)
      else                fail_at("invalid escape", @pos - 1)
      end
    end

    private def hex_scalar(width)
      start = @pos
      number = 0_u32
      width.times do
        digit = peek.to_i?(16) || fail_at("expected hexadecimal digit")
        number = (number << 4) | digit.to_u32
        @pos += 1
      end
      if (0xd800..0xdfff).includes?(number) || number > 0x10ffff
        fail_at("invalid Unicode scalar", start)
      end
      number.chr
    end
  end
end
