#!/usr/bin/env bash

set -euo pipefail

log="build.sh.log"
exec > >(tee -a "$log") 2>&1
echo "#### Starting build at $(date) ####"

nix build --log-format raw .#