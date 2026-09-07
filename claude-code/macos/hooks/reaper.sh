#!/bin/sh
# Compatibility entry point for the shared fixed-duration cache reaper.
set -eu
helper_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$helper_dir/harness_cache.py" --harness claude-code purge-expired
