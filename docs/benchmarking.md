# Benchmarking dynamic TOML loading

The comparison measures the time to materialize a root table from an in-memory String using `FusedTOML.load` and Aloli's `TOML.parse_to_hash`. Both are public APIs. Aloli v0.1.7 builds its formatting-preserving document, validates table semantics, and then builds the returned hash. This difference in work is part of the comparison. [Aloli implementation at the measured revision](https://github.com/aloli-crystal/toml/blob/3cd645c67b83ce5b055bb0ae041d68fc354c7281/src/toml.cr)

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
