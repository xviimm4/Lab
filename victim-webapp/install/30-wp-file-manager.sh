#!/usr/bin/env bash
# 30-wp-file-manager.sh — cài WP File Manager 6.0 (CVE-2020-25213) cho V1.
#
# Bản chất lỗ hổng (đã công bố): plugin ship kèm elFinder; file connector
# lib/php/connector.minimal.php để lộ lệnh `upload` không xác thực, cho phép
# ghi file tuỳ ý vào lib/files/. Đây là CVE công khai — ta chỉ PIN version
# lỗ hổng để tái lập, không viết exploit mới.
#
# Đổi độ khó: cài version đã vá (>=6.9) hoặc deactivate plugin.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/config/versions.env"
[ "$(id -u)" -eq 0 ] || { echo "Cần root."; exit 1; }

PLUGDIR="${WP_DOCROOT}/wp-content/plugins"
DEST="${PLUGDIR}/${WPFM_SLUG}"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "[*] Tải ${WPFM_SLUG} ${WPFM_VERSION} (${WPFM_CVE}) từ kho svn chính thức…"
# Kho plugin WordPress giữ mọi version cũ — pin bản lỗ hổng để tái lập.
ZIP="$WORK/wpfm.zip"
if ! wget -q "https://downloads.wordpress.org/plugin/${WPFM_SLUG}.${WPFM_VERSION}.zip" -O "$ZIP"; then
  echo "[!] Không tải được bản ${WPFM_VERSION}."
  echo "    Lấy thủ công từ: https://plugins.trac.wordpress.org/browser/${WPFM_SLUG}/tags"
  echo "    rồi đặt zip vào $ZIP và chạy lại."
  exit 1
fi

mkdir -p "$PLUGDIR"
rm -rf "$DEST"
unzip -q "$ZIP" -d "$PLUGDIR"

# Một số bản phân phối (vd 6.0) là ZIP-LỒNG: zip ngoài bung ra lại chứa một zip nữa
# (wp-file-manager-*.zip) thay vì file PHP. Nếu sau khi unzip mà chưa thấy connector,
# dò zip lồng bên trong $DEST và bung tiếp vào $PLUGDIR, rồi xoá zip lồng đi.
if [ ! -f "$DEST/lib/php/connector.minimal.php" ]; then
  INNER="$(find "$DEST" -maxdepth 2 -iname '*.zip' | head -n1)"
  if [ -n "$INNER" ]; then
    echo "[*] Phát hiện zip lồng: $(basename "$INNER") → bung tiếp…"
    unzip -oq "$INNER" -d "$PLUGDIR"
    rm -f "$INNER"
  fi
fi
# Chốt: connector phải tồn tại, nếu không thì dừng để khỏi tưởng nhầm là đã cài xong.
[ -f "$DEST/lib/php/connector.minimal.php" ] || {
  echo "[!] Không thấy lib/php/connector.minimal.php sau khi giải nén — plugin chưa đúng."
  echo "    Kiểm tra zip tải về: $ZIP"
  exit 1
}

# Thư mục files/ là nơi elFinder ghi upload — chokepoint của V1.
mkdir -p "$DEST/lib/files"
chown -R www-data:www-data "$DEST"

echo "[+] Đã đặt ${WPFM_SLUG} ${WPFM_VERSION} vào ${DEST}"
echo "    Kích hoạt plugin: WP-Admin → Plugins → Activate 'WP File Manager'"
echo "    (hoặc wp-cli: wp plugin activate ${WPFM_SLUG} --path=${WP_DOCROOT})"
echo
echo "    ĐỔI ĐỘ KHÓ:"
echo "      - Tắt V1 : wp plugin deactivate ${WPFM_SLUG} --path=${WP_DOCROOT}"
echo "      - Vá     : cài lại với WPFM_VERSION=6.9 trong versions.env"
echo "    Tiếp: install/40-apache-2449.sh"
