<?php
/**
 * FreeV - password reset mailer
 *
 * Upload to https://freev-mtasa.online/api/forgotpasswd.php together with
 * forgotpasswd.config.php (copy forgotpasswd.config.example.php and fill it in).
 *
 * The MTA server (acc_auth/server/recovery.lua) generates the code and POSTs:
 *   POST, Content-Type: application/json, Authorization: Bearer <api_key>
 *   { "email": "...", "account": "...", "code": "K7P3QX", "expires_minutes": 15, "lang": "en" }
 * This script only checks the request and emails the code; it stores nothing
 * but a small per-IP rate limit file.
 *
 * Needs PHP 7.4+ with the openssl extension.
 *
 * Answer: {"ok":true} or {"ok":false,"error":"..."} with HTTP 400/401/405/429/500.
 */

declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

function answer(int $status, array $body): void
{
    http_response_code($status);
    echo json_encode($body, JSON_UNESCAPED_UNICODE);
    exit;
}

$configFile = __DIR__ . '/forgotpasswd.config.php';
if (!is_file($configFile)) {
    answer(500, ['ok' => false, 'error' => 'not configured']);
}
$cfg = require $configFile;

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    answer(405, ['ok' => false, 'error' => 'POST only']);
}

// --- authorization -----------------------------------------------------------
$auth = $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';
if ($auth === '' && function_exists('getallheaders')) {
    foreach (getallheaders() as $name => $value) {
        if (strcasecmp($name, 'Authorization') === 0) { $auth = $value; }
    }
}
$given = preg_match('/^Bearer\s+(\S+)$/i', trim($auth), $m) ? $m[1] : '';
if ($given === '' || strlen($cfg['api_key']) < 32 || !hash_equals($cfg['api_key'], $given)) {
    answer(401, ['ok' => false, 'error' => 'unauthorized']);
}

// --- rate limit per calling IP (the game server) ------------------------------
$ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
$rateDir = rtrim($cfg['rate_dir'] ?? sys_get_temp_dir(), '/\\');
if (!is_dir($rateDir)) { @mkdir($rateDir, 0700, true); }
$rateFile = $rateDir . '/freev_reset_' . md5($ip) . '.json';
$now = time();
$hits = [];
if (is_file($rateFile)) {
    $hits = array_values(array_filter((array) json_decode((string) file_get_contents($rateFile), true),
        fn($t) => is_int($t) && $now - $t < 3600));
}
if (count($hits) >= (int) ($cfg['max_per_hour'] ?? 120)) {
    answer(429, ['ok' => false, 'error' => 'rate limited']);
}
$hits[] = $now;
@file_put_contents($rateFile, json_encode($hits), LOCK_EX);

// --- input -------------------------------------------------------------------
$raw = file_get_contents('php://input');
$in = json_decode($raw === false ? '' : $raw, true);
if (!is_array($in)) {
    answer(400, ['ok' => false, 'error' => 'bad json']);
}
$email   = trim((string) ($in['email'] ?? ''));
$account = trim((string) ($in['account'] ?? ''));
$code    = strtoupper(trim((string) ($in['code'] ?? '')));
$minutes = max(1, min(120, (int) ($in['expires_minutes'] ?? 15)));
$lang    = ($in['lang'] ?? 'en') === 'hu' ? 'hu' : 'en';

if (strlen($email) > 254 || !filter_var($email, FILTER_VALIDATE_EMAIL)) {
    answer(400, ['ok' => false, 'error' => 'bad email']);
}
if (!preg_match('/^[A-Za-z0-9_.\-]{3,30}$/', $account)) {
    answer(400, ['ok' => false, 'error' => 'bad account']);
}
if (!preg_match('/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/', $code)) {
    answer(400, ['ok' => false, 'error' => 'bad code']);
}

// --- message -----------------------------------------------------------------
$t = [
    'en' => [
        'subject' => 'Your FreeV password reset code',
        'hello'   => 'Hi %s,',
        'line1'   => 'Someone asked to reset the password of your FreeV account. Enter this code in the game:',
        'line2'   => 'The code is valid for %d minutes. If you did not ask for it, ignore this email: your password stays the same.',
        'sign'    => 'FreeV MTA:SA',
    ],
    'hu' => [
        'subject' => 'FreeV jelszó-visszaállító kód',
        'hello'   => 'Szia %s!',
        'line1'   => 'Valaki a FreeV fiókod jelszavának visszaállítását kérte. Ezt a kódot írd be a játékban:',
        'line2'   => 'A kód %d percig érvényes. Ha nem te kérted, hagyd figyelmen kívül ezt a levelet: a jelszavad nem változik.',
        'sign'    => 'FreeV MTA:SA',
    ],
][$lang];

$h = fn(string $s) => htmlspecialchars($s, ENT_QUOTES, 'UTF-8');
$text = sprintf($t['hello'], $account) . "\r\n\r\n" . $t['line1'] . "\r\n\r\n    " . $code . "\r\n\r\n"
      . sprintf($t['line2'], $minutes) . "\r\n\r\n" . $t['sign'] . "\r\n";
$html = '<!doctype html><html><body style="margin:0;padding:24px;background:#101318;font-family:Arial,sans-serif;color:#e4e9ee">'
      . '<div style="max-width:520px;margin:0 auto;background:#181d24;padding:28px;border-left:4px solid #409cb4">'
      . '<p style="margin:0 0 14px;font-size:16px">' . $h(sprintf($t['hello'], $account)) . '</p>'
      . '<p style="margin:0 0 18px;font-size:15px;line-height:1.5">' . $h($t['line1']) . '</p>'
      . '<p style="margin:0 0 18px;font-size:32px;font-weight:bold;letter-spacing:8px;color:#ffffff">' . $h($code) . '</p>'
      . '<p style="margin:0 0 18px;font-size:13px;line-height:1.5;color:#929eaa">' . $h(sprintf($t['line2'], $minutes)) . '</p>'
      . '<p style="margin:0;font-size:13px;color:#929eaa">' . $h($t['sign']) . '</p>'
      . '</div></body></html>';

try {
    smtpSend($cfg['smtp'], $cfg['from_email'], $cfg['from_name'], $email, $t['subject'], $text, $html);
} catch (Throwable $e) {
    error_log('[forgotpasswd] ' . $e->getMessage());
    answer(500, ['ok' => false, 'error' => 'mail failed']);
}
answer(200, ['ok' => true]);

// =============================================================================
// Minimal SMTP client: STARTTLS (port 587) or implicit TLS (465), AUTH LOGIN.
// =============================================================================

function smtpSend(array $s, string $fromEmail, string $fromName, string $to, string $subject, string $text, string $html): void
{
    $secure = $s['secure'] ?? 'tls'; // 'tls' = STARTTLS, 'ssl' = implicit TLS
    $remote = ($secure === 'ssl' ? 'ssl://' : 'tcp://') . $s['host'] . ':' . (int) $s['port'];
    $ctx = stream_context_create(['ssl' => ['verify_peer' => true, 'verify_peer_name' => true, 'SNI_enabled' => true]]);
    $fp = @stream_socket_client($remote, $errno, $errstr, 15, STREAM_CLIENT_CONNECT, $ctx);
    if (!$fp) {
        throw new RuntimeException("connect failed: $errstr ($errno)");
    }
    stream_set_timeout($fp, 15);

    $read = function () use ($fp): array {
        $data = '';
        while (($line = fgets($fp, 1024)) !== false) {
            $data .= $line;
            if (strlen($line) < 4 || $line[3] === ' ') { break; }
        }
        return [(int) substr($data, 0, 3), $data];
    };
    $cmd = function (string $line, array $expect, bool $secret = false) use ($fp, $read): string {
        fwrite($fp, $line . "\r\n");
        [$code, $data] = $read();
        if (!in_array($code, $expect, true)) {
            $shown = $secret ? '(credentials)' : substr($line, 0, 60);
            throw new RuntimeException("SMTP '$shown' -> $data");
        }
        return $data;
    };

    [$code, $greet] = $read();
    if ($code !== 220) { throw new RuntimeException("greeting: $greet"); }
    $host = gethostname() ?: 'localhost';
    $cmd("EHLO $host", [250]);
    if ($secure === 'tls') {
        $cmd('STARTTLS', [220]);
        if (!stream_socket_enable_crypto($fp, true, STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT | STREAM_CRYPTO_METHOD_TLSv1_3_CLIENT)) {
            throw new RuntimeException('STARTTLS failed');
        }
        $cmd("EHLO $host", [250]);
    }
    $cmd('AUTH LOGIN', [334]);
    $cmd(base64_encode($s['user']), [334], true);
    $cmd(base64_encode($s['pass']), [235], true);
    $cmd('MAIL FROM:<' . $fromEmail . '>', [250]);
    $cmd('RCPT TO:<' . $to . '>', [250, 251]);
    $cmd('DATA', [354]);

    $boundary = 'b' . bin2hex(random_bytes(12));
    $enc = fn(string $v) => '=?UTF-8?B?' . base64_encode($v) . '?=';
    $headers = [
        'Date: ' . date('r'),
        'From: ' . $enc($fromName) . ' <' . $fromEmail . '>',
        'To: <' . $to . '>',
        'Subject: ' . $enc($subject),
        'Message-ID: <' . bin2hex(random_bytes(16)) . '@' . substr(strrchr($fromEmail, '@'), 1) . '>',
        'MIME-Version: 1.0',
        'Content-Type: multipart/alternative; boundary="' . $boundary . '"',
    ];
    $body = "--$boundary\r\nContent-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
          . chunk_split(base64_encode($text))
          . "--$boundary\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
          . chunk_split(base64_encode($html))
          . "--$boundary--\r\n";
    // base64 bodies never contain a line with a lone "."
    $cmd(implode("\r\n", $headers) . "\r\n\r\n" . $body . "\r\n.", [250]);
    $cmd('QUIT', [221, 250]);
    fclose($fp);
}
