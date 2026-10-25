#!/usr/bin/env bash
# checklist.sh — verify web app (mục 4 của yêu cầu). Chạy trên VICTIM (root).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$HERE/config/versions.env"

pass(){ printf '  \033[32m[PASS]\033[0m %s\n' "$*"; }
fail(){ printf '  \033[31m[FAIL]\033[0m %s\n' "$*"; }
info(){ printf '  \033[33m[ .. ]\033[0m %s\n' "$*"; }

echo "=== verify victim-webapp ==="

echo "[1] WordPress chạy + truy cập được"
# Không dùng -f (nó nuốt mất lý do): bắt mã HTTP + curl exit code để chỉ rõ nguyên nhân.
# -L theo redirect để thấy mã cuối cùng (vd siteurl trỏ IP khác → 301).
WP_HTTP="$(curl -sS -L -o /dev/null -w '%{http_code}' "http://localhost${WP_URL_PATH}/" 2>/dev/null)"
CURL_RC=$?
if [ "$CURL_RC" -ne 0 ] || [ "$WP_HTTP" = "000" ]; then
  fail "Không KẾT NỐI được http://localhost${WP_URL_PATH}/ (curl rc=$CURL_RC) — apache2 chạy chưa? (systemctl status apache2)"
elif [ "$WP_HTTP" -ge 200 ] && [ "$WP_HTTP" -lt 400 ]; then
  pass "GET ${WP_URL_PATH}/ OK (HTTP $WP_HTTP)"
else
  fail "GET ${WP_URL_PATH}/ → HTTP $WP_HTTP  (500=lỗi DB/wp-config; 404=sai path/WP_URL_PATH; 403=quyền)"
fi

echo "[2] mod_php (parent của webshell = apache2, không fpm)"
# Điều quyết định ancestry là: PHP chạy IN-PROCESS trong apache2 (mod_php), KHÔNG qua php-fpm.
# Lưu ý: 'apache2ctl -M | grep php_module' không đáng tin — một số bản (php8.5 trên Ubuntu mới)
# mod_php load nhưng không in ra dòng 'php_module', gây false-negative. Dò qua nhiều nguồn.
PHP_VIA_FPM=0
apache2ctl -M 2>/dev/null | grep -qi 'proxy_fcgi_module' && PHP_VIA_FPM=1
systemctl is-active --quiet 'php*-fpm.service' 2>/dev/null && PHP_VIA_FPM=1
MODPHP=0
if command -v a2query >/dev/null 2>&1 && a2query -m 2>/dev/null | grep -qiE '^php'; then MODPHP=1
elif ls /etc/apache2/mods-enabled/ 2>/dev/null | grep -qiE '^php.*\.load'; then MODPHP=1
elif apache2ctl -M 2>/dev/null | grep -qi 'php._module'; then MODPHP=1
fi
if [ "$MODPHP" -eq 1 ] && [ "$PHP_VIA_FPM" -eq 0 ]; then
  pass "mod_php đã load, không dùng php-fpm (ancestry apache2→sh giữ nguyên)"
elif [ "$MODPHP" -eq 1 ] && [ "$PHP_VIA_FPM" -eq 1 ]; then
  fail "mod_php có nhưng php-fpm cũng active — ancestry có thể lệch (parent = php-fpm)"
else
  fail "Không thấy mod_php — kiểm libapache2-mod-php + a2enmod"
fi

echo "[3] V1 plugin WP File Manager ${WPFM_VERSION} (${WPFM_CVE})"
if [ -f "${WP_DOCROOT}/wp-content/plugins/${WPFM_SLUG}/lib/php/connector.minimal.php" ]; then
  pass "connector.minimal.php tồn tại (V1 sẵn sàng khi plugin active)"
else
  info "Chưa thấy connector — chạy install/30 hoặc đã gỡ để đổi độ khó"
fi

echo "[4] V2/V3 httpd ${HTTPD_VERSION} (${HTTPD_CVE}) ở cổng ${HTTPD_PORT}"
if systemctl is-active --quiet httpd-lab 2>/dev/null; then
  VER=$("${HTTPD_PREFIX}/bin/httpd" -v 2>/dev/null | head -n1)
  pass "httpd-lab active — $VER"
  "${HTTPD_PREFIX}/bin/apachectl" -M 2>/dev/null | grep -qi cgi \
    && pass "mod_cgi loaded (V2 exec khả dụng)" \
    || info "mod_cgi chưa load (V2 exec sẽ không chạy; V3 read vẫn OK)"
else
  info "httpd-lab không chạy — chạy install/40 hoặc đã stop để đổi độ khó"
fi

echo "[5] Chokepoint apache→shell có được auditd bắt?"
if command -v ausearch >/dev/null 2>&1; then
  N=$(ausearch -m EXECVE -ts recent 2>/dev/null | grep -Ei 'apache2|httpd|/sh|/bash' | wc -l)
  if [ "$N" -gt 0 ]; then pass "auditd thấy $N dòng execve liên quan (chạy attack-sim trước đó)"
  else info "Chưa thấy execve apache→shell gần đây — chạy attack-sim/v1 hoặc v2 rồi verify lại"; fi
else
  info "ausearch không có trên host này (auditd đã dựng theo mô tả — kiểm thủ công)"
fi

echo "[6] Access/error log sinh ra"
for L in /var/log/apache2/access.log "${HTTPD_PREFIX}/logs/access_log"; do
  [ -s "$L" ] && pass "log có dữ liệu: $L" || info "log trống/không có: $L"
done
info "Xác nhận đã forward lên Splunk index=${WEB_INDEX} (cấu hình UF đã có sẵn)"

echo "[7] Cô lập host-only + không egress"
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
  pass "ufw active"
  ufw status verbose 2>/dev/null | grep -q 'deny (outgoing)' \
    && pass "default deny outgoing (không gọi internet)" \
    || info "egress chưa deny-all — kiểm install/50"
else
  fail "ufw chưa active — chạy install/50-isolate.sh"
fi

echo "[8] Pin version + CVE (reproducibility)"
pass "WP=${WP_VERSION} | WPFM=${WPFM_VERSION}/${WPFM_CVE} | httpd=${HTTPD_VERSION}/${HTTPD_CVE}"
info "Chép dòng trên vào báo cáo (realism + reproducibility)."

echo "=== hết ==="
