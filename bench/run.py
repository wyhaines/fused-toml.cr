#!/usr/bin/env python3
"""Build both parsers into one release binary; verify trees before sampling."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
ALOLI = "3cd645c67b83ce5b055bb0ae041d68fc354c7281"
PAIRS = 6


def output(*args, **kwargs):
    return subprocess.check_output(args, text=True, **kwargs).strip()


def revision(repo):
    if output("git", "-C", repo, "status", "--porcelain"):
        raise SystemExit(f"benchmark requires a clean checkout: {repo}")
    return output("git", "-C", repo, "rev-parse", "HEAD")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lockfile(path):
    with path.open("w", encoding="utf-8", newline="\n") as fp:
        fp.write('format = 1\n')
        for i in range(2048):
            name = f"pkg-{i:04}"
            checksum = hashlib.sha256(name.encode("ascii")).hexdigest()
            fp.write(f'\n[[package]]\nname = "{name}"\nversion = "1.{i % 20}.{i % 7}"\n')
            fp.write(f'checksum = "{checksum}"\n')
            deps = [] if i == 0 else [f"pkg-{i - 1:04}"]
            fp.write(f'dependencies = {json.dumps(deps)}\n')


def read_text(path):
    return path.read_text().strip() if path.is_file() else None


def cpu_info(cpu):
    syscpu = Path(f"/sys/devices/system/cpu/cpu{cpu}")
    return {
        "logical_cpu": cpu,
        "siblings": read_text(syscpu / "topology/thread_siblings_list"),
        "governor": read_text(syscpu / "cpufreq/scaling_governor"),
        "model": next((line.split(":", 1)[1].strip() for line in
                       Path("/proc/cpuinfo").read_text().splitlines()
                       if line.startswith("model name")), None),
    }


def campaign(args, work):
    aloli = args.aloli.resolve()
    reference = revision(aloli)
    if reference != ALOLI:
        raise SystemExit(f"expected aloli-crystal/toml {ALOLI}, got {reference}")
    env = dict(os.environ, GC_MARKERS="1", GC_NPROCS="1")
    env["CRYSTAL_PATH"] = str(aloli / "src") + os.pathsep + output("crystal", "env", "CRYSTAL_PATH", cwd=ROOT)
    binary = work / "parse"
    flags = ["--release", "--no-debug", "--threads", "1"]
    receipt = dict(fused=revision(ROOT), aloli=reference, compiler=output("crystal", "--version"),
                   platform=platform.platform(), build_flags=flags, gc_markers=1, gc_nprocs=1)
    subprocess.run(["crystal", "build", *flags, "bench/parse.cr", "-o", binary],
                   cwd=ROOT, env=env, check=True)
    receipt["binary_sha256"] = digest(binary)
    lock = work / "lock.toml"
    lockfile(lock)
    files = [*sorted((ROOT / "bench/fixtures").glob("*.toml")), lock]
    fixtures = receipt["fixtures"] = {}
    for fixture in files:
        check = json.loads(output(binary, "verify", fixture, env=env))
        fixtures[fixture.name] = dict(size=fixture.stat().st_size, sha256=digest(fixture), **check)
    if args.mode == "verify":
        print(json.dumps(receipt, indent=2))
        return

    receipt.update(cpu=cpu_info(args.cpu), pairs=PAIRS, warmup_seconds=1,
                   measurement_seconds=2, started_utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()))
    samples = receipt["samples"] = []
    for pair in range(PAIRS):
        for fixture in files:
            order = ("fused", "aloli") if pair % 2 == 0 else ("aloli", "fused")
            for parser in order:
                load = os.getloadavg()
                result = json.loads(output("taskset", "-c", str(args.cpu), binary, parser, fixture, env=env))
                if result["root_entries"] != fixtures[fixture.name]["root_entries"]:
                    raise RuntimeError(f"result lost for {fixture.name}")
                samples.append(dict(pair=pair + 1, fixture=fixture.name, parser=parser,
                                    loadavg=load, **result))
        print(f"completed pair {pair + 1}/{PAIRS}", file=sys.stderr, flush=True)
    summary = receipt["summary"] = {}
    for name in fixtures:
        groups = {p: [s for s in samples if s["fixture"] == name and s["parser"] == p]
                  for p in ("aloli", "fused")}
        summary[name] = {
            p: {k: statistics.median(s[k] for s in group)
                for k in ("latency_us", "mib_per_second", "managed_bytes_op")}
            for p, group in groups.items()
        }
        summary[name]["paired_speedup"] = statistics.median(
            a["latency_us"] / f["latency_us"] for a, f in zip(groups["aloli"], groups["fused"]))
    with args.output.open("x") as result:
        json.dump(receipt, result, indent=2)
        result.write("\n")
    print(json.dumps(summary, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["verify", "measure"])
    parser.add_argument("--aloli", required=True, type=Path)
    parser.add_argument("--cpu", type=int)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.mode == "measure":
        if args.cpu is None or args.output is None:
            parser.error("measure requires --cpu and --output")
        if args.cpu not in os.sched_getaffinity(0) or args.output.exists():
            parser.error("select an available CPU and a new output file")
    with tempfile.TemporaryDirectory(prefix="fused-toml-parse-") as tmp:
        campaign(args, Path(tmp))


if __name__ == "__main__":
    main()
