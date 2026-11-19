# fused-toml.cr

A native Crystal reader and writer for TOML 1.1. Load a complete document from a String into a root table. Keys resolve directly into Crystal hashes and arrays, including dotted keys and arrays of tables.

```crystal
require "fused_toml"

config = FusedTOML.load("[server]\nport = 8080")
port = config["server"].as(FusedTOML::Table)["port"].as(Int64)
port # => 8080
```

During local development, a consuming shard can use a path dependency:

```yaml
dependencies:
  fused_toml:
    path: ../fused-toml.cr
```

## Reader contract

`FusedTOML::Value` includes String, Bool, Int64, Float64, Array(Value), Table, and four distinct temporal records. LocalDate, LocalTime and LocalDateTime contain calendar or clock fields. OffsetDateTime pairs a LocalDateTime with a UTC designator or signed offset. Fractional seconds are truncated to nanoseconds. The current reader accepts seconds 00 through 59. Integer overflow and out-of-range finite float literals raise a parse error. Document layout and comments are discarded after validation.

`FusedTOML.load(source, max_depth: 128)` counts each key segment and each descent into an array element. The root is at depth zero. Array-of-tables headers count their named segments. Allowed limits are 1 through 256. For invalid input, `FusedTOML::ParseError` exposes a zero-based byte offset and one-based line and Unicode column. Definition conflicts also identify the previous declaration.

## Loading typed configurations

```crystal
require "fused_toml"

struct Server
  include FusedTOML::Serializable
  include FusedTOML::Serializable::Strict

  @[FusedTOML::Field(key: "listen-port")]
  getter port : UInt16
  getter enabled : Bool = true
  getter hostname : String?
end

servers = FusedTOML.load("[edge]\nlisten-port = 443", Hash(String, Server))
servers["edge"].port # => 443_u16
```

`load(source, T, max_depth: 128)` parses and validates the entire document before constructing the model. Classes and structs map their instance variables by name. A field’s `key:` annotation is one literal key, including any dots it contains. Omitted fields keep their Crystal defaults. An omitted nilable field without a default receives `nil`. A present value must match the requested type, including when the field has a default.

Additional keys are ignored by default. Include `FusedTOML::Serializable::Strict` on each model that should reject them. Missing required fields, unexpected keys in strict models, type mismatches, and conversion failures raise `FusedTOML::DecodeError`. Its `path` identifies the field and array indices, for example `$.servers[1]["bind.port"]`. Malformed TOML still raises `FusedTOML::ParseError`.

Supported field types include strings, booleans, fixed-width integers, Float32 and Float64, the four TOML temporal types, nested models, `Array(T)`, and `Hash(String, T)`. Use `FusedTOML::Value` or `FusedTOML::Table` for dynamic sections. Integers must fit the destination type. Floating-point fields accept TOML floats, with rounding to Float32 when requested. Finite magnitudes above the Float32 range raise a mapping error.

Use a field converter for application types or unions with multiple non-nil alternatives. Its `from_toml` method receives the resolved value. A converter exception is available as the mapping error’s `cause`.

```crystal
module DurationInSeconds
  def self.from_toml(value : FusedTOML::Value) : Time::Span
    value.as(Int64).seconds
  end
end

struct Job
  include FusedTOML::Serializable

  @[FusedTOML::Field(converter: DurationInSeconds)]
  getter timeout : Time::Span
end

FusedTOML.load("timeout = 5", Job).timeout # => 5.seconds
```

## Writing TOML

```crystal
config = FusedTOML::Table.new
config["port"] = 8080_i64
config["enabled"] = true

FusedTOML.dump(config) # => "enabled = true\nport = 8080\n"
FusedTOML.dump(config, STDOUT)
```

The writer sorts keys lexically within each table. It writes assignments first, then child sections. A nonempty array containing only tables becomes a sequence of `[[headers]]` when it can be expressed as sections. Mixed arrays keep their order and use inline tables. An empty root produces the single comment `# Empty document`.

Both overloads accept the same `max_depth` as the reader. Encoding preserves float values including negative zero, normalizes NaNs to `nan`, and emits UTC designators as `Z`. Invalid UTF-8, unrepresentable temporal fields, and excessive depth raise `FusedTOML::EncodeError`. The IO overload writes directly to the caller’s stream and leaves it open. An encoding or IO error can leave a prefix written.

## Development

```sh
shards check
crystal tool format --check src spec scripts
crystal spec --order=random --error-on-warnings
crystal spec -Dfused_toml_force_scalar_string_scan --order=random --error-on-warnings
go install github.com/toml-lang/toml-test/v2/cmd/toml-test@v2.2.0
mkdir -p bin
crystal build scripts/toml_test_decoder.cr -o bin/toml-test-decoder
crystal build scripts/toml_test_encoder.cr -o bin/toml-test-encoder
"$(go env GOPATH)/bin/toml-test" test -toml 1.1 -decoder ./bin/toml-test-decoder -encoder ./bin/toml-test-encoder
```

The next milestone adds IO input and resource limits. See the [specification and milestones](docs/plan.md).

## License and provenance

MIT. The word-at-a-time ASCII scanner and its scalar fallback are adapted from Kirk Haines's [FusedJSON scanner](https://github.com/wyhaines/fused-json.cr/blob/e06ba59c5c5e402a20425731f4a0acabaa02e3db/src/fused_json/ascii_string_scanner.cr). The TOML version also detects DEL. The conformance runner is an external development tool.
