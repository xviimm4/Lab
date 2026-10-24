#!/usr/bin/env bash
# 10-stack.sh — Apache2 + mod_php + MySQL + PHP.
# Dùng mod_php (KHÔNG php-fpm) để parent của webshell là apache2 → process ancestry gọn,
# đúng chokepoint `apache2(www-data) → sh` mà auditd đã bắt.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/config/versions.env"
[ "$(id -u)" -eq 0 ] || { echo "Cần root."; exit 1; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
  apache2 php libapache2-mod-php php-mysql php-curl php-gd php-xml php-mbstring \
  mysql-server wget curl unzip ca-certificates

# Bảo đảm dùng prefork + mod_php (không event/fpm).
a2dismod mpm_event  2>/dev/null || true
a2enmod  mpm_prefork
a2enmod  php*        2>/dev/null || true
a2enmod  rewrite

systemctl enable --now mysql
systemctl enable --now apache2

# Tạo DB + user cho WordPress (local only).
mysql --protocol=socket <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
SQL

# MySQL chỉ nghe localhost (không expose DB).
BINDCONF=/etc/mysql/mysql.conf.d/mysqld.cnf
if [ -f "$BINDCONF" ] && ! grep -q '^bind-address.*127.0.0.1' "$BINDCONF"; then
  sed -i 's/^bind-address.*/bind-address = 127.0.0.1/' "$BINDCONF" || true
  systemctl restart mysql
fi

echo "[+] Stack xong. DB=${DB_NAME} user=${DB_USER} (pass trong versions.env)."
echo "    Confirm mod_php: $(apachectl -M 2>/dev/null | grep -i php || echo 'KHÔNG thấy php_module!')"
echo "    Tiếp: install/20-wordpress.sh"
