require "benchmark"
require "json"
require "toml"
require "../src/fused_toml"

# Compare native trees recursively. The shared corpus uses scalar kinds that
# both dynamic APIs represent identically, including the bits of each float.
private def equivalent?(left : FusedTOML::Value, right : TOML::Type) : Bool
  case left
  when Hash
    right.is_a?(Hash) && left.size == right.size &&
      left.all? { |key, item| right.has_key?(key) && equivalent?(item, right[key]) }
  when Array
    right.is_a?(Array) && left.size == right.size &&
      left.each_with_index.all? { |item, index| equivalent?(item, right[index]) }
  when Int64   then right.is_a?(Int64) && left == right
  when Float64 then right.is_a?(Float64) && left.unsafe_as(UInt64) == right.unsafe_as(UInt64)
  when String  then right.is_a?(String) && left == right
  when Bool    then right.is_a?(Bool) && left == right
  else              false
  end
end

private def measure(source, parse : Proc(T)) forall T
  job = Benchmark::IPS::Job.new(calculation: 2.seconds, warmup: 1.second, interactive: false)
  last = nil.as(T?)
  entry = job.report("parse") { last = parse.call }
  job.execute
  puts({
    latency_us:       1_000_000 / entry.mean,
    mib_per_second:   source.bytesize * entry.mean / (1024 * 1024),
    managed_bytes_op: entry.bytes_per_op,
    batches:          entry.size,
    rsd_percent:      entry.relative_stddev,
    root_entries:     last.not_nil!.size,
  }.to_json)
end

abort "usage: parse verify|fused|aloli FILE" unless ARGV.size == 2
mode, path = ARGV
source = File.read(path)
case mode
when "verify"
  fused = FusedTOML.load(source)
  aloli = TOML.parse_to_hash(source)
  abort "materialized trees differ for #{path}" unless equivalent?(fused, aloli)
  puts({root_entries: fused.size}.to_json)
when "fused" then measure(source, -> { FusedTOML.load(source) })
when "aloli" then measure(source, -> { TOML.parse_to_hash(source) })
else              abort "unknown mode #{mode.inspect}"
end
