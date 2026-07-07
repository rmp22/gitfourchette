#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: pkg/native/build-package.sh [--with-mfusepy] [--deb-only] [--rpm-only]

Builds native .deb and .rpm packages of GitFourchette.

All Python dependencies (pygit2, PyQt6, Pygments) are bundled under
/usr/lib/gitfourchette/site. The package's only external runtime dependency is
the matching system Python interpreter (python3.X, pinned to the build
interpreter because pygit2 ships a version-specific extension) plus the usual
Qt system libraries.

Artifacts are written to dist/.
EOF
}

WITH_MFUSEPY=0
BUILD_DEB=1
BUILD_RPM=1

while (($#)); do
  case "$1" in
    --with-mfusepy) WITH_MFUSEPY=1 ;;
    --deb-only) BUILD_RPM=0 ;;
    --rpm-only) BUILD_DEB=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

HERE="$(dirname "$(readlink -f -- "$0")")"
ROOT="$(readlink -f -- "$HERE/../..")"
FLATPAK="$ROOT/pkg/flatpak"

APPID="org.gitfourchette.gitfourchette"
APPVER="$(cd "$ROOT" && python3 -c 'from gitfourchette.appconsts import APP_VERSION; print(APP_VERSION)')"

PYVER="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
PYBIN="python$PYVER"

DEB_ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
RPM_ARCH="$(uname -m)"

echo "GitFourchette $APPVER — native package build (interpreter: $PYBIN)"

DIST="$ROOT/dist"
STAGE="$ROOT/build/native/gitfourchette_${APPVER}_${DEB_ARCH}"
SITE="$STAGE/usr/lib/gitfourchette/site"

mkdir -p "$DIST"
rm -rf "$STAGE"
mkdir -p \
  "$SITE" \
  "$STAGE/usr/bin" \
  "$STAGE/usr/share/applications" \
  "$STAGE/usr/share/icons/hicolor/256x256/apps" \
  "$STAGE/usr/share/metainfo" \
  "$STAGE/usr/share/doc/gitfourchette"

EXTRAS="pyqt6,pygments"
if ((WITH_MFUSEPY)); then
  EXTRAS="$EXTRAS,mfusepy"
fi
"$PYBIN" -m pip install --target "$SITE" "$ROOT[$EXTRAS]"

find "$SITE" -type d -name '__pycache__' -prune -exec rm -rf {} +
find "$SITE" -type d \( -name 'tests' -o -name 'test' \) -prune -exec rm -rf {} +
find "$SITE" -type f \( -name '*.pyc' -o -name '*.pyi' \) -delete
find "$SITE" -maxdepth 2 -type d -name 'bin' -exec rm -rf {} +

make_launcher() {
  local path="$1" module="$2"
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'export PYTHONPATH=/usr/lib/gitfourchette/site'
    printf 'exec %s -m %s "$@"\n' "$PYBIN" "$module"
  } > "$path"
  chmod 0755 "$path"
}
make_launcher "$STAGE/usr/bin/gitfourchette" "gitfourchette"
make_launcher "$STAGE/usr/bin/gitfourchette-askpass" "gitfourchette.forms.askpassdialog"
make_launcher "$STAGE/usr/bin/gitfourchette-mount" "gitfourchette.mount.treemount"

install -m 0644 "$FLATPAK/$APPID.desktop" "$STAGE/usr/share/applications/$APPID.desktop"
install -m 0644 "$FLATPAK/$APPID.png" "$STAGE/usr/share/icons/hicolor/256x256/apps/$APPID.png"
install -m 0644 "$FLATPAK/$APPID.metainfo.xml" "$STAGE/usr/share/metainfo/$APPID.metainfo.xml"
install -m 0644 "$ROOT/README.md" "$STAGE/usr/share/doc/gitfourchette/README.md"
install -m 0644 "$ROOT/CHANGELOG.md" "$STAGE/usr/share/doc/gitfourchette/CHANGELOG.md"
install -m 0644 "$ROOT/LICENSE" "$STAGE/usr/share/doc/gitfourchette/LICENSE"

INSTALLED_SIZE="$(du -sk "$STAGE/usr" | cut -f1)"

write_refresh_hook() {
  local path="$1"
  {
    printf '%s\n' '#!/bin/sh'
    printf '%s\n' 'set -e'
    printf '%s\n' 'if command -v update-desktop-database >/dev/null 2>&1; then'
    printf '%s\n' '  update-desktop-database -q /usr/share/applications || true'
    printf '%s\n' 'fi'
    printf '%s\n' 'if command -v gtk-update-icon-cache >/dev/null 2>&1; then'
    printf '%s\n' '  gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true'
    printf '%s\n' 'fi'
  } > "$path"
}

build_deb() {
  local debdir="$STAGE/DEBIAN"
  mkdir -p "$debdir"
  cat > "$debdir/control" <<EOF
Package: gitfourchette
Version: $APPVER
Architecture: $DEB_ARCH
Maintainer: Iliyas Jorio <https://gitfourchette.org>
Section: vcs
Priority: optional
Installed-Size: $INSTALLED_SIZE
Depends: $PYBIN, libc6, libglib2.0-0, libgl1, libegl1, libxkbcommon0, libfontconfig1, libfreetype6, libdbus-1-3
Homepage: https://gitfourchette.org
Description: The comfortable Git UI
 GitFourchette is a comfortable way to explore and understand your Git
 repositories, craft commits, and manage branches, with a snappy Qt UI.
EOF
  write_refresh_hook "$debdir/postinst"
  chmod 0755 "$debdir/postinst"

  local out="$DIST/gitfourchette_${APPVER}_${DEB_ARCH}.deb"
  dpkg-deb --root-owner-group --build "$STAGE" "$out"
  echo "Built $out"
}

build_rpm() {
  if command -v rpmbuild >/dev/null 2>&1; then
    local top="$ROOT/build/native/rpmbuild"
    rm -rf "$top"
    mkdir -p "$top"/{BUILD,RPMS,SOURCES,SPECS,SRPMS,BUILDROOT}
    local spec="$top/SPECS/gitfourchette.spec"
    cat > "$spec" <<EOF
Name:           gitfourchette
Version:        $APPVER
Release:        1
Summary:        The comfortable Git UI
License:        GPL-3.0-or-later
URL:            https://gitfourchette.org
BuildArch:      $RPM_ARCH
Requires:       $PYBIN
AutoReqProv:    no

%description
GitFourchette is a comfortable way to explore and understand your Git
repositories, craft commits, and manage branches, with a snappy Qt UI.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/usr
cp -a $STAGE/usr/. %{buildroot}/usr/

%files
/usr/lib/gitfourchette
/usr/bin/gitfourchette
/usr/bin/gitfourchette-askpass
/usr/bin/gitfourchette-mount
/usr/share/applications/$APPID.desktop
/usr/share/icons/hicolor/256x256/apps/$APPID.png
/usr/share/metainfo/$APPID.metainfo.xml
/usr/share/doc/gitfourchette

%post
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -qtf /usr/share/icons/hicolor || true
fi
EOF

    rpmbuild -bb --define "_topdir $top" "$spec"
    local built
    built="$(find "$top/RPMS" -name '*.rpm' | head -n1)"
    local out="$DIST/gitfourchette-${APPVER}-1.${RPM_ARCH}.rpm"
    cp -f "$built" "$out"
    echo "Built $out"
  elif command -v alien >/dev/null 2>&1; then
    local deb="$DIST/gitfourchette_${APPVER}_${DEB_ARCH}.deb"
    if [[ -f "$deb" ]]; then
      echo "rpmbuild not found; converting .deb with alien (may require root)."
      (cd "$DIST" && alien --to-rpm --keep-version --scripts "$deb")
    else
      echo "rpmbuild not found and no .deb to convert; skipping .rpm." >&2
    fi
  else
    echo "Neither rpmbuild nor alien found; skipping .rpm." >&2
  fi
}

if ((BUILD_DEB)); then
  build_deb
fi
if ((BUILD_RPM)); then
  build_rpm
fi

echo "Done. Artifacts in $DIST:"
ls -1 "$DIST" | sed 's/^/  /'
