#!/usr/bin/env bash
# AiTM demo lab — one-time local setup. Run as the instructor, inside the Kali VM that will
# run the live demo. See ../README.md for the full walkthrough. (A macOS variant of these same
# steps is in README.md's "Running on macOS instead" section, if you're ever not on Kali.)
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$LAB_DIR/vendor"
DOMAIN="cyberlogin-demo.test"

echo "== Installing tools (go, oathtool, git, make) =="
sudo apt-get update -qq
sudo apt-get install -y golang-go oathtool git make

echo "== Fetching + building evilginx2 =="
mkdir -p "$VENDOR_DIR"
if [ ! -d "$VENDOR_DIR/evilginx2" ]; then
  git clone --depth 1 https://github.com/kgretzky/evilginx2.git "$VENDOR_DIR/evilginx2"
fi
( cd "$VENDOR_DIR/evilginx2" && make )
echo "Built: $VENDOR_DIR/evilginx2/build/evilginx"

echo "== Adding /etc/hosts entries for $DOMAIN (needs sudo) =="
for sub in "login.$DOMAIN" "www.$DOMAIN" "device.login.$DOMAIN"; do
  if ! grep -qE "^\s*127\.0\.0\.1\s+$sub\s*$" /etc/hosts 2>/dev/null; then
    sudo sh -c "printf '127.0.0.1 %s\n' '$sub' >> /etc/hosts"
    echo "added: $sub"
  else
    echo "already present: $sub"
  fi
done

mkdir -p "$LAB_DIR/run/config"

echo
echo "== Note: port 53 =="
echo "Kali runs systemd-resolved, which usually already holds port 53. Evilginx2 tries to bind"
echo "its own DNS server there too and will print a [fatal] line if it can't — that's harmless and"
echo "expected: this demo resolves names via /etc/hosts, not evilginx's own DNS server, so the"
echo "HTTPS side (the actual demo) is unaffected. Do NOT stop systemd-resolved to 'fix' this —"
echo "that breaks the VM's normal DNS resolution for no benefit here."
echo
echo "Setup done. Next: see README.md 'Run the demo' section."
echo "Start evilginx2 with:"
echo "  sudo $VENDOR_DIR/evilginx2/build/evilginx -developer -c $LAB_DIR/run/config -p $LAB_DIR/phishlets"
