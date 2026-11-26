#!/usr/bin/env bash
# Remove the Telegram MTProto proxy
set -e
docker rm -f mtg-proxy 2>/dev/null || true
rm -rf /opt/mtg-proxy
rm -f /etc/sysctl.d/99-mtg-proxy.conf
echo "تم حذف البروكسي."
