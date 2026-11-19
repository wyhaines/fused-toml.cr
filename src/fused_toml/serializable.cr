module FusedTOML
  # Overrides the TOML key or supplies a converter with a from_toml(value) method.
  annotation Field
  end

  # Maps a resolved TOML table to the instance variables of a class or struct.
  module Serializable
    # Reject additional keys in the table mapped to this type.
    module Strict
    end

    macro included
      # :nodoc:
      def initialize(*, __fused_toml_table table : ::FusedTOML::Table, __fused_toml_decoder decoder : ::FusedTOML::Decoder)
        {% verbatim do %}
          {% begin %}
            {% keys = [] of StringLiteral %}
            {% for field in @type.instance_vars %}
              {% options = field.annotation(::FusedTOML::Field) %}
              {% key = (options && options[:key]) || field.name.stringify %}
              {% unless key.is_a?(StringLiteral) %}
                {% raise "FusedTOML::Field key must be a string literal on #{@type}##{field.name}" %}
              {% end %}
              {% if keys.includes?(key) %}
                {% raise "Duplicate TOML field #{key} on #{@type}" %}
              {% end %}
              {% keys << key %}

              if (%raw = table[{{key}}]?).nil?
                {% unless field.has_default_value? || field.type.nilable? %}
                  decoder.at({{key}}) { decoder.reject("missing required field") }
                {% end %}
              else
                @{{field.name}} = decoder.at({{key}}) do
                  {% if options && options[:converter] %}
                    decoder.convert { {{options[:converter]}}.from_toml(%raw) }
                  {% else %}
                    decoder.read(%raw, typeof(@{{field.name}}))
                  {% end %}
                end
              end
            {% end %}

            {% if @type < ::FusedTOML::Serializable::Strict %}
              table.each_key do |key|
                {% unless keys.empty? %}
                  case key
                  when {{keys.splat}} then next
                  end
                {% end %}
                decoder.at(key) { decoder.reject("unknown field") }
              end
            {% end %}
          {% end %}
        {% end %}
      end
    end
  end
end
