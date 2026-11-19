# Release verification

## 1.0.0 release notes

FusedTOML 1.0.0 reads and writes TOML 1.1 in native Crystal. It supports Crystal 1.21.0 and later 1.x releases.

- Read a String or IO into a table with `FusedTOML.load`. Use `FusedTOML.dump` to write deterministic TOML to a String or IO.
- Include `FusedTOML::Serializable` in a class or struct to load it with `FusedTOML.load(source, Model)` and write it with `model.to_toml`. Models support nested types, field renaming, custom converters, and optional rejection of unknown keys.
- Set limits on document size, token size, token count, or nesting depth. Parse errors identify the line, column, and byte offset. Typed mapping errors identify the field or array element.

The reader buffers the full document when reading from IO and discards formatting and comments when parsing. The reader and writer accept seconds 00 through 59.

On Crystal 1.21.0 and 1.22.3, all 58 specs passed with the default eight-byte scanner and again with the scalar fallback. Both compilers passed the five README examples and nine typed-writer compatibility checks. On each compiler the TOML 1.1 encoder passed all 214 cases. The String and IO decoders each accepted all 214 valid inputs and rejected all 467 invalid inputs.

## Running the release checks

Put the Crystal compiler you want to test on PATH, then run these commands from the repository root.

```sh
go install github.com/toml-lang/toml-test/v2/cmd/toml-test@v2.2.0
TOML_TEST="$(go env GOPATH)/bin/toml-test" sh scripts/check_release.sh
```

The script prints the tool versions and source revision, then checks shard dependencies and formatting. It runs the specs in release mode and with the scalar scanner. The remaining API checks compile and run the five Crystal examples in the README, run a program that uses a read-only converter, and check compiler diagnostics for converters, wire keys, and mixed field and collection types.

The script builds the encoder and decoder with `--release --no-debug --threads 1`, records their SHA-256 digests, and runs the TOML 1.1 encoder suite and both decoder suites (String and IO). A digest identifies the binary from that build. Its value can depend on the build paths and system toolchain.

## Typed writer verification

Commit `a184366` added the typed writing API. Its checks loaded a model, edited it, dumped it and loaded it again. They compared the output byte for byte with the semantic writer and checked that mapping errors reported the failing path.

The suite ran a program with a read-only converter to check compatibility. Separate compiler fixtures checked the diagnostics for a missing reverse hook, an unsupported return type, duplicate wire keys and an ambiguous union.

Crystal 1.21.0 and 1.22.3 each passed all 51 specs in both configurations, all five README examples, and all five consumer checks. On each compiler the encoder passed 214 cases. The String and IO decoders each accepted 214 valid cases and rejected 467 invalid ones. [Crystal 1.21.0 results](receipts/typed-writing-1.21.0.log) · [Crystal 1.22.3 results](receipts/typed-writing-1.22.3.log)

## Initial development release checks

On Linux x86-64, revision `27eab5b` passed the release check with Crystal 1.21.0 (LLVM 20.1.8) and 1.22.3 (LLVM 22.1.3). The benchmark used revision `dd17a55`, which has the same parser and writer sources. The counts below are for each compiler.

| Check | Passed |
| --- | ---: |
| Release specs | 42 |
| Forced-scalar specs | 42 |
| Runnable README examples | 5 |
| String decoder, valid / invalid TOML 1.1 cases | 214 / 467 |
| IO decoder, valid / invalid TOML 1.1 cases | 214 / 467 |
| Encoder, TOML 1.1 cases | 214 |

The logs include the commands, test results and release binary digests. [Crystal 1.21.0 receipt](receipts/release-1.21.0.log) · [Crystal 1.22.3 receipt](receipts/release-1.22.3.log)

Rebuilding both release adapters on the same host and checkout, with a fresh `CRYSTAL_CACHE_DIR` for each compiler, reproduced all four original SHA-256 digests. [Independent rebuild digests](receipts/rebuild.log)

During release testing, the reader mistook long float literals such as `1.0e-000001` for dates. It now checks for both date separators. A regression test covers String and IO inputs.

## Supported values and limitations

- TOML integers must fit in Int64. The dynamic reader uses IEEE 754 binary64 for floats and raises a parse error for finite literals outside that range. The writer preserves negative zero and uses one spelling for NaN.
- FusedTOML uses distinct Crystal types for dates, local times, local date-times and offset date-times. The reader truncates fractional seconds to nanoseconds. RFC 3339 permits second 60 at an actual leap-second insertion. FusedTOML accepts seconds 00 through 59. Supporting leap seconds would require rules for validating both local times and times with an offset. [TOML 1.1 time grammar](https://github.com/toml-lang/toml/blob/1.1.0/toml.abnf) · [RFC 3339 §5.7](https://www.rfc-editor.org/rfc/rfc3339#section-5.7)
- The reader buffers the entire document when loading from IO. Set `max_document_bytes` to bound reads. Typed loading maps the resolved root table to the requested Crystal model. The reader discards source layout and comments. The writer produces deterministic TOML from the table.

For runnable API examples, see the [README](../README.md). For the separate comparison of native TOML trees, see the [benchmark protocol](benchmarking.md).
