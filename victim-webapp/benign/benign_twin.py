#!/usr/bin/env python3
"""
benign_twin.py — "benign twin" của các biến thể attack: CÙNG hành vi bề mặt,
KHÁC bản chất. Mục đích: ép detection phân biệt bằng hành vi, không bằng URL/signature.

  - Twin của V1 (upload webshell) : đăng nhập wp-admin, upload .jpg hợp lệ qua Media Library.
  - Twin của "admin khai thác"     : admin chỉnh nội dung hợp lệ (tạo/sửa bài qua REST).

Chạy từ máy "user/admin" trong lab:
    python3 benign_twin.py --base http://<victim>/wordpress --user admin --pass '<pw>'
"""
import argparse
import io
import sys
import struct
import zlib

try:
    import requests
except ImportError:
    sys.exit("Cần: pip install -r requirements.txt")


def tiny_png():
    """Sinh 1 PNG 1x1 hợp lệ trong bộ nhớ (không cần file ngoài)."""
    def chunk(typ, data):
        c = typ + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    raw = b"\x00\xff\xff\xff"
    idat = chunk(b"IDAT", zlib.compress(raw))
    iend = chunk(b"IEND", b"")
    return sig + ihdr + idat + iend


def login(s, base, user, pw):
    """Đăng nhập wp-login.php như người dùng thật (lấy cookie)."""
    s.get(base + "/wp-login.php", timeout=10)
    r = s.post(base + "/wp-login.php",
               data={"log": user, "pwd": pw, "wp-submit": "Log In",
                     "redirect_to": base + "/wp-admin/", "testcookie": "1"},
               timeout=10, allow_redirects=True)
    ok = "dashboard" in r.text.lower() or "wp-admin" in r.url
    print(f"[{'+' if ok else '!'}] login {user}: {'ok' if ok else 'FAIL (kiểm pass)'}")
    return ok


def upload_media(s, base):
    """Twin của V1: upload ẢNH HỢP LỆ qua Media Library (async-upload.php)."""
    # Lấy nonce media từ trang upload.
    html = s.get(base + "/wp-admin/media-new.php", timeout=10).text
    import re
    m = re.search(r'name="_wpnonce"\s+value="([a-f0-9]+)"', html) or \
        re.search(r'"_wpnonce":"([a-f0-9]+)"', html) or \
        re.search(r'media-form.*?nonce.*?"([a-f0-9]+)"', html)
    nonce = m.group(1) if m else ""
    png = tiny_png()
    files = {"async-upload": ("lab_benign.png", io.BytesIO(png), "image/png")}
    data = {"name": "lab_benign.png", "action": "upload-attachment", "_wpnonce": nonce}
    r = s.post(base + "/wp-admin/async-upload.php", files=files, data=data, timeout=15)
    ok = r.status_code == 200 and '"success":true' in r.text
    print(f"[{'+' if ok else '!'}] upload media .png hợp lệ: HTTP {r.status_code} "
          f"{'(success)' if ok else '(xem quyền/nonce)'}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--user", required=True)
    ap.add_argument("--pass", dest="pw", required=True)
    a = ap.parse_args()
    base = a.base.rstrip("/")
    s = requests.Session()
    s.headers["User-Agent"] = "Mozilla/5.0 (benign-twin lab)"
    if login(s, base, a.user, a.pw):
        upload_media(s, base)
    print("[i] Đây là hành vi upload HỢP LỆ — twin của V1. "
          "Detection không nên báo động cái này (đo FP).")


if __name__ == "__main__":
    main()
