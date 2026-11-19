module FusedTOML
  # :nodoc:
  private module ASCIIStringScanner
    WORD_BYTES = 8

    private ONES        = 0x0101_0101_0101_0101_u64
    private HIGH_BITS   = 0x8080_8080_8080_8080_u64
    private CONTROLS    = 0x2020_2020_2020_2020_u64
    private BACKSLASHES = 0x5c5c_5c5c_5c5c_5c5c_u64

    # The source is already valid UTF-8. Only ASCII syntax and controls interrupt a span.
    def self.find_special(bytes : Bytes, start : Int32, finish : Int32, basic : Bool) : Int32
      index = start
      quote = basic ? 0x22_u8 : 0x27_u8
      {% unless flag?(:fused_toml_force_scalar_string_scan) %}
        quotes = quote.to_u64 * ONES
        while finish - index >= WORD_BYTES
          word = load_word(bytes.to_unsafe + index)
          mask = special_mask(word, quotes)
          mask |= zero_byte_mask(word ^ BACKSLASHES) if basic
          return index + (mask.trailing_zeros_count // 8).to_i32 unless mask == 0
          index += WORD_BYTES
        end
      {% end %}

      while index < finish
        byte = bytes[index]
        return index if byte == quote || (basic && byte == 0x5c_u8) || byte < 0x20_u8 || byte == 0x7f_u8
        index += 1
      end
      finish
    end

    @[AlwaysInline]
    private def self.load_word(pointer : UInt8*) : UInt64
      word = uninitialized UInt64
      pointerof(word).as(UInt8*).copy_from(pointer, WORD_BYTES)
      # Normalize memory order so trailing zeros identify the earliest byte.
      {% if IO::ByteFormat::SystemEndian == IO::ByteFormat::BigEndian %}
        word.byte_swap
      {% else %}
        word
      {% end %}
    end

    @[AlwaysInline]
    private def self.special_mask(word : UInt64, quotes : UInt64) : UInt64
      # The subtraction masks can also mark bytes after a true match because
      # of borrows. They cannot mark an earlier byte, so the first set byte is
      # always the first byte that needs full TOML handling.
      zero_byte_mask(word ^ 0x7f7f_7f7f_7f7f_7f7f_u64) |
        zero_byte_mask(word ^ quotes) |
        ((word &- CONTROLS) & ~word & HIGH_BITS)
    end

    @[AlwaysInline]
    private def self.zero_byte_mask(word : UInt64) : UInt64
      (word &- ONES) & ~word & HIGH_BITS
    end
  end
end
