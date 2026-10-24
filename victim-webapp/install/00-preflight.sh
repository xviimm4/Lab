#!/usr/bin/env bash
# 00-preflight.sh — xác nhận đây là VM lab cô lập trước khi cài gì cố ý lỗ hổng.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/config/versions.env"

red(){ printf '\033[31m%s\033[0m\n' "$*"; }
grn(){ printf '\033[32m%s\033[0m\n' "$*"; }
ylw(){ printf '\033[33m%s\033[0m\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { red "Chạy bằng sudo/root."; exit 1; }

ylw "=== PREFLIGHT: victim-webapp (lab cố ý lỗ hổng) ==="
echo "Hostname : $(hostname)"
echo "OS       : $(. /etc/os-release && echo "$PRETTY_NAME")"
echo "IPs      :"; ip -brief addr | sed 's/^/           /'

# 1) Không cho chạy nếu có default route ra internet mà không xác nhận.
if ip route | grep -q '^default'; then
  GW=$(ip route | awk '/^default/{print $3; exit}')
  ylw "Có default route (gw $GW). App này KHÔNG được expose ra ngoài."
  ylw "50-isolate.sh sẽ chặn egress; nhưng hãy chắc VM đang ở network host-only/internal."
fi

# 2) Nhắc snapshot.
red "LƯU Ý: Đây là web app CỐ Ý LỖ HỔNG (CVE công khai)."
red "       - Chỉ dùng trên VM host-only/internal, dùng-một-lần."
red "       - Hãy SNAPSHOT VM ngay bây giờ nếu chưa."
read -r -p "VM đã snapshot và đang ở network cô lập? [type: yes] " ans
[ "$ans" = "yes" ] || { red "Dừng. Snapshot + cô lập mạng trước đã."; exit 1; }

# 3) Cảnh báo nếu phát hiện đang ở máy có vẻ là workstation (có GUI dev).
if command -v code >/dev/null 2>&1 || [ -d /home/*/.vscode 2>/dev/null ]; then
  ylw "Phát hiện dấu hiệu máy dev. Chắc chắn đây KHÔNG phải máy làm việc của bạn?"
  read -r -p "Vẫn tiếp tục? [type: yes] " a2
  [ "$a2" = "yes" ] || exit 1
fi

grn "Preflight OK. Tiếp: install/10-stack.sh"
