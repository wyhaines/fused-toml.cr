# Benchmarking dynamic TOML loading

The benchmark times two public APIs, `FusedTOML.load` and Aloli's `TOML.parse_to_hash`, as they build a root table from an in-memory String. Aloli v0.1.7 builds a document that preserves formatting and validates its table definitions before returning a hash. Its timings include that work. [Aloli implementation at the measured revision](https://github.com/aloli-crystal/toml/blob/3cd645c67b83ce5b055bb0ae041d68fc354c7281/src/toml.cr)

A later run used the same four fixtures to compare FusedTOML at `84de66a` with both other released Crystal parsers and parsers for Ruby, Python, and Rust. [Dell cross-language benchmark](cross-language-benchmark.md)

## Measured results

On a quiet Core i9-12900HK laptop running on AC power, FusedTOML loaded the three small configurations in 4.50 to 5.59 µs and the 2,048-package lockfile in 4.18 ms. Both parsers produced equivalent trees for every input.

| Fixture | Input bytes | Fused latency | Aloli latency | Paired speedup | Fused / Aloli MiB/s | Fused / Aloli managed KiB per parse |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Server | 169 | 4.50 µs | 22.93 µs | 5.03× | 35.8 / 7.0 | 4.77 / 29.69 |
| Manifest | 294 | 5.03 µs | 28.94 µs | 5.74× | 55.8 / 9.7 | 5.52 / 37.02 |
| Routes | 300 | 5.59 µs | 32.00 µs | 5.65× | 51.2 / 8.9 | 5.69 / 39.11 |
| Lockfile | 318,461 | 4.18 ms | 29.28 ms | 7.06× | 72.6 / 10.4 | 4,251.08 / 30,848.15 |

The run started on 2026-11-19 UTC. It used FusedTOML `dd17a55`, Aloli v0.1.7, Crystal 1.22.3 and LLVM 22.1.3 on Linux x86-64. Logical CPU 2 and its sibling, CPU 3, were both 100% idle during the three-second check before timing. Both parsers ran on CPU 2 with the host's powersave governor. The one-minute system load ranged from 0.29 to 0.94 at the start of samples. The results include all six pairs for each fixture. [Raw observations, fixture hashes and build metadata](receipts/native-tree-1.22.3.json)

## Reproduce

Start with a clean FusedTOML checkout on Linux. You'll need Python 3.10 or later, Git, taskset and Crystal. Fetch Aloli separately for the comparison.

```sh
git clone --branch v0.1.7 https://github.com/aloli-crystal/toml.git /tmp/aloli-toml
python3 bench/run.py verify --aloli /tmp/aloli-toml
python3 bench/run.py measure --aloli /tmp/aloli-toml --cpu 2 --output /tmp/toml-comparison.json
```

Choose an available logical CPU on an idle host and check that its SMT sibling is idle too. If you're using a laptop, plug it into AC power. The runner checks the Aloli commit and compiles both parsers into one binary with `--release --no-debug --threads 1`. The verify command builds the binary and checks that the parsers agree. Run the measure command when you want timings.

The results file identifies the binary by its SHA-256 digest and records both source revisions, the compiler and LLVM versions, and the kernel. It also lists the CPU model, governor, logical CPU and its siblings.

## Corpus and preflight

The three checked-in TOML 1.0 inputs describe a server, a build manifest with quoted keys, and a route list with escaped strings. The runner generates a lockfile with 2,048 `[[package]]` entries. Each package has a name, version, deterministic SHA-256 checksum and dependency array. Timing starts after generation and file reads. The fixtures omit temporal values because the two dynamic APIs represent them differently.

Before timing, the binary recursively compares the complete trees. Tables must have the same keys, arrays must have the same element order, and scalar values must match in both type and value. For floats it compares the bits. Any difference stops the run. The results file records each fixture's byte count, SHA-256 digest and number of root entries.

## Sampling and interpretation

The runner starts six pairs of fresh processes per fixture. FusedTOML runs first in odd pairs and Aloli runs first in even pairs. Both use the selected CPU and `GC_MARKERS=1 GC_NPROCS=1`. Crystal's `Benchmark::IPS` warms up for one second, then measures for two seconds in calibrated batches. Both parsers retain the most recent complete tree on each iteration.

For each process the results file gives the time per document in microseconds (the reciprocal of the mean parse rate), throughput in MiB/s of input, and managed bytes per document. It also records the batch count, relative standard deviation and host load at the start of the sample.

The table reports medians for each parser and fixture. To calculate speedup, divide Aloli's latency by FusedTOML's within each pair, then take the median of the six ratios. Managed bytes count GC allocation traffic.

These timings cover dynamic loading from a String. Typed loading, IO, writing, source-preserving edits, and peak process memory each need a separate workload. Profile the workload you want to improve before changing a hot path.

## AVX2 string-scanner experiment

FusedTOML keeps the eight-byte scanner as its default because AVX2 gave no consistent improvement on the three small configurations or the lockfile. On the Dell XPS 15 9520 (Core i9-12900HK), the AVX2 prototype cut whole-document parse time by 16% for long basic strings and 14% for long UTF-8 literal strings. All eight pairs favored AVX2 on both long-string inputs. [Benchmark prototype](../bench/avx2/scanner.cr) · [Raw measurements](receipts/dell-avx2-prefix8.json)

| Document | Eight-byte scanner | AVX2 | Paired change in parse time |
| --- | ---: | ---: | ---: |
| Server | 3.81 µs | 3.87 µs | +0.3% |
| Manifest | 4.19 µs | 4.23 µs | +1.0% |
| Routes | 4.65 µs | 4.60 µs | +0.5% |
| Lockfile | 2.90 ms | 3.04 ms | +3.1% |
| Long basic strings | 612 µs | 513 µs | −16.0% |
| Long UTF-8 literal strings | 605 µs | 515 µs | −14.0% |
| Escape-heavy basic strings | 199 µs | 197 µs | −0.9% |

Both binaries used the parser from `1350d91` and the same `FusedTOML.load` worker. The candidate first scans eight bytes with the existing code. If they contain no special byte, it checks 32 bytes at a time for the quote, ASCII controls and, in basic strings, backslashes. The existing scanner finds the exact position within a matching block and handles partial blocks. Crystal 1.22.3 and LLVM 22.1.3 generated the AVX2 byte comparisons from a Crystal loop.

Each long-string document has 128 keys with 4,096-byte values. One uses ASCII in double quotes, the other repeats `雪a` in single quotes. The escape-heavy document has 128 keys with 32 newline escapes apiece. Both workers returned the same complete tree for every document.

A separate build counted how often the scanner could skip a full 32-byte block. With the eight-byte prefix it skipped zero blocks on the small configurations and the escape-heavy input. On the lockfile it entered the vector loop 6,142 times and skipped 2,048 blocks, one per checksum. On each long-string document, 128 calls skipped 16,256 blocks.

The columns report median times across eight fresh processes per worker and fixture. Each pair ran on CPU 2 with at least half a second of warmup and one second of timed parsing per process. Run order alternated. The last column gives the median of the changes **within** each pair, so it can differ from the change between the two column medians. On the lockfile those paired changes ranged from 9.5% faster to 14.6% slower. All 112 samples passed the Dell benchmark's AC power, CPU and disk checks.

A second run waited for 128 ordinary bytes before switching to AVX2. Parse time fell 18.1% on long basic strings and 15.1% on long UTF-8 literal strings. On the lockfile the median change was +0.4%, with each scanner winning four pairs. The longest strings in that fixture are 64-byte checksums. Both prototypes passed all 58 project specs and the TOML 1.1 decoder suite on String and IO. [Follow-up measurements](receipts/dell-avx2-prefix128.json)

### Repeat the scanner comparison

From the repository root on a quiet AVX2 Linux host, choose an available core with an SMT sibling. The runner uses the same AC power and NVMe checks as the Dell cross-language benchmark.

```sh
work=$(mktemp -d)
export CRYSTAL_PATH="$PWD/src:$(crystal env CRYSTAL_PATH)"
crystal run --release bench/avx2/check.cr
crystal build --release --no-debug --threads 1 bench/cross_language/worker.cr -o "$work/baseline"
crystal build --release --no-debug --threads 1 --emit asm bench/avx2/worker.cr -o "$work/candidate"
python3 -B bench/avx2/compare.py --work "$work" --cpu 2
```

For the 128-byte prefix, reuse the baseline binary and run a fresh comparison.

```sh
long=$(mktemp -d)
cp "$work/baseline" "$long/baseline"
crystal run --release -Dbench_avx2_long_prefix bench/avx2/check.cr
crystal build --release --no-debug --threads 1 --emit asm -Dbench_avx2_long_prefix bench/avx2/worker.cr -o "$long/candidate"
python3 -B bench/avx2/compare.py --work "$long" --cpu 2 --fixtures lock long-basic long-literal
```
