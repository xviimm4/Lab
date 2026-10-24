<?php
/**
 * lab-marker.php — PAYLOAD LAB TỐI GIẢN cho V1 (CVE-2020-25213).
 *
 * MỤC ĐÍCH: khi file này được gọi, PHP (chạy dưới www-data trong apache2) sẽ
 * spawn tiến trình con shell để chạy một BỘ LỆNH RECON CỐ ĐỊNH, LÀNH TÍNH.
 * Đó chính là chokepoint `apache2(www-data) → sh → id/uname/...` mà auditd + detection
 * cần bắt được. Telemetry sinh ra giống hệt hành vi hậu-khai-thác điển hình.
 *
 * GIỚI HẠN CÓ CHỦ Ý (để an toàn, đây là artifact lab chứ không phải webshell dùng chung):
 *   - KHÔNG nhận lệnh tuỳ ý từ $_GET/$_POST. Chỉ chạy allow-list recon lành tính.
 *   - Không mạng, không ghi đè file hệ thống, không leo thang.
 * Nếu vòng thử cần phủ rộng hơn, chỉnh allow-list NGAY TẠI ĐÂY, trong lab cô lập.
 *
 * Nhận diện file: để một marker rõ ràng cho blue team dễ truy vết.
 */
header("X-Lab-Marker: victim-webapp CVE-2020-25213 V1");

$ALLOW = array(
    "id",
    "whoami",
    "uname -a",
    "hostname",
);

echo "== victim-webapp lab marker (V1) ==\n";
echo "uid php     : " . (function_exists('posix_getuid') ? posix_getuid() : 'n/a') . "\n";
echo "sapi        : " . php_sapi_name() . "\n";
echo "parent note : expect auditd => apache2(www-data) -> sh -> <recon>\n";
echo "----\n";

// Mỗi lệnh chạy qua system() => PHP gọi /bin/sh -c '<cmd>' => đúng ancestry cần đo.
foreach ($ALLOW as $cmd) {
    echo "\$ $cmd\n";
    system($cmd);
    echo "\n";
}

echo "== end marker ==\n";
