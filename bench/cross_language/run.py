"""Compare native, in-memory parses using a pinned CPU and balanced process order."""
import argparse
import datetime
import hashlib
import json
import os
import platform
import statistics
import subprocess
import sys
import time
from pathlib import Path


def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def output(*command):
    return subprocess.check_output(command, text=True).strip()


def cpu_ticks():
    return {key: tuple(map(int, fields[:8]))
            for key, *fields in (line.split() for line in Path("/proc/stat").read_text().splitlines())
            if key.startswith("cpu") and key[3:].isdigit()}


def idle(before, after, cpus, include_iowait=False):
    total = unused = 0
    for cpu in cpus:
        a, b = before[f"cpu{cpu}"], after[f"cpu{cpu}"]
        total += sum(b) - sum(a)
        unused += b[3] - a[3]
        if include_iowait:
            unused += b[4] - a[4]
    return 100 * unused / max(1, total)


def power():
    return {p.parent.name: int(p.read_text()) for p in Path("/sys/class/power_supply").glob("*/online")}


def disk_ticks():
    return {p.name: int((p / "stat").read_text().split()[9])
            for p in Path("/sys/block").glob("nvme*n*")}


def disk_busy(before, start):
    elapsed_ms = (time.monotonic() - start) * 1000
    return max(100 * (ticks - before[dev]) / elapsed_ms for dev, ticks in disk_ticks().items())


def quiet(siblings, cpus):
    for _ in range(60):
        start = cpu_ticks()
        disks, stamp = disk_ticks(), time.monotonic()
        time.sleep(3)
        end = cpu_ticks()
        sample = dict(utc=utc(), idle_pct=idle(start, end, cpus),
                      cpu_available_pct=idle(start, end, cpus, include_iowait=True),
                      disk_busy_pct=disk_busy(disks, stamp),
                      core_idle_pct={n: idle(start, end, [n]) for n in siblings},
                      power=power(), loadavg=os.getloadavg())
        if (sample["power"].get("AC") == 1 and sample["cpu_available_pct"] >= 95
                and sample["disk_busy_pct"] <= 10 and min(sample["core_idle_pct"].values()) >= 95):
            return sample
        time.sleep(2)
    raise RuntimeError("Dell has not been quiet on AC for five minutes")


def timed(command, source, env, cpu, roots):
    with subprocess.Popen(["taskset", "-c", str(cpu), *command, "measure", source],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=env) as worker:
        def batch(count):
            print(count, file=worker.stdin, flush=True)
            response = worker.stdout.readline().split()
            if len(response) != 2 or int(response[1]) != roots:
                raise RuntimeError(f"worker returned {response}: {command} {source}")
            return int(response[0])

        count = 1
        warm_ns = 0
        while warm_ns < 500_000_000:
            duration = batch(count)
            warm_ns += duration
            count = max(1, min(100_000, 8 * count, round(count * 80_000_000 / max(1, duration))))
        measured = iterations = batches = 0
        while measured < 1_000_000_000:
            measured += batch(count)
            iterations += count
            batches += 1
        worker.stdin.close()
        if worker.wait() != 0:
            raise RuntimeError(f"worker failed: {command}")
    return dict(iterations=iterations, elapsed_ns=measured, batches=batches,
                batch_size=count, warmup_ns=warm_ns, us_per_parse=measured / iterations / 1000)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--cpu", type=int, required=True)
    parser.add_argument("--python", required=True)
    parser.add_argument("--ruby", required=True)
    parser.add_argument("--fused-rev", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    work, cpu = args.work.resolve(), args.cpu
    harness = Path(__file__).resolve().parent
    ruby = [args.ruby, "--disable-yjit", str(harness / "worker.rb")]
    commands = {name: [str(work / (name + "-worker"))] for name in ("fused", "community", "aloli")}
    commands.update({"toml-rb": [*ruby, "toml-rb"], "tomlib": [*ruby, "tomlib"],
                     "tomllib": [args.python, str(harness / "worker.py")],
                     "rust-toml": [str(harness / "rust/target/release/toml-bench-worker")]})
    env = dict(os.environ, GC_MARKERS="1", GC_NPROCS="1",
               GEM_HOME=str(work / "gems"), GEM_PATH=str(work / "gems"))
    cpus = sorted(os.sched_getaffinity(0))
    topo = Path(f"/sys/devices/system/cpu/cpu{cpu}")
    siblings = [n for n in cpus if (Path(f"/sys/devices/system/cpu/cpu{n}/topology/thread_siblings_list").read_text()
                                    == (topo / "topology/thread_siblings_list").read_text())]
    if cpu not in cpus:
        raise ValueError("CPU outside affinity")
    versions = {"crystal": output("crystal", "--version"), "python": output(args.python, "-VV"),
                "rustc": output("rustc", "-Vv"), "cargo": output("cargo", "--version"),
                "ruby": output(args.ruby, "--disable-yjit", "-v")}
    for gem in ("toml-rb", "tomlib"):
        versions[gem] = subprocess.check_output([args.ruby, "-e",
            f'require "{gem}"; puts Gem.loaded_specs.fetch("{gem}").version'], text=True, env=env).strip()
    for shard in ("aloli", "community"):
        versions[shard] = output("git", "-C", work / shard, "rev-parse", "HEAD")
    versions["fused"] = args.fused_rev
    artifacts = {name: sha(Path(cmd[0])) for name, cmd in commands.items()}
    for f in ["run.py", "worker.cr", "worker.rb", "worker.py", "rust/src/main.rs", "rust/Cargo.lock"]:
        artifacts[f] = sha(harness / f)
    result = dict(versions=versions, sha256=artifacts, started_utc=utc(), logical_cpu=cpu,
                  siblings=siblings, kernel=platform.release(), host=platform.node(),
                  model=Path("/sys/class/dmi/id/product_name").read_text().strip(),
                  cpu_model=next(s.partition(":")[2].strip() for s in Path("/proc/cpuinfo").read_text().splitlines()
                                 if s.startswith("model name")),
                  governor=(topo / "cpufreq/scaling_governor").read_text().strip(),
                  preflight={}, samples=[], discarded=[], quiet_checks=[])
    inputs = [work / "fused/bench/fixtures" / (n + ".toml") for n in ("server", "manifest", "routes")]
    inputs.append(work / "lock.toml")
    for path in inputs:
        fingerprints = {}
        for name, command in commands.items():
            response = subprocess.check_output([*command, "verify", path], env=env, timeout=90)
            tree = json.loads(response)
            canonical = json.dumps(tree, ensure_ascii=False, sort_keys=True,
                                   separators=(",", ":"), allow_nan=False).encode()
            fingerprints[name] = hashlib.sha256(canonical).hexdigest()
        if len(set(fingerprints.values())) != 1:
            raise RuntimeError(f"tree mismatch: {path.name}: {fingerprints}")
        result["preflight"][path.name] = dict(bytes=path.stat().st_size, sha256=sha(path),
            root_entries=len(tree), tree_sha256=fingerprints, equivalent=True)
        print(f"Verified {path.name} on {len(commands)} parsers", flush=True)

    def save():
        tmp = args.output.with_suffix(".partial.json")
        tmp.write_text(json.dumps(result, indent=2) + "\n")
        tmp.replace(args.output)

    names = list(commands)
    if args.output.exists():
        raise FileExistsError(args.output)
    for r in range(len(names)):
        result["quiet_checks"].append(quiet(siblings, cpus))
        for f in range(len(inputs)):
            path = inputs[(r + f) % len(inputs)]
            ordered = [names[(i + r + inputs.index(path)) % len(names)] for i in range(len(names))]
            for position, name in enumerate(ordered):
                for attempt in range(3):
                    before = cpu_ticks()
                    disks, stamp = disk_ticks(), time.monotonic()
                    load = os.getloadavg()
                    sample = timed(commands[name], path, env, cpu, result["preflight"][path.name]["root_entries"])
                    after = cpu_ticks()
                    sample.update(round=r+1, order=position+1, utc=utc(), parser=name, fixture=path.name,
                                  loadavg=load, peer_idle_pct=idle(before, after, [n for n in siblings if n != cpu]),
                                  other_idle_pct=idle(before, after, [n for n in cpus if n != cpu]),
                                  other_cpu_available_pct=idle(before, after, [n for n in cpus if n != cpu], True),
                                  disk_busy_pct=disk_busy(disks, stamp), ac=power().get("AC"))
                    if (sample["peer_idle_pct"] >= 90 and sample["other_cpu_available_pct"] >= 90
                            and sample["disk_busy_pct"] <= 15 and sample["ac"] == 1):
                        result["samples"].append(sample)
                        break
                    result["discarded"].append(sample)
                    save()
                    result["quiet_checks"].append(quiet(siblings, cpus))
                else:
                    raise RuntimeError("persistent background load")
            save()
        print(f"Completed round {r+1}/{len(names)}", flush=True)
    result["median_us"] = {path.name: {name: statistics.median(s["us_per_parse"] for s in result["samples"]
        if s["parser"] == name and s["fixture"] == path.name) for name in names} for path in inputs}
    result["finished_utc"] = utc()
    save()


if __name__ == "__main__":
    main()
