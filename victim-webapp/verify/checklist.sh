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
if curl -fsS "http://localhost${WP_URL_PATH}/" -o /dev/null; then
  pass "GET ${WP_URL_PATH}/ OK"
else
  fail "Không GET được ${WP_URL_PATH}/ (đã cài WP + hoàn tất install.php?)"
fi

echo "[2] mod_php (parent của webshell = apache2, không fpm)"
if apachectl -M 2>/dev/null | grep -qi 'php._module'; then
  pass "php_module đã load (mod_php)"
else
  fail "Không thấy php_module — process ancestry có thể lệch"
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
