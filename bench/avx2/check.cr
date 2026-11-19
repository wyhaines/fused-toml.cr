require "./scanner"

{% if flag?(:x86_64) && !flag?(:fused_toml_force_scalar_string_scan) %}
  module FusedTOML
    private module ASCIIStringScanner
      def self.check_byte_matches
        abort "This check requires AVX2" unless AVX2_AVAILABLE

        span = PREFIX_BYTES + 3 * 32 + 3
        bytes = Bytes.new(32 + span, 0x61_u8)
        checks = 0
        {true, false}.each do |basic|
          quote = basic ? 0x22_u8 : 0x27_u8
          32.times do |start|
            finish = start + span
            span.times do |offset|
              pos = start + offset
              256.times do |value|
                bytes[pos] = value.to_u8
                special = value == quote || (basic && value == 0x5c) || value < 0x20 || value == 0x7f
                expected = special ? pos : finish
                actual = find_special(bytes, start, finish, basic)
                unless actual == expected
                  raise "Byte #{value} at #{pos}, start #{start}, basic #{basic}: expected #{expected}, got #{actual}"
                end
                checks += 1
              end

              bytes[pos] = quote
              actual = find_special(bytes, start, pos, basic)
              raise "Scanned past limit #{pos} from #{start}" unless actual == pos
              bytes[pos] = 0x61_u8
              checks += 1
            end
          end
        end
        puts "#{checks} byte, alignment and token-limit checks passed"
      end
    end

    ASCIIStringScanner.check_byte_matches
  end
{% else %}
  abort "This check requires an x86-64 build with the AVX2 scanner"
{% end %}
