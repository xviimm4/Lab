#!/usr/bin/env bash
# 50-isolate.sh — khoá victim về host-only: chỉ cho truy cập từ LAB_CIDR,
# chặn egress ra internet (app cố ý lỗ hổng không được "gọi về nhà").
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/config/versions.env"
[ "$(id -u)" -eq 0 ] || { echo "Cần root."; exit 1; }

# Tự dò CIDR host-only nếu chưa đặt.
if [ -z "${LAB_CIDR:-}" ]; then
  if [ -n "${BIND_IFACE:-}" ]; then
    LAB_CIDR="$(ip -o -f inet addr show "$BIND_IFACE" | awk '{print $4}' | head -n1)"
  else
    # đoán: interface KHÔNG mang default route (thường là host-only).
    DEFIF="$(ip route | awk '/^default/{print $5; exit}')"
    GUESS_IF="$(ip -o link show | awk -F': ' '{print $2}' | grep -v "$DEFIF" | grep -v '^lo$' | head -n1 || true)"
    [ -n "$GUESS_IF" ] && LAB_CIDR="$(ip -o -f inet addr show "$GUESS_IF" | awk '{print $4}' | head -n1)"
  fi
fi
[ -n "${LAB_CIDR:-}" ] || { echo "[!] Không xác định được LAB_CIDR. Đặt tay trong versions.env."; exit 1; }
echo "[*] LAB_CIDR = $LAB_CIDR"

# ufw: cho phép web + ssh TỪ lab, chặn mọi egress trừ DNS nội bộ.
apt-get install -y ufw >/dev/null
ufw --force reset >/dev/null
ufw default deny incoming
ufw default deny outgoing

# Vào: SSH + HTTP(80) + httpd-lab (8081) chỉ từ dải lab.
ufw allow from "$LAB_CIDR" to any port 22  proto tcp
ufw allow from "$LAB_CIDR" to any port 80  proto tcp
ufw allow from "$LAB_CIDR" to any port "$HTTPD_PORT" proto tcp

# Ra: cho Splunk forwarder tới indexer trong lab + DNS lab. Sửa cho đúng hạ tầng bạn.
ufw allow out to "$LAB_CIDR"
ufw allow out on lo

echo "[i] Mặc định CHẶN egress ra internet. Nếu Splunk indexer ngoài LAB_CIDR,"
echo "    thêm: ufw allow out to <indexer_ip> port <9997/8089 ...>"

ufw --force enable
ufw status verbose

echo "[+] Cô lập xong. Victim chỉ truy cập được trong $LAB_CIDR, không ra internet."
echo "    Verify: verify/checklist.sh"
