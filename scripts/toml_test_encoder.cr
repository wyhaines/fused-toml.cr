require "json"
require "../src/fused_toml"

private def table(fields) : FusedTOML::Table
  result = FusedTOML::Table.new
  fields.each { |key, item| result[key] = decode(item) }
  result
end

private def decode(node : JSON::Any) : FusedTOML::Value
  if items = node.as_a?
    return items.map { |item| decode(item) }
  end
  fields = node.as_h
  type = fields["type"]?.try(&.as_s?)
  return table(fields) unless type
  text = fields["value"].as_s
  case type
  when "string"  then text
  when "integer" then text.to_i64
  when "float"
    case text
    when "inf", "+inf"         then Float64::INFINITY
    when "-inf"                then -Float64::INFINITY
    when "nan", "+nan", "-nan" then Float64::NAN
    else                            text.to_f64
    end
  when "bool"
    case text
    when "true"  then true
    when "false" then false
    else              raise "unexpected boolean #{text.inspect}"
    end
    # Temporal tags carry TOML/RFC 3339 literals. Delegate their conversion to
    # the reader, then enforce the kind supplied by the fixture.
  when "date-local"     then temporal(text).as(FusedTOML::LocalDate)
  when "time-local"     then temporal(text).as(FusedTOML::LocalTime)
  when "datetime-local" then temporal(text).as(FusedTOML::LocalDateTime)
  when "datetime"       then temporal(text).as(FusedTOML::OffsetDateTime)
  else                       raise "unexpected scalar tag #{type.inspect}"
  end
end

private def temporal(text)
  FusedTOML.load("v = #{text}")["v"]
end

FusedTOML.dump(table(JSON.parse(STDIN).as_h), STDOUT)
