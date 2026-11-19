import json
from pathlib import Path
import sys
from time import perf_counter_ns
import tomllib


def main():
    mode, path = sys.argv[1:]
    source = Path(path).read_text(encoding="utf-8")
    parse = tomllib.loads
    last = parse(source)
    if mode == "verify":
        print(json.dumps(last, ensure_ascii=False))
        return
    for line in sys.stdin:
        count = int(line)
        start = perf_counter_ns()
        for _ in range(count):
            last = parse(source)
        elapsed = perf_counter_ns() - start
        print(elapsed, len(last), flush=True)


if __name__ == "__main__":
    main()
