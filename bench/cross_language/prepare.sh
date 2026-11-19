#!/bin/sh
# Usage: sh bench/cross_language/prepare.sh EMPTY_WORKDIR FUSED_REV RUBY
set -eu
work=$(realpath "$1")
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
rev=$(git -C "$root" rev-parse --verify "$2^{commit}")
ruby=$(realpath "$3")
mkdir "$work/fused" "$work/cross_language"
git -C "$root" archive "$rev" src bench/fixtures bench/run.py > "$work/source.tar"
tar -xf "$work/source.tar" -C "$work/fused"
cp -R "$root/bench/cross_language/." "$work/cross_language/"
cd "$work"
git clone -q --branch v0.8.1 --depth 1 https://github.com/crystal-community/toml.cr.git community
git clone -q --branch v0.1.7 --depth 1 https://github.com/aloli-crystal/toml.git aloli
test "$(git -C community rev-parse HEAD)" = 030a3866af395bfb9fe2cce234d9b3d0d8f3ad3c
test "$(git -C aloli rev-parse HEAD)" = 3cd645c67b83ce5b055bb0ae041d68fc354c7281
stdlib=$(crystal env CRYSTAL_PATH)
for impl in fused community aloli; do
  CRYSTAL_PATH="$work/$impl/src:$stdlib" crystal build --release --no-debug --threads 1 \
    "-Dbench_$impl" cross_language/worker.cr -o "$impl-worker"
done
cargo build --manifest-path cross_language/rust/Cargo.toml --release --locked --jobs 2
PATH="$(dirname "$ruby"):$PATH" GEM_HOME="$work/gems" GEM_PATH="$work/gems" \
  "$ruby" -S gem install --install-dir "$work/gems" --no-document bigdecimal:4.1.3 toml-rb:6.0.0 tomlib:0.7.3
python3 -c 'import sys; sys.path.insert(0, "fused/bench"); from run import lockfile; from pathlib import Path; lockfile(Path("lock.toml"))'
