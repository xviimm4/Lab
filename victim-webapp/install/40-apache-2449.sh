#!/usr/bin/env bash
# 40-apache-2449.sh — build Apache httpd 2.4.49 từ source cho V2/V3 (CVE-2021-41773).
#
# Tại sao build riêng, nghe cổng phụ 8081:
#   - apache2 của distro (đã vá) vẫn phục vụ WordPress + benign + V1 (mod_php, www-data).
#   - httpd 2.4.49 tách ra để tái hiện traversal→read (V3) và traversal→mod_cgi exec (V2).
#   - CHẠY DƯỚI www-data → chokepoint `httpd(www-data) → sh` giống hệt apache2.
#
# Cấu hình lỗ hổng đúng như CVE-2021-41773 công bố:
#   - `Require all granted` trên <Directory /> (misconfig cần thiết cho traversal).
#   - mod_cgi + ScriptAlias /cgi-bin/ để nhánh V2 (exec) hoạt động.
# Đây là tái lập cấu hình đã tài liệu hoá, không phải exploit mới.
#
# Vòng khó hơn: đổi HTTPD_VERSION=2.4.50 + CVE-2021-42013 (double-encoding).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/config/versions.env"
[ "$(id -u)" -eq 0 ] || { echo "Cần root."; exit 1; }

export DEBIAN_FRONTEND=noninteractive
# Lưu ý: KHÔNG cài libpcre3-dev — Ubuntu mới đã bỏ gói này (PCRE1). Ta build PCRE1 từ source bên dưới.
# libexpat1-dev: apr-util cần expat để build phần XML (nếu thiếu → fatal error: expat.h).
apt-get install -y build-essential wget libssl-dev libexpat1-dev tar

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

# apr/apr-util (2021) trên gcc mới sinh RẤT nhiều warning vô hại → tắt (-w) cho output sạch.
# KHÔNG tắt lỗi thật; chỉ ẩn warning. Đừng Ctrl+C khi thấy log trôi — nó đang compile.
export CFLAGS="${CFLAGS:-} -O2 -w"

echo "[*] Tải nguồn httpd ${HTTPD_VERSION} + apr ${APR_VERSION} + apr-util ${APR_UTIL_VERSION} + pcre ${PCRE_VERSION}…"
# Mirror archive (bản cũ không còn ở mirror chính).
wget -q "https://archive.apache.org/dist/httpd/httpd-${HTTPD_VERSION}.tar.gz"
wget -q "https://archive.apache.org/dist/apr/apr-${APR_VERSION}.tar.gz"
wget -q "https://archive.apache.org/dist/apr/apr-util-${APR_UTIL_VERSION}.tar.gz"
# PCRE1 (httpd 2.4.49 cần pcre-config, không nhận PCRE2 của hệ thống).
wget -q "https://downloads.sourceforge.net/project/pcre/pcre/${PCRE_VERSION}/pcre-${PCRE_VERSION}.tar.gz" \
     -O "pcre-${PCRE_VERSION}.tar.gz"

# Build + cài PCRE1 vào chính prefix của httpd (teardown xoá cùng $HTTPD_PREFIX).
echo "[*] Build PCRE1 ${PCRE_VERSION}…"
tar xzf "pcre-${PCRE_VERSION}.tar.gz"
( cd "pcre-${PCRE_VERSION}" \
  && ./configure --prefix="$HTTPD_PREFIX" --disable-cpp >/dev/null \
  && make -j"$(nproc)" >/dev/null \
  && make install >/dev/null )

tar xzf "httpd-${HTTPD_VERSION}.tar.gz"
tar xzf "apr-${APR_VERSION}.tar.gz"
tar xzf "apr-util-${APR_UTIL_VERSION}.tar.gz"
mv "apr-${APR_VERSION}"       "httpd-${HTTPD_VERSION}/srclib/apr"
mv "apr-util-${APR_UTIL_VERSION}" "httpd-${HTTPD_VERSION}/srclib/apr-util"

cd "httpd-${HTTPD_VERSION}"
echo "[*] configure + make (có thể vài phút)…"
# --disable-ssl: httpd 2.4.49 mod_ssl dùng ERR_GET_FUNC — đã bị gỡ ở OpenSSL 3.x (Ubuntu mới),
# gây lỗi build. Lab traversal chạy HTTP thuần cổng 8081 nên không cần mod_ssl.
./configure --prefix="$HTTPD_PREFIX" --enable-cgi --with-included-apr --disable-ssl \
            --with-pcre="$HTTPD_PREFIX/bin/pcre-config" >/dev/null
make -j"$(nproc)" >/dev/null
make install >/dev/null

# Cho runtime linker thấy libpcre.so trong prefix (tránh lỗi "cannot open shared object" khi start).
echo "$HTTPD_PREFIX/lib" > /etc/ld.so.conf.d/httpd-lab.conf
ldconfig

CONF="$HTTPD_PREFIX/conf/httpd.conf"

# Nghe cổng phụ.
sed -i "s/^Listen .*/Listen ${HTTPD_PORT}/" "$CONF"

# Chạy dưới www-data (giống apache2) → ancestry đồng nhất khi so telemetry.
sed -i 's/^User .*/User www-data/'  "$CONF"
sed -i 's/^Group .*/Group www-data/' "$CONF"

# Bật mod_cgi/mod_cgid nếu bị comment (nhánh V2 exec).
# Lưu ý: trong httpd.conf chuẩn, 2 dòng này nằm trong <IfModule mpm_*> và thụt đầu bằng TAB,
# nên pattern '^#' KHÔNG khớp. Phải cho phép khoảng trắng đầu dòng ([[:space:]]*).
# Bỏ comment cả hai — guard <IfModule> đảm bảo chỉ module khớp MPM thực sự load.
sed -i -E 's|^([[:space:]]*)#(LoadModule cgid?_module .*)|\1\2|' "$CONF" || true

# Misconfig lỗ hổng đúng như CVE-2021-41773 (require all granted trên /).
cat >> "$CONF" <<EOF

# ---- LAB (CVE-2021-41773) — CỐ Ý misconfig, chỉ host-only ----
<Directory />
    AllowOverride none
    Require all granted
</Directory>
# ScriptAlias (cgi-handler) → nhánh V2: traversal ra /bin/sh rồi mod_cgi EXEC.
ScriptAlias /cgi-bin/ "${HTTPD_PREFIX}/cgi-bin/"
# plain Alias (KHÔNG cgi-handler) → nhánh V3: traversal ra /etc/passwd rồi READ.
# Cần Alias riêng vì qua ScriptAlias thì file bị đem đi exec (500), không đọc được.
Alias /docs/ "${HTTPD_PREFIX}/htdocs/"
# -------------------------------------------------------------
EOF
mkdir -p "$HTTPD_PREFIX/cgi-bin"
chown -R www-data:www-data "$HTTPD_PREFIX/logs" "$HTTPD_PREFIX/cgi-bin" 2>/dev/null || true

# systemd unit để journald/Splunk thu log như service thật.
cat > /etc/systemd/system/httpd-lab.service <<EOF
[Unit]
Description=LAB Apache httpd ${HTTPD_VERSION} (${HTTPD_CVE}) — host-only only
After=network.target
[Service]
Type=forking
ExecStart=${HTTPD_PREFIX}/bin/apachectl start
ExecStop=${HTTPD_PREFIX}/bin/apachectl stop
ExecReload=${HTTPD_PREFIX}/bin/apachectl graceful
PIDFile=${HTTPD_PREFIX}/logs/httpd.pid
[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now httpd-lab.service

echo "[+] httpd ${HTTPD_VERSION} (${HTTPD_CVE}) chạy ở cổng ${HTTPD_PORT}, user www-data."
echo "    V2/V3 trỏ vào http://<victim>:${HTTPD_PORT}"
echo "    Tắt khi đổi độ khó: systemctl stop httpd-lab"
echo "    Tiếp: install/50-isolate.sh"
