# TOML parsing across Crystal, Ruby, Python and Rust

Seven parsers, including FusedTOML `84de66a`, ran on a Dell XPS 15 9520 with a Core i9-12900HK. Each used its public API to parse UTF-8 text already in memory into its own dynamic table type. Before timing, all seven produced equivalent trees for each of the four inputs. [Raw timings, tool versions and verification hashes](receipts/dell-cross-language-84de66a.json)

## Results

Each cell gives the median time to parse one document across seven fresh processes. Times for the three small inputs are in microseconds. Lockfile times are in milliseconds.

| Implementation | Server · 169 B (µs) | Manifest · 294 B (µs) | Routes · 300 B (µs) | Lockfile · 318,461 B (ms) |
| --- | ---: | ---: | ---: | ---: |
| Crystal · FusedTOML `84de66a` | 3.89 | 4.20 | 4.66 | 2.84 |
| Crystal · crystal-community/toml.cr 0.8.1 | 31.86 | 53.64 | 34.34 | 34.57 |
| Crystal · Aloli 0.1.7 | 23.04 | 28.90 | 32.27 | 25.85 |
| Ruby · toml-rb 6.0.0 | 41.62 | 52.68 | 58.93 | 34.83 |
| Ruby · Tomlib 0.7.3 (C extension) | 6.52 | 8.53 | 8.57 | 9.02 |
| Python · tomllib | 34.88 | 43.17 | 48.61 | 39.92 |
| Rust · toml 1.2.1 | 4.95 | 6.58 | 6.76 | 6.68 |

For the 2,048-package lockfile, Aloli took 9.10× as long as FusedTOML, crystal-community took 12.17× as long, and parsing into Rust's `toml::Table` took 2.30× as long. Each ratio is the median of seven comparisons, pairing the two parsers' times within each round.

![Paired parse-time ratios with the range across seven rounds](receipts/dell-cross-language-84de66a.png)

## Workload and APIs

The three small inputs are the server, build manifest and route configurations in the repository. The benchmark generator supplies the fourth input, a lockfile. Together these TOML 1.0 documents exercise tables, arrays of tables, strings, booleans, integers and floats. To check the results, the runner recursively serializes each complete tree to sorted, canonical JSON and compares the hashes. This check preserves array order and scalar types for these inputs and runs outside the timer. Dates, TOML 1.1-only syntax, typed deserialization and writing need their own workloads. [Fixtures](../bench/fixtures) · [Lockfile generator](../bench/run.py)

- Crystal 1.22.3 compiled a separate release binary for each parser with LLVM 22.1.3 and `--release --no-debug --threads 1`. The FusedTOML worker called `FusedTOML.load`. The community shard's `TOML.parse` returns a table of `TOML::Any` values. Aloli's `TOML.parse_to_hash` builds a document that preserves formatting before it returns a hash. All three workers ran with `GC_MARKERS=1` and `GC_NPROCS=1`. [Community API](https://github.com/crystal-community/toml.cr/blob/030a3866af395bfb9fe2cce234d9b3d0d8f3ad3c/src/toml.cr) · [Aloli API](https://github.com/aloli-crystal/toml/blob/3cd645c67b83ce5b055bb0ae041d68fc354c7281/src/toml.cr)
- Ruby 4.0.9 ran with YJIT off. Both the pure Ruby `TomlRB.parse` and the native C extension `Tomlib.load` returned Ruby hashes. [toml-rb](https://github.com/emancu/toml-rb) · [Tomlib](https://github.com/kgiszczak/tomlib)
- CPython 3.14.3 used `tomllib.loads` from the standard library. [Python 3.14 API](https://docs.python.org/3.14/library/tomllib.html)
- The Rust 1.95.0 worker called `str::parse::<toml::Table>()`. It used Cargo's release profile and the default features of `toml` 1.2.1+spec-1.1.0. [Rust API](https://docs.rs/toml/1.2.1/toml/type.Table.html) · [Cargo.lock](../bench/cross_language/rust/Cargo.lock)

## Sampling and host conditions

For each fixture, the runner started a fresh process for every parser in every round. It rotated the order so each parser ran in each of the seven positions once. Each worker read its input once and warmed up for at least 0.5 seconds. It then timed at least one second of parsing in calibrated batches, keeping each result until the next parse replaced it.

The timer covered parsing and replacing the previous tree. Process startup, file reads, verification, messages between processes and printing all fell outside that interval. The benchmark did not measure memory use across languages.

The Dell ran on AC power with its usual `powersave` governor. All workers ran on logical CPU 2, whose SMT sibling is CPU 3. Before each round the runner sampled the host for three seconds. Both siblings had to be at least 95% idle, excluding I/O wait. Across the host, at least 95% of CPU time had to be available (idle plus I/O wait), and NVMe busy time could be at most 10%. Two other CPUs reported I/O wait during the idle check.

During each timed sample the runner checked AC power, sibling idle time, CPU availability elsewhere on the host, and NVMe activity. The sibling was idle 99.4% to 100.0% of the time, and the disk was busy 0.0% to 0.3% of the time. All 196 samples passed on the first attempt.

## Reproduce

Use an AC-powered Linux host with NVMe and choose a CPU that has an SMT sibling. You'll need Git, Crystal, Cargo, Ruby with its development headers, and Python with `tomllib`. To repeat this comparison, use the toolchain versions listed above. The preparation script builds dependencies in the work directory you supply. In the commands below, use your host's CPU ID and paths to the Ruby and Python interpreters.

```sh
work=$(mktemp -d)
ruby=$(command -v ruby)
python=$(command -v python3.14)
rev=84de66a3d3e02158aa38c2468a37a14fddd0eeff
sh bench/cross_language/prepare.sh "$work" "$rev" "$ruby"
python3 "$work/cross_language/run.py" --work "$work" --cpu 2 \
  --ruby "$ruby" --python "$python" --fused-rev "$rev" --output "$work/result.json"
```
