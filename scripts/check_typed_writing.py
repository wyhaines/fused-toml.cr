"""Check consumer compilation and diagnostics for lazy typed writers."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
search = [root / "src", root / "spec/fixtures/typed_writing"]
stdlib = subprocess.check_output(["crystal", "env", "CRYSTAL_PATH"], text=True).strip()
env = dict(os.environ, CRYSTAL_PATH=os.pathsep.join([*map(str, search), stdlib]))
load = 'FusedTOML.load(%("job.timeout" = 5), ReadOnlyModel)'
cases = [
    ("load_only", 'raise "failed to load" unless ' + load + ".duration == 5.seconds", ()),
    ("missing_hook", load + ".to_toml", ("ReadOnlyConverter", "to_toml(value)", "field duration")),
    ("invalid_result", "FusedTOML.dump(InvalidResult.new)", ("InvalidConverter", "field duration", "Time::Span")),
    ("duplicate_key", "DuplicateKey.new.to_toml", ('Duplicate TOML field "port"',)),
    ("union_field", "AmbiguousField.new.to_toml", ("use a fusedtoml::field converter for union",)),
]

with tempfile.TemporaryDirectory(prefix="fused-toml-consumer-") as tmp:
    for name, expression, diagnostic in cases:
        file = Path(tmp) / (name + ".cr")
        file.write_text('require "fixture_models"\n' + expression + '\n')
        command = ["crystal", "build", "--no-codegen"] if diagnostic else ["crystal", "run"]
        result = subprocess.run([*command, "--no-color", "--threads", "1", file],
                                cwd=tmp, env=env, text=True, capture_output=True)
        if diagnostic:
            passed = result.returncode != 0 and all(s.lower() in result.stderr.lower() for s in diagnostic)
        else:
            passed = result.returncode == 0
        if not passed:
            raise SystemExit(f"{name}: unexpected compiler result {result.returncode}\n{result.stderr}")
        print(f"{name}: expected compiler result")
