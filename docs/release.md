# Release verification

Run the following commands from the repository root with the Crystal compiler under test on PATH.

```sh
go install github.com/toml-lang/toml-test/v2/cmd/toml-test@v2.2.0
TOML_TEST="$(go env GOPATH)/bin/toml-test" sh scripts/check_release.sh
```

The check prints tool versions and the source revision, checks shard dependencies and formatting, runs the specs in release mode and with the scalar scanner, and compiles and runs the five Crystal examples in the README. It runs a load-only converter consumer and checks four expected compiler diagnostics for typed writing. It builds the encoder and decoder with `--release --no-debug --threads 1`, records their SHA-256 digests, and runs the TOML 1.1 encoder and both String and IO decoder suites. Build digests identify the local binaries; paths and system toolchains can affect them.

## Typed writer verification

Revision `a184366` adds the typed writing API. Its release checks cover the load/edit/dump/reload workflow, byte parity with the semantic writer, converter compatibility and path-specific mapping failures. The compiler fixtures run a consumer with a read-only converter and separately check diagnostics for a missing reverse hook, an unsupported return type, duplicate wire keys and an ambiguous union.

On Crystal 1.21.0 and 1.22.3, all 51 specs passed in both configurations. All five README examples and all five consumer checks passed. Each compiler passed 214 encoder cases and both sets of 214 valid and 467 invalid decoder cases. [Crystal 1.21.0 typed writing receipt](receipts/typed-writing-1.21.0.log) · [Crystal 1.22.3 typed writing receipt](receipts/typed-writing-1.22.3.log)

## Initial development release checks

The release check passed on Linux x86-64 at `27eab5b` with Crystal 1.21.0 (LLVM 20.1.8) and 1.22.3 (LLVM 22.1.3). The benchmarked revision `dd17a55` has identical parser and writer sources. The following counts apply to each compiler.

| Check | Passed |
| --- | ---: |
| Release specs | 42 |
| Forced-scalar specs | 42 |
| Runnable README examples | 5 |
| String decoder, valid / invalid TOML 1.1 cases | 214 / 467 |
| IO decoder, valid / invalid TOML 1.1 cases | 214 / 467 |
| Encoder, TOML 1.1 cases | 214 |

The logs include the commands, test results and release binary digests. [Crystal 1.21.0 receipt](receipts/release-1.21.0.log) · [Crystal 1.22.3 receipt](receipts/release-1.22.3.log)

Both release adapters were rebuilt on the same host and checkout with a fresh `CRYSTAL_CACHE_DIR` for each compiler. All four SHA-256 digests matched the original builds. [Independent rebuild digests](receipts/rebuild.log)

The release review also caught a numeric dispatch error. A sufficiently long float such as `1.0e-000001` was classified as a date. The reader now checks both date separators and has a regression for String and IO inputs.

## Supported values and limitations

- TOML integers fit in Int64. Dynamic floats use IEEE 754 binary64. Finite literals outside that range raise a parse error. The writer preserves negative zero and emits a single NaN spelling.
- Dates, local times, local date-times and offset date-times have distinct Crystal types. Fractions are truncated to nanoseconds. The 0.1 series supports seconds 00–59. RFC 3339 also defines leap-second timestamps with second 60 at an actual insertion. This release rejects those on input and output. Accepting one would require an explicit policy for validating offset and local forms. [TOML 1.1 time grammar](https://github.com/toml-lang/toml/blob/1.1.0/toml.abnf) · [RFC 3339 §5.7](https://www.rfc-editor.org/rfc/rfc3339#section-5.7)
- IO loading buffers a complete document. Set `max_document_bytes` to bound reads. Typed loading maps the resolved root table into the requested Crystal model. The writer emits deterministic TOML from a semantic table; source layout and comments are discarded during loading.

The [README](../README.md) contains runnable API examples. The [benchmark protocol](benchmarking.md) describes the separate native-tree comparison.
