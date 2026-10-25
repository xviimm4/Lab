#!/usr/bin/env bash
# 50-isolate.sh — giới hạn INGRESS về LAB_CIDR (chỉ cho truy cập từ dải lab).
# Egress để mở: lab local, tự tấn công trên máy — không chặn internet của host.
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

# ufw: chỉ giới hạn INGRESS web + ssh về dải lab. Egress để MỞ:
# đây là lab local (tự tấn công trên chính máy), không phải victim cô lập cần chặn "call home",
# nên chặn outbound chỉ làm hỏng apt/update/Splunk của chính host.
apt-get install -y ufw >/dev/null
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing

# Vào: SSH + HTTP(80) + httpd-lab (8081) chỉ từ dải lab.
ufw allow from "$LAB_CIDR" to any port 22  proto tcp
ufw allow from "$LAB_CIDR" to any port 80  proto tcp
ufw allow from "$LAB_CIDR" to any port "$HTTPD_PORT" proto tcp

echo "[i] Egress để MỞ (lab local). Nếu cần biến thành victim cô lập thật,"
echo "    đổi lại: ufw default deny outgoing + allow out tới LAB_CIDR/indexer."

ufw --force enable
ufw status verbose

echo "[+] Xong. Ingress giới hạn trong $LAB_CIDR; egress mở (internet dùng bình thường)."
echo "    Verify: verify/checklist.sh"
