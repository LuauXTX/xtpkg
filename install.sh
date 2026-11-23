#!/bin/sh
set -eu
case "$(uname -s)" in
    Linux|Darwin) ;;
    *) printf '%s\n' 'error: install.sh supports Linux and macOS; use install.cmd on Windows.' >&2; exit 1 ;;
esac
command -v git >/dev/null 2>&1 || { printf '%s\n' 'error: Git is required on PATH.' >&2; exit 1; }
runtime=${LUAUXTX_BIN:-luauxtx}
runtime=$(command -v "$runtime") || { printf '%s\n' 'error: LuauXTX is required. Install it or set LUAUXTX_BIN to its native executable.' >&2; exit 1; }
source_dir=$(CDPATH= cd -P -- "$(dirname -- "$0")" && pwd)
# No download, sudo, eval, or install hooks. All arguments retain their boundaries.
exec "$runtime" "$source_dir/src/setup/main.luau" "$@"
