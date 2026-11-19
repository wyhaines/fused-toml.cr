# fused-toml.cr

FusedTOML reads and writes TOML 1.1 in native Crystal. Load a document from a String or IO to get its root table. The reader resolves dotted keys and arrays of tables into Crystal hashes and arrays.

FusedTOML parsed a 2,048-package lockfile in **2.84 ms** on a Core i9-12900HK. Among seven parsers across Crystal, Ruby, Python, and Rust, it had the lowest median parse time on each of the four inputs. [Benchmark results and methodology](docs/cross-language-benchmark.md)

```crystal
require "fused_toml"

config = FusedTOML.load("[server]\nport = 8080")
port = config["server"].as(FusedTOML::Table)["port"].as(Int64)
port # => 8080
```

To use a local checkout from another shard, add a path dependency.

```yaml
dependencies:
  fused_toml:
    path: ../fused-toml.cr
```

## Reader contract

`FusedTOML::Value` includes String, Bool, Int64, Float64, Array(Value), Table, and four date and time records. LocalDate, LocalTime and LocalDateTime hold calendar or clock fields. OffsetDateTime adds a UTC designator or signed offset to a LocalDateTime. The reader truncates fractional seconds to nanoseconds and accepts seconds 00 through 59.

Integer overflow and out-of-range finite float literals raise a parse error. After validating the whole document, the reader discards its layout and comments.

`FusedTOML.load(source, max_depth: 128)` starts at depth zero for the root. Each key segment adds one level, including named segments in array-of-tables headers. Descending into an array element also adds one level. You can set the limit from 1 to 256.

On invalid input, `FusedTOML::ParseError` reports a zero-based byte offset and a one-based line and Unicode column. If two declarations conflict, the error also points to the earlier declaration.

## Reading from IO with limits

```crystal
require "fused_toml"

limits = FusedTOML::Limits.new(
  max_document_bytes: 1_048_576,
  max_token_bytes: 8192,
  max_tokens: 100_000,
)

File.open("settings.toml") do |file|
  ports = FusedTOML.load(file, Hash(String, UInt16), limits: limits)
  puts ports["http"]
end
```

Both `load(source)` and `load(source, T)` read raw UTF-8 bytes from the IO's current position and leave the stream open. A read can return fewer bytes than requested. The loader continues until a read returns zero bytes (EOF) and propagates any IO error.

The loader buffers the whole document before parsing. Set `max_document_bytes` to bound how much input it retains from an open stream. At the limit it requests one more byte to distinguish an exact fit from an oversized document.

The limits below are off by default. Each is inclusive and can be zero. Set the depth limit separately with `max_depth`.

| Limit | What counts |
| --- | --- |
| `max_document_bytes` | Every input byte, including a leading BOM, comments and whitespace. The reader checks the size before validating UTF-8 or TOML syntax. |
| `max_token_bytes` | All source bytes in a single key component, scalar, comment or punctuation token, including quotes, escape spellings and multiline continuations. A date-time scalar includes the space between its date and time, if present. A comment starts at the `#` and ends before the newline. |
| `max_tokens` | Each key component, scalar and comment counts once, as does each punctuation byte outside those tokens. Each bracket in `[[name]]` counts separately. Whitespace outside tokens and the initial BOM count as zero. |

If the input exceeds a limit, `FusedTOML::LimitError` reports the first byte or token over budget. It's a `ParseError` with two additional fields, `limit_name` and `maximum`. All locations are relative to the start of the document. If the byte limit falls inside a multibyte character, the column points to that character. For conflicting definitions, `previous_offset`, `previous_line`, and `previous_column` give the location of the earlier declaration.

## Loading typed configurations

```crystal
require "fused_toml"

struct Server
  include FusedTOML::Serializable
  include FusedTOML::Serializable::Strict

  @[FusedTOML::Field(key: "listen-port")]
  property port : UInt16
  getter enabled : Bool = true
  getter hostname : String?
end

servers = FusedTOML.load("[edge]\nlisten-port = 443", Hash(String, Server))
servers["edge"].port # => 443_u16
server = servers["edge"]
server.port = 8443_u16
servers["edge"] = server
updated = FusedTOML.dump(servers)
FusedTOML.load(updated, Hash(String, Server))["edge"].port # => 8443_u16
FusedTOML.load(server.to_toml, Server).port # => 8443_u16
```

`load(source, T, max_depth: 128)` parses and validates the whole document before constructing the model. The mixin maps TOML keys to class or struct instance variables by name. To use a different key, pass a string literal to the field's `key:` annotation. Any dots in that string belong to the key itself.

Subclasses inherit the mapping even if they define their own constructors. The mixin supplies an initializer for loading. If all the model's fields have defaults and you also want to call `Model.new`, declare an empty, zero-argument `initialize` method.

When a key is missing, the field keeps its Crystal default. A nilable field without a default gets `nil`. If the key is present, its value must match the field type even if the field has a default.

Models ignore unknown keys by default. Include `FusedTOML::Serializable::Strict` in each model that should reject them. A missing required field, an unknown key in a strict model, a type mismatch, or a failed conversion raises `FusedTOML::DecodeError`. Its `path` identifies the field and any array indices, as in `$.servers[1]["bind.port"]`. Malformed TOML raises `FusedTOML::ParseError` during parsing.

Fields can hold strings, booleans, fixed-width integers, Float32 or Float64, any of the four TOML temporal types, nested models, `Array(T)`, or `Hash(String, T)`. Use `FusedTOML::Value` or `FusedTOML::Table` for dynamic sections. Integers must fit the destination type. Floating-point fields accept TOML floats. For Float32 fields, the loader rounds values to the available precision. A finite magnitude outside the Float32 range raises a mapping error.

Use a field converter for application types and for unions with multiple non-nil alternatives. The loader passes the resolved value to `from_toml`. This method is enough if you only load the model. To write the model as well, implement `to_toml(field_value)` and return a `FusedTOML::Value` or one of its member types, such as Int64, String or FusedTOML::Table. If a converter raises an exception, the mapping error keeps it as its `cause`.

```crystal
module DurationInSeconds
  def self.from_toml(value : FusedTOML::Value) : Time::Span
    value.as(Int64).seconds
  end

  def self.to_toml(value : Time::Span) : Int64
    raise ArgumentError.new("expected whole seconds") unless value.nanoseconds.zero?
    value.to_i
  end
end

struct Job
  include FusedTOML::Serializable

  @[FusedTOML::Field(converter: DurationInSeconds)]
  getter timeout : Time::Span
end

job = FusedTOML.load("timeout = 5", Job)
job.timeout # => 5.seconds
job.to_toml # => "timeout = 5\n"
```

## Writing TOML

To write a Serializable model, call `to_toml` or `to_toml(io)`. You can also use `FusedTOML.dump(model)` and `FusedTOML.dump(model, io)` with a model or a typed hash with string keys. All four methods accept `max_depth:`. The typed writer maps the model to a native table and passes it to the semantic writer.

The writer uses the same field names as the loader. It writes false, zero, empty containers and non-nil values that equal their defaults. It skips nil fields before calling any converter. If you set a nilable field to nil and it has a non-nil default, loading the document again restores that default.

A nil array element or hash entry, a reference cycle, or an integer outside the Int64 range raises `FusedTOML::EncodeError`. Its `path` identifies the field or entry. The typed writer finishes mapping before it writes to the supplied IO.

```crystal
config = {"port" => 8080_i64, "enabled" => true} of String => FusedTOML::Value

FusedTOML.dump(config) # => "enabled = true\nport = 8080\n"
FusedTOML.dump(config, STDOUT)
```

Declare arrays of mixed TOML values with `of FusedTOML::Value`. In hashes that compare keys by object identity, strings with identical contents name the same TOML key. The writer raises `FusedTOML::EncodeError` if two entries have that key.

Within each table the writer sorts keys lexically and writes assignments before child sections. Where the document allows sections, a nonempty array of tables becomes a sequence of `[[headers]]`. Mixed arrays keep their order and use inline tables. An empty root produces the single comment `# Empty document`.

Both overloads accept the same `max_depth` as the reader. The writer preserves float values, including negative zero. It uses `nan` for all NaNs and `Z` for UTC designators. Invalid UTF-8, unrepresentable temporal fields, and excessive depth raise `FusedTOML::EncodeError`.

The IO overload writes UTF-8 bytes at the current position. It preserves the stream's text encoding setting and leaves the stream open for the caller. If encoding or IO fails after writing begins, the stream can contain part of the document.

## Development

```sh
shards check
crystal tool format --check src spec scripts bench
crystal spec --order=random --error-on-warnings
crystal spec -Dfused_toml_force_scalar_string_scan --order=random --error-on-warnings
go install github.com/toml-lang/toml-test/v2/cmd/toml-test@v2.2.0
mkdir -p bin
crystal build scripts/toml_test_decoder.cr -o bin/toml-test-decoder
crystal build scripts/toml_test_encoder.cr -o bin/toml-test-encoder
"$(go env GOPATH)/bin/toml-test" test -toml 1.1 -decoder ./bin/toml-test-decoder -encoder ./bin/toml-test-encoder
"$(go env GOPATH)/bin/toml-test" test -toml 1.1 -decoder "./bin/toml-test-decoder --io"
```

See the [original Aloli benchmark](docs/benchmarking.md), [release checks and limitations](docs/release.md), and [implementation plan](docs/plan.md).

## License and provenance

FusedTOML is licensed under the [Apache License, Version 2.0](LICENSE).

The word-at-a-time ASCII scanner and its scalar fallback come from Kirk Haines's [FusedJSON scanner](https://github.com/wyhaines/fused-json.cr/blob/e06ba59c5c5e402a20425731f4a0acabaa02e3db/src/fused_json/ascii_string_scanner.cr), adapted here to detect DEL as well. The short-read IO spec helper comes from [FusedJSON's streaming specs](https://github.com/wyhaines/fused-json.cr/blob/e06ba59c5c5e402a20425731f4a0acabaa02e3db/spec/support/chunked_io.cr). The [FusedJSON MIT license notice](licenses/FusedJSON-MIT.txt) applies to those portions. The conformance runner is an external development tool.
