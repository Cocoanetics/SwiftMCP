#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
git config core.hooksPath scripts/hooks
echo "core.hooksPath -> scripts/hooks"
