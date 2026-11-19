"""Time the same FusedTOML worker with the shipped and experimental scanners."""
import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys
import time

BENCH = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BENCH))
from cross_language import run as harness
from run import cpu_info, lockfile


def documents(work):
    paths = [BENCH / "fixtures" / f"{name}.toml" for name in ("server", "manifest", "routes")]
    path = work / "lock.toml"
    lockfile(path)
    paths.append(path)
    for name, quote, content in (
        ("long-basic", '"', "0123456789abcdef" * 256),
        ("long-literal", "'", "雪a" * 1024),
        ("escape-heavy", '"', r"abcdefg\n" * 32),
    ):
        path = work / f"{name}.toml"
        path.write_text("".join(f"k{i} = {quote}{content}{quote}\n" for i in range(128)),
                        encoding="utf-8")
        paths.append(path)
    return paths


def measure(command, path, env, cpu, roots, peers, others):
    before = harness.cpu_ticks()
    disks, start = harness.disk_ticks(), time.monotonic()
    obs = harness.timed([str(command)], path, env, cpu, roots)
    after = harness.cpu_ticks()
    obs.update(peer_idle_pct=harness.idle(before, after, peers),
               other_available_pct=harness.idle(before, after, others, include_iowait=True),
               disk_busy_pct=harness.disk_busy(disks, start), ac=harness.power().get("AC"))
    return obs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True,
                        help="Directory containing the baseline and candidate release binaries")
    parser.add_argument("--cpu", type=int, required=True)
    parser.add_argument("--fixtures", nargs="+", help="Limit the run to named fixtures")
    args = parser.parse_args()
    work, cpu = args.work.resolve(), args.cpu
    outfile = work / "results.json"
    if outfile.exists():
        raise SystemExit(f"Results already exist: {outfile}")
    cpus = sorted(os.sched_getaffinity(0))
    info = cpu_info(cpu)
    siblings = [c for c in cpus if cpu_info(c)["siblings"] == info["siblings"]]
    peers = [c for c in siblings if c != cpu]
    others = [c for c in cpus if c != cpu]
    if cpu not in siblings or not peers:
        raise SystemExit("Choose an available core with an available SMT sibling")
    if any("avx2" not in line.split() for line in Path("/proc/cpuinfo").read_text().splitlines()
           if line.startswith("flags")):
        raise SystemExit("An AVX2-capable host is required for this comparison")
    env = dict(os.environ, GC_MARKERS="1", GC_NPROCS="1")
    names = ("baseline", "candidate")
    docs = documents(work)
    if args.fixtures:
        selected = set(args.fixtures)
        docs = [path for path in docs if path.stem in selected]
        if len(docs) != len(selected):
            raise SystemExit("Unknown fixture name")
    result = dict(started_utc=harness.utc(), cpu=cpu, cpu_info=info, host=os.uname().nodename,
                  crystal=harness.output("crystal", "--version"),
                  sha256={n: harness.sha(work / n) for n in names},
                  scanner_sha256=harness.sha(BENCH / "avx2/scanner.cr"),
                  fixtures={}, quiet=[], samples=[], discarded=[])
    for path in docs:
        trees = [subprocess.check_output([work / name, "verify", path], env=env) for name in names]
        if trees[0] != trees[1]:
            raise RuntimeError(f"Different parse trees for {path}")
        result["fixtures"][path.stem] = dict(bytes=path.stat().st_size,
                                             sha256=harness.sha(path), roots=len(json.loads(trees[0])))
    for r in range(8):
        result["quiet"].append(harness.quiet(siblings, cpus))
        for i in range(len(docs)):
            index = (i + r) % len(docs)
            path = docs[index]
            ordered = names if (index + r) % 2 == 0 else names[::-1]
            for order, name in enumerate(ordered):
                for attempt in range(3):
                    sample = measure(work / name, path, env, cpu,
                                     result["fixtures"][path.stem]["roots"], peers, others)
                    sample.update(round=r+1, position=order+1, worker=name, fixture=path.stem)
                    if (sample["peer_idle_pct"] >= 90 and sample["other_available_pct"] >= 90
                            and sample["disk_busy_pct"] <= 15 and sample["ac"] == 1):
                        result["samples"].append(sample)
                        break
                    result["discarded"].append(sample)
                    result["quiet"].append(harness.quiet(siblings, cpus))
                else:
                    raise RuntimeError("Persistent background load")
        result["finished_utc"] = harness.utc()
        outfile.write_text(json.dumps(result, indent=2) + "\n")
        print(f"Completed pair {r+1}/8", flush=True)
    for path in docs:
        pairs = [[s["us_per_parse"] for s in result["samples"]
                  if s["fixture"] == path.stem and s["worker"] == name] for name in names]
        deltas = [100 * (b / a - 1) for a, b in zip(*pairs)]
        print(f"{path.stem:14} {statistics.median(pairs[0]):8.2f} {statistics.median(pairs[1]):8.2f}"
              f" µs   {statistics.median(deltas):+6.2f}% paired latency")


if __name__ == "__main__":
    main()
