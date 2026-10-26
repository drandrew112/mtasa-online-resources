<?php
// forgotpasswd.php settings. Copy to forgotpasswd.config.php and fill in.
// api_key must be the same as RECOVERY.API_KEY in v_accounts/config.lua.
return [
    'api_key'      => 'PUT_THE_SAME_LONG_RANDOM_KEY_HERE',
    'from_email'   => 'noreply@freev-mtasa.online', // must be a sender verified in Brevo
    'from_name'    => 'FreeV',
    'max_per_hour' => 120,                // requests per hour from one IP (the game server)
    'rate_dir'     => sys_get_temp_dir(), // writable folder for the rate limit files
    'smtp' => [
        'host'   => 'smtp-relay.brevo.com',
        'port'   => 587,
        'secure' => 'tls',                // 'tls' = STARTTLS (587), 'ssl' = implicit TLS (465)
        'user'   => 'SMTP_LOGIN',
        'pass'   => 'SMTP_KEY',
    ],
];
