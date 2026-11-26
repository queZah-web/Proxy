#!/usr/bin/env bash
# =============================================================
#  Telegram MTProto Proxy (Fake-TLS) - one-command installer
#  Engine: mtg v2 (https://github.com/9seconds/mtg) in Docker
#  Usage:  sudo bash install.sh [PORT] [FAKE_TLS_DOMAIN]
#  Example: sudo bash install.sh 443 www.cloudflare.com
# =============================================================
set -euo pipefail

PORT="${1:-443}"
DOMAIN="${2:-www.cloudflare.com}"
IMAGE="nineseconds/mtg:2"
NAME="mtg-proxy"
DIR="/opt/mtg-proxy"

green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { red "شغّل السكربت بصلاحيات root: sudo bash install.sh"; exit 1; }

# ---------- 1) Docker ----------
if ! command -v docker >/dev/null 2>&1; then
  green "[1/5] تثبيت Docker..."
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker >/dev/null 2>&1 || true

# ---------- 2) Speed tuning (BBR + bigger buffers) ----------
green "[2/5] تحسين سرعة الشبكة (BBR)..."
cat > /etc/sysctl.d/99-mtg-proxy.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_notsent_lowat = 16384
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
fs.file-max = 1048576
EOF
modprobe tcp_bbr 2>/dev/null || true
sysctl --system >/dev/null 2>&1 || true

# ---------- 3) Secret ----------
mkdir -p "$DIR"
docker pull "$IMAGE" >/dev/null
if [ -f "$DIR/secret" ]; then
  SECRET="$(cat "$DIR/secret")"
  green "[3/5] استخدام السر الموجود مسبقاً."
else
  green "[3/5] توليد سر Fake-TLS للدومين $DOMAIN ..."
  SECRET="$(docker run --rm "$IMAGE" generate-secret --hex "$DOMAIN")"
  echo "$SECRET" > "$DIR/secret"
  chmod 600 "$DIR/secret"
fi

cat > "$DIR/config.toml" <<EOF
secret = "$SECRET"
bind-to = "0.0.0.0:3128"
concurrency = 8192
prefer-ip = "prefer-ipv4"
EOF

# ---------- 4) Run ----------
green "[4/5] تشغيل البروكسي على المنفذ $PORT ..."
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  --ulimit nofile=1048576:1048576 \
  -p "$PORT":3128 \
  -v "$DIR/config.toml":/config.toml:ro \
  "$IMAGE" >/dev/null

# Open firewall if present
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q active; then
  ufw allow "$PORT"/tcp >/dev/null
fi

# ---------- 5) Link ----------
sleep 2
IP="$(curl -4 -fsS https://api.ipify.org || curl -4 -fsS https://ifconfig.me || hostname -I | awk '{print $1}')"
LINK="tg://proxy?server=${IP}&port=${PORT}&secret=${SECRET}"
WEB="https://t.me/proxy?server=${IP}&port=${PORT}&secret=${SECRET}"
echo "$WEB" > "$DIR/link.txt"

green "[5/5] تم ✅"
echo
echo "السيرفر : $IP"
echo "المنفذ  : $PORT"
echo "السر    : $SECRET"
echo
green "رابط البروكسي (افتحه من جوالك وسيضاف تلقائياً لتليجرام):"
echo "$WEB"
echo "$LINK"
echo
echo "الرابط محفوظ في: $DIR/link.txt"
echo "BBR: $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || echo unknown)"
