#!/usr/bin/env bash
# teardown.sh — gỡ web app victim. Khuyến nghị: REVERT SNAPSHOT thay vì gỡ tay.
# Chạy trên victim (root).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/config/versions.env"
[ "$(id -u)" -eq 0 ] || { echo "Cần root."; exit 1; }

echo "[!] Cách SẠCH NHẤT là revert VM snapshot. teardown.sh chỉ gỡ best-effort."
read -r -p "Tiếp tục gỡ thủ công? [type: yes] " a; [ "$a" = "yes" ] || exit 0

# httpd-lab (2.4.49).
systemctl stop httpd-lab 2>/dev/null || true
systemctl disable httpd-lab 2>/dev/null || true
rm -f /etc/systemd/system/httpd-lab.service
systemctl daemon-reload 2>/dev/null || true
rm -rf "$HTTPD_PREFIX"
rm -f /etc/ld.so.conf.d/httpd-lab.conf && ldconfig 2>/dev/null || true

# WordPress + payload V1.
rm -rf "$WP_DOCROOT"

# DB.
mysql --protocol=socket -e "DROP DATABASE IF EXISTS \`${DB_NAME}\`; DROP USER IF EXISTS '${DB_USER}'@'${DB_HOST}';" 2>/dev/null || true

echo "[+] Đã gỡ httpd-lab, WordPress, DB. ufw rules giữ nguyên — reset nếu muốn:"
echo "    ufw --force reset"
echo "[i] apache2/php/mysql của distro KHÔNG bị gỡ (dùng apt purge nếu cần)."
