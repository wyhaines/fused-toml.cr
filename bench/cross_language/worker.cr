require "json"

{% if flag?(:bench_community) %}
  require "toml"

  private def parse(source)
    TOML.parse(source)
  end

  private def emit(json, value : TOML::Any) : Nil
    emit(json, value.raw)
  end
{% elsif flag?(:bench_aloli) %}
  require "toml"

  private def parse(source)
    TOML.parse_to_hash(source)
  end
{% else %}
  require "fused_toml"

  private def parse(source)
    FusedTOML.load(source)
  end
{% end %}

# The verification adapter handles the shared corpus's scalar types.
private def emit(json, value) : Nil
  case value
  when Hash
    json.object { value.each { |key, item| json.field(key) { emit(json, item) } } }
  when Array
    json.array { value.each { |item| emit(json, item) } }
  when Int64, Float64, String, Bool
    value.to_json(json)
  else
    raise "unexpected corpus value: #{value.class}"
  end
end

source = File.read(ARGV[1])
last = parse(source)
if ARGV[0] == "verify"
  puts JSON.build { |json| emit(json, last) }
else
  STDIN.each_line do |line|
    count = line.to_i
    start = Time.instant
    count.times { last = parse(source) }
    elapsed = Time.instant - start
    puts "#{elapsed.total_nanoseconds.to_i64} #{last.size}"
    STDOUT.flush
  end
end
