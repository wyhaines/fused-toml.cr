module FusedTOML
  # :nodoc:
  class Encoder
    include MappingPath

    @active = Set(UInt64).new

    def initialize(@max_depth : Int32)
    end

    def check_type(type : T.class, owner : C.class) forall T, C
      {% if T.union? && T != Value && T != Value? && T.union_types.reject { |t| t == Nil }.size > 1 %}
        {% if C < Hash %}
          {% raise "For mixed TOML values (#{T}), declare the hash literal 'of String => FusedTOML::Value'" %}
        {% elsif C < Array %}
          {% raise "For mixed TOML values (#{T}), declare the array literal 'of FusedTOML::Value'" %}
        {% else %}
          {% raise "Use a FusedTOML::Field converter for union #{T}" %}
        {% end %}
      {% end %}
    end

    def field(table : Table, key : String, depth, &)
      checked_at(key, depth) do
        EncodingChecks.validate(key)
        table[key] = yield
      end
    end

    # The named tuple carries the Crystal field name into compiler diagnostics.
    def convert(converter : C, field : F) : Value forall C, F
      {% if C.has_method?(:to_toml) %}
        result = converter.to_toml(field.values.first)
        checked_result(result, converter, field)
      {% else %}
        {% raise "#{C} must define to_toml(value) to write field #{F.keys.first}" %}
      {% end %}
    rescue ex
      raise EncodeError.new("converter failed: #{ex.message || ex.class.name}", ex, path: current_path)
    end

    private def checked_result(result : R, converter : C, field : F) : Value forall R, C, F
      {% unless R <= Value %}
        {% raise "#{C}.to_toml for field #{F.keys.first} must return FusedTOML::Value, got #{R}" %}
      {% end %}
      result
    end

    def encode(value : Serializable, depth, sections) : Table
      with_container(value) { value.__fused_toml_encode(self, depth, sections) }
    end

    def encode(value : Hash(K, V), depth, sections) : Table forall K, V
      {% unless K == String %}
        {% raise "TOML table keys must be String, got #{K}" %}
      {% end %}
      check_type(V, value.class)
      result = Table.new
      with_container(value) do
        value.each do |key, item|
          field(result, key, depth + 1) do
            EncodingChecks.reject_duplicate_key(key) if value.compare_by_identity? && result.has_key?(key)
            encode(item, depth + 1, sections)
          end
        end
      end
      result
    end

    def encode(value : Array(E), depth, sections) : Array(Value) forall E
      check_type(E, value.class)
      with_container(value) do
        # Only arrays written as [[headers]] share their depth with each element.
        headers = sections && !value.empty? && value.all? { |v| v.is_a?(Hash) || v.is_a?(Serializable) }
        child_depth = headers ? depth : depth + 1
        result = [] of Value
        value.each_with_index do |item, index|
          result << checked_at(index, child_depth) { encode(item, child_depth, headers) }
        end
        result
      end
    end

    def encode(value : Int::Primitive, depth, sections) : Int64
      unless Int64::MIN <= value <= Int64::MAX
        raise EncodeError.new("integer #{value} is outside Int64 range")
      end
      value.to_i64
    end

    def encode(value : Float32 | Float64, depth, sections) : Float64
      value.to_f64
    end

    def encode(value : Bool, depth, sections) : Bool
      value
    end

    def encode(value : String | LocalDate | LocalTime | LocalDateTime | OffsetDateTime, depth, sections)
      EncodingChecks.validate(value)
      value
    end

    def encode(value : Nil, depth, sections) : NoReturn
      raise EncodeError.new("TOML collections cannot contain nil")
    end

    private def checked_at(segment, depth, &)
      at(segment) do
        begin
          raise EncodeError.new("maximum depth exceeded") if depth > @max_depth
          yield
        rescue ex : EncodeError
          raise ex if ex.path
          raise EncodeError.new(ex.message, ex.cause, path: current_path)
        end
      end
    end

    private def with_container(value, &)
      if value.is_a?(Reference)
        id = value.object_id
        raise EncodeError.new("cyclic reference") unless @active.add?(id)
        begin
          yield
        ensure
          @active.delete(id)
        end
      else
        yield
      end
    end
  end
end
