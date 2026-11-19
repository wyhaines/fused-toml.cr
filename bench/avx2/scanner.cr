require "../../src/fused_toml"

module FusedTOML
  private module ASCIIStringScanner
    {% if flag?(:x86_64) && !flag?(:fused_toml_force_scalar_string_scan) %}
      private def self.avx2_supported? : Bool
        max_leaf = 0_u32
        asm("cpuid" : "={eax}"(max_leaf) : "{eax}"(0_u32) : "ebx", "ecx", "edx")
        return false if max_leaf < 7

        features = 0_u32
        asm("cpuid" : "={ecx}"(features) : "{eax}"(1_u32) : "ebx", "eax", "edx")
        # CPUID.1:ECX bits 27 and 28 mean OSXSAVE and AVX.
        return false unless features.bits_set?(0x1800_0000_u32)

        state = 0_u32
        asm("xgetbv" : "={eax}"(state) : "{ecx}"(0_u32) : "edx")
        return false unless state.bits_set?(6_u32) # OS saves XMM and YMM state.

        asm("cpuid" : "={ebx}"(features) : "{eax}"(7_u32), "{ecx}"(0_u32) : "eax", "ecx", "edx")
        features.bit(5) == 1
      end

      private AVX2_AVAILABLE = avx2_supported?
      {% if flag?(:bench_avx2_long_prefix) %}
        private PREFIX_BYTES = 128
      {% else %}
        private PREFIX_BYTES = WORD_BYTES
      {% end %}

      def self.find_special(bytes : Bytes, start : Int32, finish : Int32, basic : Bool) : Int32
        if finish - start >= PREFIX_BYTES + 32 && AVX2_AVAILABLE
          quote = basic ? 0x22_u8 : 0x27_u8
          escape = basic ? 0x5c_u8 : quote
          {% if flag?(:bench_avx2_long_prefix) %}
            prefix_end = start + PREFIX_BYTES
            match = previous_def(bytes, start, prefix_end, basic)
            return match if match < prefix_end
          {% else %}
            # Most configuration strings end in the first word.
            word = load_word(bytes.to_unsafe + start)
            mask = special_mask(word, quote.to_u64 * ONES)
            mask |= zero_byte_mask(word ^ BACKSLASHES) if basic
            return start + (mask.trailing_zeros_count // 8).to_i32 unless mask.zero?
          {% end %}
          start = skip_blocks(bytes.to_unsafe, start + PREFIX_BYTES, finish, quote, escape)
        end
        previous_def(bytes, start, finish, basic)
      end

      @[TargetFeature("+avx2")]
      private def self.skip_blocks(data : UInt8*, index : Int32, finish : Int32, quote : UInt8, escape : UInt8) : Int32
        last_block = finish - 32
        while index <= last_block
          block = data + index
          found = 0_u8
          32.times do |offset|
            b = block[offset]
            special = (b < 0x20_u8) | (b == 0x7f_u8) | (b == quote) | (b == escape)
            found |= special ? 1_u8 : 0_u8
          end
          break unless found.zero?
          index &+= 32
        end
        index
      end
    {% end %}
  end
end
