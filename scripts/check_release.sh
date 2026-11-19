#!/bin/sh
set -eu

# Run from the repository root. TOML_TEST may name an absolute path.
runner=${TOML_TEST:-toml-test}
case "$("$runner" version)" in
  "toml-test v2.2.0;"*) ;;
  *) echo 'expected toml-test v2.2.0' >&2; exit 1 ;;
esac

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
set -x
git rev-parse HEAD
crystal --version
shards --version
"$runner" version
shards check
crystal tool format --check src spec scripts bench
crystal spec --release --threads 1 --order=4721 --error-on-warnings
crystal spec -Dfused_toml_force_scalar_string_scan --threads 1 --order=7183 --error-on-warnings
python3 scripts/check_doc_examples.py
python3 scripts/check_typed_writing.py
crystal build --release --no-debug --threads 1 --error-on-warnings scripts/toml_test_decoder.cr -o "$work/decoder"
crystal build --release --no-debug --threads 1 --error-on-warnings scripts/toml_test_encoder.cr -o "$work/encoder"
sha256sum "$work/decoder" "$work/encoder"
"$runner" test -toml 1.1 -parallel 1 -color never -decoder "$work/decoder" -encoder "$work/encoder"
"$runner" test -toml 1.1 -parallel 1 -color never -decoder "$work/decoder --io"
