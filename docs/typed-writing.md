# Typed TOML writing

**Status** — implemented in `a184366`. The [typed writer specs](../spec/typed_writing_spec.cr) exercise the public API. The [consumer checks](../scripts/check_typed_writing.py) cover converter compatibility and compiler diagnostics. Both supported compilers passed the [release verification](release.md#typed-writer-verification).

A caller who loads a configuration, edits a field, and writes the configuration should be able to use the same Crystal model throughout. Generate a conversion from the model to a `FusedTOML::Table`, then pass that table to the existing writer. This costs one intermediate tree and gives both APIs the same escaping, key order, section layout, and temporal formatting. [Field mapping](../src/fused_toml/serializable.cr) · [Semantic writer](../src/fused_toml/writer.cr)

## Public contract

| Call | Result |
| --- | --- |
| `config.to_toml` or `FusedTOML.dump(config)` | A deterministic TOML String |
| `config.to_toml(io)` or `FusedTOML.dump(config, io)` | Writes at the current position, leaves the IO open, and returns Nil |
| `FusedTOML.dump(servers)` or `FusedTOML.dump(servers, io)` for `Hash(String, Server)` | Encodes the same root shape as the typed-loading example in the README |

Generate the instance methods on classes and structs that include `FusedTOML::Serializable`. All entry points take the existing `max_depth:` keyword, default 128 and valid range 1–256. The existing `dump(Table)` overload keeps its direct route to the writer.

| Input | Mapping |
| --- | --- |
| Model fields | Use the external name from `@[FusedTOML::Field(key: ...)]` or the instance variable name. A dot in an annotated name belongs to that one key. Emit present values including false, zero, empty collections and values equal to their defaults. |
| Nilable model field | Omit a nil field. Reloading an omitted field applies its Crystal default. For example, setting `description : String? = "default"` to nil and reloading yields `"default"`. |
| Arrays and string-keyed hashes | Recurse into values and preserve array order. Reject nil elements and nil hash entries at their exact paths, since dropping either changes the collection. |
| Scalars and native TOML values | Range-check signed and unsigned integers before converting to Int64. Widen Float32 to Float64. Preserve strings, booleans, native subtrees and all four temporal kinds under the existing writer rules. |
| Converted field | For a present field, call `converter.to_toml(value)` once. It returns a value representable as `FusedTOML::Value`. Omission happens before conversion. Use a converter for application types and unions with multiple non-nil alternatives, consistent with typed loading. |

## Implementation sequence

1. **Establish the public test first.** Add `spec/typed_writing_spec.cr` around a model with a nested endpoint array, a literal key named `"bind.port"`, and a duration converter. Load the model, edit its port, and specify the expected native table independently. Use it as the reference for all four model entry points.
2. **Generate the write mapping.** Reuse the loader's field-name and duplicate-key rules. Generate the write method lazily so existing load-only models and converters still compile. Require the reverse converter only when writing that model. A missing hook or incompatible return type should identify the field and converter at compile time. [Typed loader](../src/fused_toml/decoder.cr)
3. **Bound model traversal before materializing the tree.** Track the external keys and indices for diagnostics. Detect reference cycles on the active path while allowing sibling fields to share a child. Match the writer's depth accounting for sections, arrays of tables and inline collections. An index always belongs in an error path, even when a `[[section]]` element uses the section's depth.
4. **Route model and typed-hash overloads through the writer.** Mapping failures raise `FusedTOML::EncodeError` with a path such as `$.endpoints[1]["bind.port"]`. Preserve the cause of converter exceptions. Complete model conversion before writing to the supplied IO. Once output begins, retain the existing writer contract for a partially written prefix and propagated IO errors. [Public facade](../src/fused_toml.cr)
5. **Document the API with an executable example.** Extend the README's typed configuration example to load, edit, dump, and reload. Show a two-way converter and the nil/default caveat. Record the release checks against the implementation commit.

## Validation and completion

| Test | Pass condition |
| --- | --- |
| Public round trip | All four model entry points produce the same bytes as `dump(expected_table)`. Reloading produces the edited port and duration. Repeat with a root `Hash(String, Server)` and assert field values individually. |
| Fields and collections | Test nested classes and structs, empty models and collections, renamed keys, raw TOML values, and different hash insertion orders. Verify false/default emission, nil-field omission, and path-specific rejection of nil in an array or hash. |
| Numeric and temporal boundaries | Test Int64 extrema and the adjacent out-of-range Int128/UInt64 values. Verify Float32 round trips, signed zero, infinities and NaN by sign or classification as appropriate. Exercise all four temporal types, including fractional seconds and a signed offset. |
| Converters and compilation | Run a load-only consumer with a read-only converter. Run `crystal build --no-codegen` on a separate consumer that writes that model. Require a nonzero exit and a diagnostic naming the field and missing reverse hook. Cover duplicate wire names on a write-only call, an unsupported return type, and a throwing converter with its cause and external path. |
| Depth, cycles and IO | Compare typed and native output at the same depth boundary, including an array of tables and a mixed inline array. Reject a self-cycle and accept a shared child. Verify a mapping error leaves an existing IO prefix intact, successful writes leave the stream open, and a write failure propagates. |

Run `crystal spec spec/typed_writing_spec.cr --error-on-warnings` during development. Include the compile-success and expected-compile-failure fixtures in automated validation on the minimum and stable compilers. Run `sh scripts/check_release.sh` with toml-test v2.2.0 on Crystal 1.21.0 and 1.22.3. The typed specs establish the model-to-table contract; the existing 214 encoder cases and both 681-case decoder runs cover the underlying TOML implementation. Completion requires both layers to pass and the README example to execute on both compilers. [Release verification](release.md)
