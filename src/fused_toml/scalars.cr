module FusedTOML
  private class Parser
    DECIMAL = /\A[+-]?(?:0|[1-9](?:_?[0-9])*+)\z/
    FLOAT   = /\A[+-]?(?:0|[1-9](?:_?[0-9])*+)(?:\.[0-9](?:_?[0-9])*+(?:[eE][+-]?[0-9](?:_?[0-9])*+)?|[eE][+-]?[0-9](?:_?[0-9])*+)\z/
    BASES   = {
      16 => /\A0x[0-9a-fA-F](?:_?[0-9a-fA-F])*+\z/,
       8 => /\A0o[0-7](?:_?[0-7])*+\z/,
       2 => /\A0b[01](?:_?[01])*+\z/,
    }
    DATE = /\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/
    TIME = /\A([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.([0-9]++))?)?([Zz]|[+-][0-9]{2}:[0-9]{2})?\z/

    private def scalar : Value
      start = @pos
      scan_atom
      width = @pos - start
      date = width >= 10 && @bytes[start + 7] == '-'.ord && @bytes[start + 4] == '-'.ord
      if date && width == 10 && peek == ' ' && peek(3) == ':'
        advance
        scan_atom
      end
      token = span(start)
      case token
      when "true"                then true
      when "false"               then false
      when "inf", "+inf"         then Float64::INFINITY
      when "-inf"                then -Float64::INFINITY
      when "nan", "+nan", "-nan" then Float64::NAN
      else
        if date
          temporal_date(token, start)
        elsif token.includes?(':')
          time, offset = temporal_time(token, start)
          fail_at("local time cannot have an offset", start) if offset
          time
        elsif DECIMAL.matches?(token)
          token.to_i64?(underscore: true) || fail_at("integer outside Int64 range", start)
        elsif FLOAT.matches?(token)
          number = token.delete('_').to_f64?
          fail_at("float outside Float64 range", start) unless number && number.finite?
          number
        else
          BASES.each do |base, pattern|
            if pattern.matches?(token)
              return token.byte_slice(2).to_i64?(base, underscore: true) || fail_at("integer outside Int64 range", start)
            end
          end
          fail_at("expected a TOML scalar", start)
        end
      end
    end

    private def scan_atom
      until eof? || peek.in?(' ', '\t', '\r', '\n', '#', ',', ']', '}')
        fail_at("expected ASCII in a bare value") if @bytes[@pos] >= 0x80
        advance
      end
    end

    private def temporal_date(token, start)
      match = DATE.match(token.byte_slice(0, 10)) || fail_at("invalid date", start)
      year, month, day = match[1].to_i, match[2].to_i, match[3].to_i
      unless (1..12).includes?(month) && (1..Time.days_in_month(year, month)).includes?(day)
        fail_at("invalid calendar date", start)
      end
      date = LocalDate.new(year, month, day)
      return date if token.bytesize == 10
      fail_at("invalid date-time delimiter", start + 10) unless token.byte_at(10).chr.in?('T', 't', ' ')
      time, offset = temporal_time(token.byte_slice(11), start + 11)
      local = LocalDateTime.new(date, time)
      offset ? OffsetDateTime.new(local, offset) : local
    end

    private def temporal_time(token, start)
      match = TIME.match(token) || fail_at("invalid time", start)
      hour, minute = match[1].to_i, match[2].to_i
      second = match[3]?.try(&.to_i) || 0
      fail_at("time out of range", start) if hour > 23 || minute > 59 || second > 59
      fraction = match[4]?
      nanos = fraction ? fraction.byte_slice(0, Math.min(9, fraction.bytesize)).ljust(9, '0').to_i : 0
      offset = match[5]?
      if offset && offset.size > 1
        if offset.byte_slice(1, 2).to_i > 23 || offset.byte_slice(4, 2).to_i > 59
          fail_at("invalid UTC offset", start + token.bytesize - 6)
        end
      end
      {LocalTime.new(hour, minute, second, nanos), offset.try(&.upcase)}
    end
  end
end
