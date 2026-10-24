#!/usr/bin/env bash
# 20-wordpress.sh — tải + cài WordPress (pinned version) vào docroot.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/config/versions.env"
[ "$(id -u)" -eq 0 ] || { echo "Cần root."; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
TARBALL="wordpress-${WP_VERSION}.tar.gz"

echo "[*] Tải WordPress ${WP_VERSION} (pinned)…"
wget -q "https://wordpress.org/${TARBALL}" -O "$WORK/$TARBALL"

if [ -n "${WP_SHA256:-}" ]; then
  echo "${WP_SHA256}  $WORK/$TARBALL" | sha256sum -c - \
    || { echo "[!] SHA256 KHÔNG khớp — dừng."; exit 1; }
else
  echo "[i] WP_SHA256 trống — bỏ qua verify (nên điền để tái lập chặt)."
fi

mkdir -p "$(dirname "$WP_DOCROOT")"
rm -rf "$WP_DOCROOT"
tar xzf "$WORK/$TARBALL" -C "$WORK"
mv "$WORK/wordpress" "$WP_DOCROOT"

# wp-config.php từ sample.
CFG="$WP_DOCROOT/wp-config.php"
cp "$WP_DOCROOT/wp-config-sample.php" "$CFG"
sed -i "s/database_name_here/${DB_NAME}/"  "$CFG"
sed -i "s/username_here/${DB_USER}/"       "$CFG"
sed -i "s/password_here/${DB_PASS}/"       "$CFG"
sed -i "s/localhost/${DB_HOST}/"           "$CFG"

# Salts.
SALTS="$(curl -fsS https://api.wordpress.org/secret-key/1.1/salt/ || true)"
if [ -n "$SALTS" ]; then
  python3 - "$CFG" <<'PY' "$SALTS"
import sys, re
cfg = sys.argv[1]; salts = sys.argv[2]
txt = open(cfg).read()
txt = re.sub(r"define\( *'(AUTH_KEY|SECURE_AUTH_KEY|LOGGED_IN_KEY|NONCE_KEY|AUTH_SALT|SECURE_AUTH_SALT|LOGGED_IN_SALT|NONCE_SALT)'.*?\);\n", "", txt)
txt = txt.replace("/**#@-*/", salts + "\n/**#@-*/", 1)
open(cfg,"w").write(txt)
PY
fi

# Cho phép upload/edit để benign twin (media upload) chạy mượt.
grep -q "FS_METHOD" "$CFG" || sed -i "/That's all, stop editing/i define('FS_METHOD','direct');" "$CFG"

chown -R www-data:www-data "$WP_DOCROOT"
find "$WP_DOCROOT" -type d -exec chmod 755 {} \;
find "$WP_DOCROOT" -type f -exec chmod 644 {} \;

# Vhost tối giản (URL theo chức năng: /wordpress/…).
systemctl reload apache2 || systemctl restart apache2

echo "[+] WordPress ${WP_VERSION} đã giải nén vào ${WP_DOCROOT}."
echo "    Hoàn tất cài qua trình duyệt trong lab:"
echo "      http://<victim>${WP_URL_PATH}/wp-admin/install.php"
echo "    Sau đó seed vài bài viết để có nền benign (đọc bài, comment, search)."
echo "    Tiếp: install/30-wp-file-manager.sh"
