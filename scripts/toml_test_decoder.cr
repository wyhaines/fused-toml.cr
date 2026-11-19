require "json"
require "../src/fused_toml"

private def tagged(json, type, value)
  json.object do
    json.field "type", type
    json.field "value", value
  end
end

private def date_string(date : FusedTOML::LocalDate)
  "%04d-%02d-%02d" % {date.year, date.month, date.day}
end

private def time_string(time : FusedTOML::LocalTime)
  text = "%02d:%02d:%02d" % {time.hour, time.minute, time.second}
  time.nanosecond.zero? ? text : text + (".%09d" % time.nanosecond).rstrip('0')
end

private def timestamp(value : FusedTOML::LocalDateTime)
  "#{date_string(value.date)}T#{time_string(value.time)}"
end

private def emit(json : JSON::Builder, value : FusedTOML::Value) : Nil
  case value
  when Hash
    json.object { value.each { |key, item| json.field(key) { emit(json, item) } } }
  when Array
    json.array { value.each { |item| emit(json, item) } }
  when String then tagged(json, "string", value)
  when Int64  then tagged(json, "integer", value.to_s)
  when Bool   then tagged(json, "bool", value.to_s)
  when Float64
    text = case
           when value.nan?            then "nan"
           when value.infinite? == 1  then "inf"
           when value.infinite? == -1 then "-inf"
           else                            value.to_s
           end
    tagged(json, "float", text)
  when FusedTOML::LocalDate      then tagged(json, "date-local", date_string(value))
  when FusedTOML::LocalTime      then tagged(json, "time-local", time_string(value))
  when FusedTOML::LocalDateTime  then tagged(json, "datetime-local", timestamp(value))
  when FusedTOML::OffsetDateTime then tagged(json, "datetime", timestamp(value.local) + value.offset)
  end
end

begin
  table = FusedTOML.load(STDIN.gets_to_end)
  JSON.build(STDOUT) { |json| emit(json, table) }
rescue ex : FusedTOML::ParseError
  STDERR.puts ex.message
  exit 1
end
