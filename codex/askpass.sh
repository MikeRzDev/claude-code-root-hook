#!/bin/sh
# stdout belongs to sudo's password pipe. Never run this helper directly.
set -eu
helper_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cache_helper="$helper_dir/harness_cache.py"
# Also support invoking the helper from a source checkout.
[ -f "$cache_helper" ] || cache_helper="$helper_dir/../harness_cache.py"
exec python3 "$cache_helper" --harness codex askpass
