#!/usr/bin/env bash
# install-all.sh — chạy tuần tự toàn bộ các bước cài đặt victim-webapp.
#
# Dùng:
#   sudo bash install/install-all.sh                  # chạy đủ (00-preflight → 50)
#   sudo bash install/install-all.sh --skip-preflight # chỉ 5 bước install (10 → 50)
#
# Chạy mọi script install/NN-*.sh theo đúng thứ tự số, DỪNG NGAY nếu một bước fail
# (set -e). 00-preflight có prompt xác nhận snapshot/cô lập — trả lời khi được hỏi.
# Tất cả bước con đều cần root → chạy script này bằng sudo để truyền quyền xuống.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "[!] Cần root. Chạy: sudo bash $0"; exit 1; }

SKIP_PREFLIGHT=0
[ "${1:-}" = "--skip-preflight" ] && SKIP_PREFLIGHT=1

# Thu thập các bước theo thứ tự số (glob NN-*.sh tự sort). Script này tên không khớp
# mẫu NN-* nên không tự gọi chính nó.
STEPS=()
for f in "$HERE"/[0-9]*.sh; do
  base="$(basename "$f")"
  if [ "$SKIP_PREFLIGHT" -eq 1 ] && [[ "$base" == 00-* ]]; then
    echo "[i] Bỏ qua $base (--skip-preflight)"
    continue
  fi
  STEPS+=("$f")
done

[ "${#STEPS[@]}" -gt 0 ] || { echo "[!] Không tìm thấy bước install nào trong $HERE"; exit 1; }

echo "[*] Sẽ chạy ${#STEPS[@]} bước theo thứ tự:"
for f in "${STEPS[@]}"; do echo "      - $(basename "$f")"; done
echo

i=0
for f in "${STEPS[@]}"; do
  i=$((i + 1))
  echo "────────────────────────────────────────────────────────"
  echo "[$i/${#STEPS[@]}] ▶ $(basename "$f")"
  echo "────────────────────────────────────────────────────────"
  bash "$f"
  echo "[✓] $(basename "$f") xong."
  echo
done

echo "[+] Hoàn tất toàn bộ cài đặt (${#STEPS[@]} bước)."
echo "    Kiểm tra: sudo bash verify/checklist.sh"
