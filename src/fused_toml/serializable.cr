module FusedTOML
  # Overrides the wire key or supplies a converter with from_toml and/or to_toml.
  annotation Field
  end

  # Maps a TOML table to and from the instance variables of a class or struct.
  module Serializable
    # Reject additional keys in the table mapped to this type.
    module Strict
    end

    # Encodes this model as a complete TOML document.
    def to_toml(*, max_depth : Int32 = 128) : String
      FusedTOML.dump(self, max_depth: max_depth)
    end

    # Writes this model to a borrowed IO.
    def to_toml(io : IO, *, max_depth : Int32 = 128) : Nil
      FusedTOML.dump(self, io, max_depth: max_depth)
    end

    # Defer field discovery until Crystal specializes each generated method.
    # A load-only consumer therefore only instantiates the read converter.
    macro included
      {% for direction in [:read, :write] %}
        # :nodoc:
        {% if direction == :read %}
          def initialize(*, __fused_toml_table table : ::FusedTOML::Table, __fused_toml_decoder decoder : ::FusedTOML::Decoder)
        {% else %}
          def __fused_toml_encode(encoder : ::FusedTOML::Encoder, depth : Int32, sections : Bool) : ::FusedTOML::Table
        {% end %}
          {% verbatim do %}
            {% begin %}
              {% reading = @def.name == "initialize" %}
              {% unless reading %}
                table = ::FusedTOML::Table.new
              {% end %}
              {% keys = [] of StringLiteral %}
              {% for field in @type.instance_vars %}
                {% options = field.annotation(::FusedTOML::Field) %}
                {% key = (options && options[:key]) || field.name.stringify %}
                {% converter = options && options[:converter] %}
                {% unless key.is_a?(StringLiteral) %}
                  {% raise "FusedTOML::Field key must be a string literal on #{@type}##{field.name}" %}
                {% end %}
                {% if keys.includes?(key) %}
                  {% raise "Duplicate TOML field #{key} on #{@type}" %}
                {% end %}
                {% keys << key %}

                {% if reading %}
                  if (%raw = table[{{key}}]?).nil?
                    {% unless field.has_default_value? || field.type.nilable? %}
                      decoder.at({{key}}) { decoder.reject("missing required field") }
                    {% end %}
                  else
                    @{{field.name}} = decoder.at({{key}}) do
                      {% if converter %}
                        decoder.convert { {{converter}}.from_toml(%raw) }
                      {% else %}
                        decoder.read(%raw, typeof(@{{field.name}}))
                      {% end %}
                    end
                  end
                {% else %}
                  %value = @{{field.name}}
                  unless %value.nil?
                    encoder.field(table, {{key}}, depth + 1) do
                      {% if converter %}
                        %native = encoder.convert({{converter}}, { {{field.name}}: %value })
                        encoder.encode(%native, depth + 1, sections)
                      {% else %}
                        encoder.check_type(typeof(@{{field.name}}))
                        encoder.encode(%value, depth + 1, sections)
                      {% end %}
                    end
                  end
                {% end %}
              {% end %}

              {% if reading && @type < ::FusedTOML::Serializable::Strict %}
                table.each_key do |key|
                  {% unless keys.empty? %}
                    case key
                    when {{keys.splat}} then next
                    end
                  {% end %}
                  decoder.at(key) { decoder.reject("unknown field") }
                end
              {% end %}
              {% unless reading %}
                table
              {% end %}
            {% end %}
          {% end %}
        end
      {% end %}
    end
  end
end
