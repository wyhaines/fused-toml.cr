# Benchmarking dynamic TOML loading

The comparison measures the time to materialize a root table from an in-memory String using `FusedTOML.load` and Aloli's `TOML.parse_to_hash`. Both are public APIs. Aloli v0.1.7 builds its formatting-preserving document, validates table semantics, and then builds the returned hash. This difference in work is part of the comparison. [Aloli implementation at the measured revision](https://github.com/aloli-crystal/toml/blob/3cd645c67b83ce5b055bb0ae041d68fc354c7281/src/toml.cr)

## Measured results

On a quiet, AC-powered Core i9-12900HK laptop, FusedTOML took 4.50–5.59 µs to load the three small configurations and 4.18 ms to load the 2,048-package lockfile. All four inputs passed the native-tree equivalence check.

| Fixture | Input bytes | Fused latency | Aloli latency | Paired speedup | Fused / Aloli MiB/s | Fused / Aloli managed KiB per parse |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Server | 169 | 4.50 µs | 22.93 µs | 5.03× | 35.8 / 7.0 | 4.77 / 29.69 |
| Manifest | 294 | 5.03 µs | 28.94 µs | 5.74× | 55.8 / 9.7 | 5.52 / 37.02 |
| Routes | 300 | 5.59 µs | 32.00 µs | 5.65× | 51.2 / 8.9 | 5.69 / 39.11 |
| Lockfile | 318,461 | 4.18 ms | 29.28 ms | 7.06× | 72.6 / 10.4 | 4,251.08 / 30,848.15 |

The run started on 2026-11-19 UTC with FusedTOML `dd17a55`, Aloli v0.1.7, Crystal 1.22.3 and LLVM 22.1.3 on Linux x86-64. Logical CPU 2 and sibling 3 both sampled 100% idle for three seconds before the campaign. Both implementations used CPU 2 with the host's existing powersave governor. One-minute system load at sample starts ranged from 0.29 to 0.94. All six pairs per fixture are included. [Raw observations, fixture hashes and build metadata](receipts/native-tree-1.22.3.json)

## Reproduce

Use Linux, Python 3.10 or later, Git, taskset and Crystal. Run from a clean FusedTOML checkout. The comparison shard is an external benchmark dependency.

```sh
git clone --branch v0.1.7 https://github.com/aloli-crystal/toml.git /tmp/aloli-toml
python3 bench/run.py verify --aloli /tmp/aloli-toml
python3 bench/run.py measure --aloli /tmp/aloli-toml --cpu 2 --output /tmp/toml-comparison.json
```

Choose an available logical CPU on an idle host and check its SMT sibling before measuring. Use AC power for a laptop. The runner checks the comparator commit and builds one binary containing both parsers with `--release --no-debug --threads 1`. The receipt records its SHA-256, source revisions, compiler and LLVM, kernel, CPU, governor, logical CPU and siblings. The verify command builds and checks equivalent native trees. Measurement is opt-in.

## Corpus and preflight

Three checked-in TOML 1.0 configs exercise a server, a build manifest with quoted keys, and a route list with escaped strings. The runner also generates a lockfile with 2,048 `[[package]]` entries. Each package has a name, version, deterministic SHA-256 checksum and dependency array. Generation and file reads occur outside the timed region. Temporal values are outside this corpus because the two dynamic APIs use different representations.

Before timing, the binary recursively compares every value from both parsers. It compares table key sets, element order, exact scalar types, and float bits. Any difference stops the run. The receipt records the byte count, SHA-256 and root entry count for every fixture.

## Sampling and interpretation

Each fixture gets six pairs of fresh processes. FusedTOML runs first in odd pairs and Aloli in even pairs. Both use the selected CPU and `GC_MARKERS=1 GC_NPROCS=1`. Crystal's `Benchmark::IPS` warms up for one second and measures for two seconds in calibrated batches. Each iteration retains the most recent complete tree in both implementations. The receipt includes each process's reciprocal mean rate in microseconds per document, input MiB/s, managed bytes per document, batch count, relative standard deviation and starting host load.

Report the median per parser and fixture. Speedup is the median of the six paired Aloli/FusedTOML latency ratios. Managed bytes measure GC allocation traffic. This experiment measures dynamic String loading only; typed loading, IO, writing, source-preserving edits, and peak process memory require their own workloads. Profile the relevant workload before changing a hot path.
