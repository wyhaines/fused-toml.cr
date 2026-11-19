module FusedTOML
  # A valid TOML document could not be mapped to the requested Crystal type.
  class DecodeError < Exception
    # Rooted key path, including array indices and quoted non-bare keys.
    getter path : String

    def initialize(message : String, @path : String, cause : Exception? = nil)
      super("#{path}: #{message}", cause)
    end
  end

  # :nodoc:
  class Decoder
    include MappingPath

    def reject(message, cause = nil) : NoReturn
      raise DecodeError.new(message, current_path, cause)
    end

    private def mismatch(expected, value) : NoReturn
      actual = case value
               when Hash  then "table"
               when Array then "array"
               else            value.class.to_s
               end
      reject("expected #{expected}, got #{actual}")
    end

    def convert(&)
      yield
    rescue ex
      reject("converter failed: #{ex.message || ex.class.name}", ex)
    end

    def read(value : Value, type : T.class) : T forall T
      {% if T == Value || T == Value? %}
        value
      {% elsif T.union? %}
        {% members = T.union_types.reject { |member| member == Nil } %}
        {% if members.size == 1 && T.nilable? %}
          read_optional(value, type)
        {% else %}
          {% raise "Use a FusedTOML::Field converter for union #{T}" %}
        {% end %}
      {% elsif T < Serializable %}
        mismatch("table for #{T}", value) unless value.is_a?(Table)
        T.__fused_toml_decode(value, self)
      {% elsif T < Array %}
        read_array(value, type)
      {% elsif T < Hash %}
        read_table(value, type)
      {% elsif Int::Primitive.union_types.includes?(T) %}
        mismatch(T, value) unless value.is_a?(Int64)
        reject("integer #{value} is outside #{T} range") unless T::MIN <= value <= T::MAX
        T.new(value)
      {% elsif T == Float32 %}
        mismatch(T, value) unless value.is_a?(Float64)
        reject("float is outside Float32 range") if value.finite? && value.abs > Float32::MAX
        value.to_f32
      {% elsif [String, Bool, Float64, LocalDate, LocalTime, LocalDateTime, OffsetDateTime].includes?(T) %}
        value.is_a?(T) ? value : mismatch(T, value)
      {% else %}
        {% raise "Cannot decode #{T}. Include FusedTOML::Serializable or supply a FusedTOML::Field converter" %}
      {% end %}
    end

    private def read_array(value : Value, type : Array(E).class) : Array(E) forall E
      mismatch("array", value) unless value.is_a?(Array)
      {% if E == Value %}
        value
      {% else %}
        Array(E).new(value.size) { |index| at(index) { read(value[index], E) } }
      {% end %}
    end

    private def read_table(value : Value, type : Hash(K, E).class) : Hash(K, E) forall K, E
      {% unless K == String %}
        {% raise "TOML table keys must be String in #{K} => #{E}" %}
      {% end %}
      mismatch("table", value) unless value.is_a?(Table)
      {% if E == Value %}
        value
      {% else %}
        result = Hash(String, E).new(initial_capacity: value.size)
        value.each { |key, item| result[key] = at(key) { read(item, E) } }
        result
      {% end %}
    end

    private def read_optional(value, type : (E | Nil).class) forall E
      read(value, E)
    end
  end
end
