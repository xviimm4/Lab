# victim-webapp — WordPress victim lab (detection / FP research)

Package để triển khai **web application victim** trên một **Ubuntu VM đã dựng sẵn**
(OS, auditd, journald, Splunk UF/forwarding đã có). Mục tiêu:

1. **Initial-access chokepoint** — mỗi lần khai thác thành công đều sinh chuỗi
   `apache2/httpd (www-data) → sh/…` để auditd bắt được.
2. **Benign traffic + benign twin** — nền web traffic thật để đo **false positive**.
3. **Tái lập được** — pin version WordPress / plugin / Apache kèm **CVE ID**.

> ⚠️ **SCOPE & AN TOÀN**
> - Chỉ chạy trong mạng **host-only / internal**. **KHÔNG expose** ra internet hay LAN thật.
> - Mọi lỗ hổng là **CVE công khai đã tài liệu hoá** — đây là *emulation* kỹ thuật đã công bố,
>   không phát triển exploit mới.
> - Deploy trên **VM dùng một lần** (snapshot trước khi chạy, revert sau khi đo).
> - **KHÔNG** chạy trên máy dev/máy này. Package chỉ để copy sang Ubuntu victim.

---

## Thành phần

```
victim-webapp/
├── README.md                  ← bạn đang đọc
├── config/
│   └── versions.env           ← pin version + CVE ID (nguồn chân lý)
├── install/
│   ├── 00-preflight.sh        ← kiểm tra host-only, snapshot reminder
│   ├── 10-stack.sh            ← apache2 + mod_php + mysql + php
│   ├── 20-wordpress.sh        ← tải + cài WordPress (pinned)
│   ├── 30-wp-file-manager.sh  ← plugin WP File Manager 6.0 (CVE-2020-25213) → V1
│   ├── 40-apache-2449.sh      ← build Apache 2.4.49 (CVE-2021-41773) → V2/V3
│   └── 50-isolate.sh          ← firewall host-only, chặn egress
├── benign/
│   ├── requirements.txt
│   ├── benign_traffic.py      ← traffic WP thật, nhiều "user", timing ngẫu nhiên
│   └── benign_twin.py         ← upload media hợp lệ / admin edit (twin của attack)
├── attack-sim/                ← trigger sinh telemetry (chạy từ máy attacker trong lab)
│   ├── v1_upload_webshell.sh  ← CVE-2020-25213
│   ├── v2_apache_cgi_rce.sh   ← CVE-2021-41773 (traversal → mod_cgi exec)
│   ├── v3_traversal_read.sh   ← CVE-2021-41773 (path traversal read)
│   └── lab-marker.php         ← payload lab tối giản (xem file để biết giới hạn)
├── verify/
│   └── checklist.sh           ← kiểm apache→shell, log forward, độ khó
└── teardown.sh                ← gỡ sạch (hoặc revert snapshot)
```

---

## Quy trình chạy (trên Ubuntu victim)

```bash
# 0. Snapshot VM trước. Rồi copy cả thư mục này sang victim, ví dụ /opt/victim-webapp
sudo bash install/00-preflight.sh        # xác nhận host-only + nhắc snapshot
sudo bash install/10-stack.sh
sudo bash install/20-wordpress.sh
sudo bash install/30-wp-file-manager.sh  # bật V1 (có thể tắt để đổi độ khó)
sudo bash install/40-apache-2449.sh      # bật V2/V3 trên cổng phụ 8081
sudo bash install/50-isolate.sh          # khoá host-only + chặn ra ngoài
```

Hoàn tất cài WP qua trình duyệt trong lab: `http://<victim>/wordpress/wp-admin/install.php`
(thông tin DB ở `config/versions.env`). Sau đó seed vài bài viết để có nền benign.

### Sinh benign traffic (nền đo FP) — chạy từ máy "user" trong lab
```bash
pip install -r benign/requirements.txt
python3 benign/benign_traffic.py --base http://<victim>/wordpress --minutes 30
python3 benign/benign_twin.py     --base http://<victim>/wordpress --user admin --pass <pw>
```

### Trigger attack (sinh telemetry) — chạy từ máy "attacker" trong lab
```bash
bash attack-sim/v1_upload_webshell.sh http://<victim>
bash attack-sim/v2_apache_cgi_rce.sh  http://<victim>:8081
bash attack-sim/v3_traversal_read.sh  http://<victim>:8081
```

### Verify
```bash
sudo bash verify/checklist.sh
```

---

## Map 3 biến thể initial access

| Biến thể | CVE | Đường trên lab | Chokepoint sinh ra |
| --- | --- | --- | --- |
| **V1** File upload → webshell | **CVE-2020-25213** (WP File Manager 6.0) | upload PHP vào `wp-content/plugins/wp-file-manager/lib/files/` | `apache2(www-data) → sh` khi gọi webshell |
| **V2** Command exec / RCE | **CVE-2021-41773** (Apache 2.4.49, mod_cgi) | traversal tới `/bin/sh` qua cgi | `httpd(www-data) → sh` |
| **V3** LFI / path-traversal | **CVE-2021-41773** (hoặc CVE-2021-42013 / 2.4.50) | đọc file ngoài docroot | đọc file nhạy cảm, tiền đề log-poisoning |

## Điều chỉnh độ khó qua các vòng
WordPress không có "security level" như DVWA. Thay bằng:
- **Tắt/bật** plugin lỗ hổng (`wp plugin deactivate wp-file-manager`).
- **Nâng version** plugin/WP/Apache (vá dần) — sửa `config/versions.env` rồi cài lại.
- Thêm WAF nhẹ (ModSecurity CRS) để chứng minh detection bám **hành vi**, không bám signature.

Chi tiết: xem `config/versions.env` và từng script.
