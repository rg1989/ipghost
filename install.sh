#!/bin/sh
# ipghost installer — https://github.com/rg1989/ipghost
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/rg1989/ipghost/main/install.sh | sudo sh
#
# Environment overrides:
#   IPGHOST_DEST  install directory (default /usr/local/bin)
#   IPGHOST_SRC   script URL (default .../main/ipghost)

set -eu

DEST="${IPGHOST_DEST:-/usr/local/bin}"
SRC="${IPGHOST_SRC:-https://raw.githubusercontent.com/rg1989/ipghost/main/ipghost}"

fail() { echo "ipghost install: error: $*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || fail "curl is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required (3.8+)"

TMP="$(mktemp "${TMPDIR:-/tmp}/ipghost.XXXXXX")"
trap 'rm -f "$TMP"' EXIT

echo "Downloading $SRC ..."
curl -fsSL "$SRC" -o "$TMP" || fail "download failed"
head -n 1 "$TMP" | grep -q 'python3' || fail "downloaded file does not look like the ipghost script"

install_to() {
    mkdir -p "$DEST"
    install -m 0755 "$TMP" "$DEST/ipghost"
}

if [ "$(id -u)" = "0" ]; then
    install_to || fail "could not install into $DEST"
elif { [ -d "$DEST" ] && [ -w "$DEST" ]; } \
   || { [ ! -d "$DEST" ] && [ -w "$(dirname "$DEST")" ]; }; then
    install_to || fail "could not install into $DEST"
else
    echo "Installing into $DEST needs administrator rights; requesting sudo ..."
    sudo mkdir -p "$DEST"
    sudo install -m 0755 "$TMP" "$DEST/ipghost" || fail "could not install into $DEST"
fi

echo
"$DEST/ipghost" --version
echo
echo "Installed: $DEST/ipghost"
echo "Quick start:"
echo "  ipghost add 10.99.99.99 example.com --ports 443,8080"
echo "  ipghost up && ipghost status"
