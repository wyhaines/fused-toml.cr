# Typed TOML writing

Commit `a184366` added typed writing. The specs exercise the public API. Separate checks compile consumer code to test converter compatibility and compiler diagnostics. Both supported compilers passed release verification. [Typed writer specs](../spec/typed_writing_spec.cr) · [Consumer checks](../scripts/check_typed_writing.py) · [Release verification](release.md#typed-writer-verification)

You can load a configuration, edit a field and write the result using the same Crystal model. The generated code builds one intermediate `FusedTOML::Table` and passes it to the semantic writer. Both APIs therefore use the same escaping, key order, section layout and temporal formatting. [Field mapping](../src/fused_toml/serializable.cr) · [Semantic writer](../src/fused_toml/writer.cr)

## Public contract

| Call | Result |
| --- | --- |
| `config.to_toml` or `FusedTOML.dump(config)` | Returns a deterministic TOML String |
| `config.to_toml(io)` or `FusedTOML.dump(config, io)` | Writes at the current position, leaves the IO open, and returns Nil |
| `FusedTOML.dump(servers)` or `FusedTOML.dump(servers, io)` for `Hash(String, Server)` | Writes a root table with the same structure as the typed-loading example in the README |

Classes and structs that include `FusedTOML::Serializable` get the instance methods above. All entry points accept `max_depth:`, which defaults to 128 and allows values from 1 to 256. The `dump(Table)` overload writes the native table directly.

| Input | Mapping |
| --- | --- |
| Model fields | The writer uses the external name from `@[FusedTOML::Field(key: ...)]` or the instance variable name. A dot in an annotated name is part of the key. The writer includes false, zero, empty collections and other present values, even when they equal the field's default. |
| Nilable model field | The writer skips nil fields. The loader applies Crystal defaults to omitted fields. For example, if you set `description : String? = "default"` to nil, it becomes `"default"` when you reload. |
| Arrays and string-keyed hashes | The writer maps values recursively and keeps array order. Skipping a nil array element or hash entry would change the collection, so the writer reports the exact path of the nil value. |
| Scalars and native TOML values | The writer checks that signed and unsigned integers fit in Int64 before conversion. It widens Float32 to Float64 and preserves strings, booleans, native subtrees and all four temporal types under the usual writer rules. |
| Converted field | The writer skips nil before conversion. For each present field it calls `converter.to_toml(value)` once. The result must be representable as `FusedTOML::Value`. As with typed loading, use a converter for application types and unions with multiple non-nil alternatives. |

## Implementation sequence

1. Start with the public round-trip test in `spec/typed_writing_spec.cr`. The model has a nested endpoint array, a literal key named `"bind.port"`, and a duration converter. Load it, edit the port, and compare all four model entry points against an independently specified native table.
2. Generate the write method lazily, using the loader's rules for field names and duplicate keys. A load-only model or converter must still compile. Only writing the model requires a reverse hook. If that hook is missing or returns an incompatible type, the compiler diagnostic should name both the field and the converter. [Typed loader](../src/fused_toml/decoder.cr)
3. Enforce traversal limits before building the full tree. Track external keys and array indices for error messages. Detect cycles on the current path while allowing sibling fields to share a child. Use the writer's depth rules for sections, arrays of tables and inline collections. A `[[section]]` element has the same depth as its section, but an error in that element still needs its index.
4. Send models and typed hashes through the same writer. Finish mapping the model before writing to the supplied IO. Mapping failures raise `FusedTOML::EncodeError` with a path such as `$.endpoints[1]["bind.port"]`. Preserve the cause when a converter raises. Once writing starts, IO errors propagate and the stream may contain part of the document. [Public facade](../src/fused_toml.cr)
5. Give the README a runnable example that loads, edits, dumps and reloads a typed configuration. Show a two-way converter and explain what happens when a nil field has a default. Record release checks for the commit that implements typed writing.

## Validation and completion

| Test | Pass condition |
| --- | --- |
| Public round trip | All four model entry points produce the same bytes as `dump(expected_table)`. Reloading restores the edited port and the duration. Repeat with a root `Hash(String, Server)` and check each field's value. |
| Fields and collections | Cover nested classes and structs, empty models and collections, renamed keys, raw TOML values and different hash insertion orders. Check that the writer emits false and default values, skips nil fields, and reports the exact path of a nil array element or hash entry. |
| Numeric and temporal boundaries | Test both Int64 limits and the adjacent out-of-range Int128 and UInt64 values. Round-trip Float32 values. Check the sign or classification of signed zero, infinities and NaN as appropriate. Exercise all four temporal types, including fractional seconds and a signed offset. |
| Converters and compilation | Run a consumer that only loads the model and uses a read-only converter. Run `crystal build --no-codegen` on a separate consumer that writes the same model. It must exit with a nonzero status and name the field and missing reverse hook. Also cover duplicate wire names on a write-only call, a converter with an unsupported return type, and a converter exception with its cause and external field path. |
| Depth, cycles and IO | Compare typed and native output at the same depth limit for an array of tables and a mixed inline array. A self-cycle must fail and a shared child must succeed. On a mapping error, check that the IO still contains its original prefix. Successful writes leave the stream open, and write failures propagate. |

During development, run `crystal spec spec/typed_writing_spec.cr --error-on-warnings` to check how models map to tables. Automated checks on the minimum and stable compilers must include the fixtures that compile successfully and those that should fail.

Run `sh scripts/check_release.sh` with toml-test v2.2.0 on Crystal 1.21.0 and 1.22.3. The underlying TOML implementation has 214 encoder cases and two decoder runs of 681 cases each. On both compilers, the typed checks and conformance suites must pass and the README example must run successfully. [Release verification](release.md)
