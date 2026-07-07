#!/usr/bin/env bash

set -euo pipefail

ROOT="$(dirname "$(readlink -f -- "$0")")"

missing=()
command -v dpkg-deb >/dev/null 2>&1 || missing+=("dpkg-deb")
if ! command -v rpmbuild >/dev/null 2>&1 && ! command -v alien >/dev/null 2>&1; then
  missing+=("rpmbuild or alien")
fi
if ((${#missing[@]})); then
  echo "Missing build tools: ${missing[*]}" >&2
  exit 1
fi

python3 -m pip install -q -U pip wheel setuptools

exec "$ROOT/pkg/native/build-package.sh" "$@"
