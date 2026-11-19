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

Milestones 1 through 3 are complete. The typed loader maps resolved tables into Crystal classes, structs and typed collections. Its field, numeric and error-path contracts are documented in the [typed configuration guide](../README.md#loading-typed-configurations).

On Linux x86-64, all 28 project specs pass with both the default and forced-scalar scanners on Crystal 1.21.0 and 1.22.3. On each compiler the default build passes toml-test v2.2.0 for TOML 1.1 (214 valid decoder, 467 invalid decoder and 214 encoder cases). The writer milestone also verified equivalent native values and stable output across read/write/read cycles for all 214 valid fixtures.

Milestone 4 adds IO input, resource limits and diagnostics. Before release, revisit the 00–59 second range for leap-second inputs.
