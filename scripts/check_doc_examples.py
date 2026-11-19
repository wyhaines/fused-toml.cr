"""Compile the README examples and check their annotated results."""
import os
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
blocks = re.findall(r"^```crystal\n(.*?)^```$", (root / "README.md").read_text(), re.M | re.S)
if not blocks:
    raise SystemExit("README contains no Crystal examples")
lines = ['require "fused_toml"']
for block in blocks:
    for line in block.splitlines():
        code, marker, expected = line.partition(" # => ")
        if marker:
            lines.append(f'raise "README result mismatch" unless ({code.strip()}) == ({expected})')
        else:
            lines.append(line)

with tempfile.TemporaryDirectory(prefix="fused-toml-examples-") as tmp:
    work = Path(tmp)
    (work / "settings.toml").write_text("http = 8080\n")
    (work / "examples.cr").write_text("\n".join(lines) + "\n")
    crystal_path = subprocess.check_output(["crystal", "env", "CRYSTAL_PATH"], text=True).strip()
    env = dict(os.environ, CRYSTAL_PATH=str(root / "src") + os.pathsep + crystal_path)
    subprocess.run(["crystal", "run", "examples.cr", "--threads", "1", "--error-on-warnings"],
                   cwd=work, env=env, check=True)
print(f"{len(blocks)} README examples passed")
