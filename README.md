# fused-toml.cr

A native Crystal reader for TOML 1.1. Load a complete document from a String into a root table. Keys resolve directly into Crystal hashes and arrays, including dotted keys and arrays of tables.

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

## Development

```sh
shards check
crystal tool format --check src spec scripts
crystal spec --order=random --error-on-warnings
crystal spec -Dfused_toml_force_scalar_string_scan --order=random --error-on-warnings
go install github.com/toml-lang/toml-test/v2/cmd/toml-test@v2.2.0
mkdir -p bin
crystal build scripts/toml_test_decoder.cr -o bin/toml-test-decoder
"$(go env GOPATH)/bin/toml-test" test -toml 1.1 -decoder ./bin/toml-test-decoder
```

The semantic writer, typed configuration API and IO reader are planned. See the [specification and milestones](docs/plan.md).

## License and provenance

MIT. The word-at-a-time ASCII scanner and its scalar fallback are adapted from Kirk Haines's [FusedJSON scanner](https://github.com/wyhaines/fused-json.cr/blob/e06ba59c5c5e402a20425731f4a0acabaa02e3db/src/fused_json/ascii_string_scanner.cr). The TOML version also detects DEL. The conformance runner is an external development tool.
