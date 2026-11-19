# FusedTOML implementation plan

## Contract

Target [TOML 1.1.0](https://toml.io/en/v1.1.0) in native Crystal. One input describes one root table. A successful load validates the entire document, including comments and trailing bytes. Preserve heterogeneous arrays, signed 64-bit integers, binary64 floats and the four TOML temporal types. The writer must reproduce these distinctions when its output is read. Keep comments and source-preserving edits outside the semantic reader/writer API.

Use a byte cursor over a String with a bounded recursive value reader. Build Crystal tables directly. Keep declaration history per table and decoded key while loading. A definition records where it occurred and whether a table was implicit, explicit, established by dotted assignment, an array of tables, or a completed value. Traverse the newest array element for a child header. Assignments inside inline tables get an independent scope. Cap container and dotted-key depth before descending. Errors expose the failing byte offset and human-readable line and column.

## Milestones and acceptance

1. **String reader.** Implement header resolution, assignments, arrays, all four string forms, numbers and temporal values. Exercise implicit parents, dotted/quoted collisions, sealed inline tables and array element scope in Crystal specs. Pin the versioned [toml-test runner](https://github.com/toml-lang/toml-test/releases/tag/v2.2.0), translate public output to its tagged JSON protocol, and pass its TOML 1.1 valid/invalid matrix. Compare ordinary and forced-scalar string scanning. Tagging belongs exclusively in the test adapter.
2. **Semantic writer.** Add deterministic `dump(table)` and `dump(table, io)`. Define a stable key order and escape controls, preserve negative zero, temporal precision and offset. Cover empty tables, nested arrays of tables and heterogeneous arrays. Gate on the official encoder matrix and reader/writer round trips through public APIs.
3. **Typed configurations.** Add a TOML-specific Serializable mixin and `load(source, T)` on resolved tables. Specify defaults, missing and unknown fields, renamed keys, nilable fields (TOML has no null), integer bounds and custom converters. Test nested structs, arrays, and full error paths.
4. **IO, limits and diagnostics.** Specify and test borrowed IO, short reads, EOF, IO errors, byte and token caps, and String/IO result and location parity. Add adversarial generated cases for long dotted paths, nested inline values and temporal fractions. Verify supported Crystal releases in CI.
5. **Performance and release.** Establish reproducible release builds, a corpus of small configs and a generated lockfile with repeated package tables. Compare equivalent materialized values against aloli-crystal/toml on the shared 1.0 subset. Record compiler, fixtures, latency, allocations and throughput. Profile before adding fast paths. Publish API examples, conformance receipts and limitations.

The String reader is the first deliverable. Advancing each later milestone requires the earlier public contracts and regression tests to keep passing.

## Implementation status

All five implementation milestones are complete for the local development release. Both dynamic and typed loaders accept a String or borrowed IO. The [IO and limits guide](../README.md#reading-from-io-with-limits) covers buffering, EOF, resource budgets and diagnostics. The [typed configuration guide](../README.md#loading-typed-configurations) describes field mapping.

The release checks cover 42 specs, five README examples, and the TOML 1.1 String decoder, IO decoder and encoder suites. The [release verification report](release.md) records compiler versions, build commands, conformance receipts and supported temporal precision.

The [benchmark report](benchmarking.md) compares equivalent native values on three small configurations and a generated lockfile. It includes all 48 observations, the fixture hashes and the commands for repeating the campaign on an idle host. The shard remains at `0.1.0-dev` pending a publication decision.
