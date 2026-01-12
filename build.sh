#!/usr/bin/env bash

set -euo pipefail

log="build.sh.$(date +%Y%m%d%H%M%S).log"
exec > >(tee -a "$log") 2>&1
echo "#### Starting build at $(date) ####"

if [[ "${1:-}" == "--wrap" ]]; then
    if [ -z "${SYSTEMD_RUN:-}" ] && command -v systemd-run >/dev/null 2>&1; then
        mem_avail_bytes="$(free -b | awk '/^Mem:/ {print $7}')"
        mem_limit_bytes=$((mem_avail_bytes * 80 / 100))
        echo "#### Launching build in systemd scope (MemoryMax=${mem_limit_bytes} bytes) ####"
        exec systemd-run --user --scope -p "MemoryMax=${mem_limit_bytes}" \
            env SYSTEMD_RUN=1 bash "$0"
    fi
fi

nix build --log-format raw .#
