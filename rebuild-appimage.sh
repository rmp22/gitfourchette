#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./rebuild-appimage.sh [--skip-deps]

Creates or reuses build/appimage-venv, installs missing host-side AppImage
build tools, runs pkg/appimage/build-appimage.sh, and restores
gitfourchette/appconsts.py.
EOF
}

SKIP_DEPS=0
PIP_DEPS=(pip wheel setuptools python-appimage pygit2)
PYTHON_DEPS=(pip wheel setuptools python_appimage pygit2)

while (($#)); do
  case "$1" in
    --skip-deps)
      SKIP_DEPS=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

ROOT="$(dirname "$(readlink -f -- "$0")")"
VENV="$ROOT/build/appimage-venv"
APP_CONSTS="$ROOT/gitfourchette/appconsts.py"
BACKUP="$ROOT/build/appconsts.py.before-appimage"

mkdir -p "$ROOT/build"
cp "$APP_CONSTS" "$BACKUP"

restore_appconsts() {
  if [[ -f "$BACKUP" ]]; then
    cp "$BACKUP" "$APP_CONSTS"
  fi
}

trap restore_appconsts EXIT

deps_installed() {
  python - "${PYTHON_DEPS[@]}" <<'PY'
import importlib.util
import sys

missing = [module for module in sys.argv[1:] if importlib.util.find_spec(module) is None]
if missing:
    print("Missing AppImage build deps: " + ", ".join(missing))
    sys.exit(1)
PY
}

if [[ ! -x "$VENV/bin/python" ]]; then
  python3 -m venv "$VENV"
fi
source "$VENV/bin/activate"

if (( SKIP_DEPS )); then
  echo "Skipping dependency installation."
elif deps_installed; then
  echo "AppImage build dependencies already installed."
else
  python -m pip install -U "${PIP_DEPS[@]}"
fi

export PINNED_REQUIREMENTS="${PINNED_REQUIREMENTS:-}"

bash "$ROOT/pkg/appimage/build-appimage.sh"
