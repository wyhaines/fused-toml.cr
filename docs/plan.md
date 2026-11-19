# FusedTOML implementation plan

## Contract

Implement [TOML 1.1.0](https://toml.io/en/v1.1.0) in native Crystal. Each input describes one root table. Validate the entire document, including comments and trailing bytes, before returning the table. Loading the writer's output must preserve heterogeneous arrays, signed 64-bit integers, binary64 floats and all four TOML temporal types. Comment retention and edits that preserve source formatting are outside the scope of the semantic reader and writer.

Read bytes from a String with a cursor and build Crystal tables directly. The recursive value reader must check the depth limit before descending into a container or following a dotted key.

For each table, track the location and kind of every decoded key's declaration. Distinguish implicit tables, explicit tables, tables created by dotted assignment, arrays of tables, and completed values. Resolve a child header against the most recent array element. Give assignments inside each inline table their own scope. When parsing fails, report the byte offset, line and column.

## Milestones and acceptance

1. Start with the String reader. Resolve headers and assignments, parse arrays and all four string forms, and read numbers and temporal values. Test implicit parent tables, collisions between dotted and quoted keys, sealed inline tables, and the scope of array elements. Pin the [toml-test runner](https://github.com/toml-lang/toml-test/releases/tag/v2.2.0) and pass its valid and invalid TOML 1.1 cases. Only the test adapter should translate public values into the runner's tagged JSON. Compare ordinary and forced-scalar string scanning.
2. Implement deterministic output for `dump(table)` and `dump(table, io)`. Define a stable key order, escape control characters, and preserve negative zero, temporal precision and offsets. Test empty tables, nested arrays of tables and heterogeneous arrays. The writer must pass the official encoder suite and round-trip through the public reader and writer APIs.
3. Map resolved tables to typed configurations with a TOML-specific Serializable mixin and `load(source, T)`. Define how to handle defaults, missing and unknown fields, renamed keys, integer bounds and custom converters. Specify what happens to nilable fields, since TOML has no null. Test nested structs and arrays, including the full path reported on error.
4. Support borrowed IO and define what happens on short reads, EOF, IO errors, and byte or token limits. Check that String and IO inputs produce the same results and error locations. Generate stress cases for long dotted paths, nested inline values and temporal fractions. Run CI on the supported Crystal releases.
5. Make release builds reproducible. Benchmark small configurations and a generated lockfile with repeated package tables against aloli-crystal/toml. Use the shared TOML 1.0 subset and check that both parsers build equivalent values. Record the compiler, fixtures, latency, allocations and throughput. Profile before adding fast paths. Publish runnable API examples, conformance results and known limitations.

Each milestone after the String reader must preserve the earlier public contracts and pass their regression tests.

## Implementation status

All five milestones are complete for the local development release. The dynamic and typed loaders both accept a String or borrowed IO. For buffering, EOF, resource limits and error locations, see the [IO and limits guide](../README.md#reading-from-io-with-limits). The [typed configuration guide](../README.md#loading-typed-configurations) covers field mapping.

Release checks run the project specs, README examples, typed-writer compatibility checks, and TOML 1.1 suites for both decoders (String and IO) and the encoder. For compiler versions, build commands, conformance logs and supported temporal precision, see the [release verification report](release.md).

The benchmark compares equivalent native values on three small configurations and a generated lockfile. For all 48 observations, fixture hashes and commands for repeating the run on an idle host, see the [benchmark report](benchmarking.md).

The shard is at `0.1.0-dev` pending a decision on publication.

## Typed writing

Typed writing extends `FusedTOML::Serializable`. It also lets callers write a typed hash with string keys as the root table. For round-trip behavior, converter compatibility and validation, see the [typed writing contract](typed-writing.md).
