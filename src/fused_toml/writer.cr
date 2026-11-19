module FusedTOML
  # Raised when a Crystal value cannot be represented in the output document.
  class EncodeError < Exception
    getter path : String?

    def initialize(message : String? = nil, cause : Exception? = nil, *, @path : String? = nil)
      super(path ? "#{path}: #{message}" : message, cause)
    end
  end

  private module EncodingChecks
    def self.validate(string : String)
      raise EncodeError.new("invalid UTF-8 string") unless string.valid_encoding?
    end

    def self.validate(date : LocalDate)
      unless (0..9999).includes?(date.year) && (1..12).includes?(date.month) &&
             (1..Time.days_in_month(date.year, date.month)).includes?(date.day)
        raise EncodeError.new("invalid calendar date")
      end
    end

    def self.validate(time : LocalTime)
      unless (0..23).includes?(time.hour) && (0..59).includes?(time.minute) &&
             (0..59).includes?(time.second) && (0..999_999_999).includes?(time.nanosecond)
        raise EncodeError.new("invalid local time")
      end
    end

    def self.validate(value : LocalDateTime)
      validate(value.date)
      validate(value.time)
    end

    def self.validate(value : OffsetDateTime)
      validate(value.local)
      check_offset(value.offset)
    end

    def self.check_offset(offset)
      unless offset.valid_encoding? && /\A(?:[Zz]|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])\z/.matches?(offset)
        raise EncodeError.new("invalid UTC offset")
      end
    end
  end

  private class Writer
    @path = [] of String
    @started = false

    def initialize(@io : IO, @max_depth : Int32)
    end

    def write(table : Table) : Nil
      if table.empty?
        @io << "# Empty document\n"
      else
        write_body(table)
      end
    end

    private def write_body(table : Table) : Nil
      sections, assignments = table.keys.sort!.partition do |key|
        value = table[key]
        value.is_a?(Hash) || array_of_tables?(value)
      end

      depth = @path.size + 1
      assignments.each do |key|
        check_depth(depth)
        write_key(key)
        @io << " = "
        write_inline(table[key], depth)
        @io << '\n'
        @started = true
      end
      sections.each do |key|
        check_depth(depth)
        @path << key
        case section = table[key]
        when Hash
          write_header(array: false)
          write_body(section)
        when Array
          section.each do |element|
            write_header(array: true)
            write_body(element.as(Table))
          end
        end
        @path.pop
      end
    end

    private def array_of_tables?(value)
      value.is_a?(Array) && !value.empty? && value.all?(&.is_a?(Hash))
    end

    private def write_header(*, array : Bool)
      @io << '\n' if @started
      @io << (array ? "[[" : "[")
      @path.join(@io, '.') { |key| write_key(key) }
      @io << (array ? "]]\n" : "]\n")
      @started = true
    end

    private def write_inline(value : Value, depth : Int32) : Nil
      check_depth(depth)
      case value
      when Hash
        @io << '{'
        value.keys.sort!.join(@io, ", ") do |key|
          write_key(key)
          @io << " = "
          write_inline(value[key], depth + 1)
        end
        @io << '}'
      when Array
        @io << '['
        value.join(@io, ", ") { |item| write_inline(item, depth + 1) }
        @io << ']'
      when String
        write_string(value)
      when Float64
        case
        when value.nan?            then @io << "nan"
        when value.infinite? == 1  then @io << "inf"
        when value.infinite? == -1 then @io << "-inf"
        else                            @io << value
        end
      when Int64, Bool
        @io << value
      when LocalDate
        write_date(value)
      when LocalTime
        write_time(value)
      when LocalDateTime
        write_date_time(value)
      when OffsetDateTime
        offset = value.offset == "z" ? "Z" : value.offset
        EncodingChecks.check_offset(offset)
        write_date_time(value.local)
        @io << offset
      end
    end

    private def check_depth(depth)
      raise EncodeError.new("maximum depth exceeded") if depth > @max_depth
    end

    private def write_key(key)
      if !key.empty? && key.each_byte.all? { |byte| byte.chr.ascii_alphanumeric? || byte.chr.in?('-', '_') }
        @io << key
      else
        write_string(key)
      end
    end

    private def write_string(string)
      EncodingChecks.validate(string)
      @io << '"'
      start = 0
      string.to_slice.each_with_index do |byte, index|
        escape = case byte
                 when 0x22       then "\\\""
                 when 0x5c       then "\\\\"
                 when 0x08       then "\\b"
                 when 0x09       then "\\t"
                 when 0x0a       then "\\n"
                 when 0x0c       then "\\f"
                 when 0x0d       then "\\r"
                 when 0..31, 127 then "\\u%04X" % byte
                 else                 next
                 end
        @io.write(string.to_slice[start, index - start])
        @io << escape
        start = index + 1
      end
      @io.write(string.to_slice[start..])
      @io << '"'
    end

    private def write_date_time(value)
      write_date(value.date)
      @io << 'T'
      write_time(value.time)
    end

    private def write_date(date)
      EncodingChecks.validate(date)
      @io.printf("%04d-%02d-%02d", date.year, date.month, date.day)
    end

    private def write_time(time)
      EncodingChecks.validate(time)
      @io.printf("%02d:%02d:%02d", time.hour, time.minute, time.second)
      unless time.nanosecond.zero?
        @io << (".%09d" % time.nanosecond).rstrip('0')
      end
    end
  end
end
