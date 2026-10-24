#!/usr/bin/env python3
"""
benign_traffic.py — sinh luồng WordPress THẬT, lặp lại được, để làm nền đo false-positive.

Nhiều "user" (session riêng), timing ngẫu nhiên, URL theo chức năng:
đọc bài (/?p=), xem trang, search, mở wp-login.php, xen 404. Tất cả là hành vi
HỢP LỆ của người dùng thường — đây chính là nền để đo FP của detection.

Chạy từ một máy "user" trong lab, KHÔNG phải trên victim:
    python3 benign_traffic.py --base http://<victim>/wordpress --minutes 30 --users 5
"""
import argparse
import random
import sys
import time
from concurrent.futures import ThreadPoolExecutor

try:
    import requests
except ImportError:
    sys.exit("Cần: pip install -r requirements.txt")

UA_POOL = [
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.1 Safari/605.1.15",
]
SEARCH_TERMS = ["hello", "lab", "news", "update", "about", "guide", "security", "post"]


def one_visit(base, rng):
    """Một 'phiên đọc' của một user: xem home, vài bài, có khi search/login/404."""
    s = requests.Session()
    s.headers["User-Agent"] = rng.choice(UA_POOL)
    actions = []

    def get(path, **kw):
        try:
            r = s.get(base + path, timeout=10, allow_redirects=True, **kw)
            actions.append(f"{r.status_code} GET {path}")
        except requests.RequestException as e:
            actions.append(f"ERR GET {path} ({e.__class__.__name__})")

    get("/")                                   # home
    for _ in range(rng.randint(1, 4)):         # đọc vài bài
        get(f"/?p={rng.randint(1, 20)}")
        time.sleep(rng.uniform(0.3, 2.0))
    if rng.random() < 0.5:                      # search
        get("/", params={"s": rng.choice(SEARCH_TERMS)})
    if rng.random() < 0.3:                       # ghé trang login (không đăng nhập)
        get("/wp-login.php")
    if rng.random() < 0.2:                       # tự nhiên có 404
        get(f"/?p=999{rng.randint(0,9)}0000")
    if rng.random() < 0.2:                       # xem feed
        get("/?feed=rss2")
    return actions


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True, help="vd http://victim/wordpress")
    ap.add_argument("--minutes", type=float, default=15)
    ap.add_argument("--users", type=int, default=5, help="số 'user' song song")
    ap.add_argument("--seed", type=int, default=None)
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    base = a.base.rstrip("/")
    rng = random.Random(a.seed)

    deadline = time.time() + a.minutes * 60
    total = 0
    print(f"[*] Benign traffic → {base} trong {a.minutes} phút, {a.users} user song song")
    with ThreadPoolExecutor(max_workers=a.users) as pool:
        while time.time() < deadline:
            futs = [pool.submit(one_visit, base, random.Random(rng.random()))
                    for _ in range(a.users)]
            for f in futs:
                acts = f.result()
                total += len(acts)
                if a.verbose:
                    print("   " + " | ".join(acts))
            time.sleep(rng.uniform(1.0, 5.0))   # giãn cách giữa các đợt
    print(f"[+] Xong. ~{total} request hợp lệ đã sinh (nền FP). index={'lab_web'}")


if __name__ == "__main__":
    main()
