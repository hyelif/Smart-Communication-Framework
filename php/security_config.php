<?php
/**
 * SmartPonic Security Configuration
 *
 * IMPORTANT: This file contains shared secrets.
 * In production, move these values to environment variables.
 */

// API key for HQ gateway authentication
define('SMARTPONIC_API_KEY', 'smartponic-hq-key');

// HMAC secret for request signing (SHA256 of timestamp+body+secret)
define('SMARTPONIC_HMAC_SECRET', 'smartponic-hq-signature-secret');

// Expected auth key in sensor payloads
define('SMARTPONIC_AUTH_KEY', 'AQUA77');

// Maximum age of a request timestamp (seconds)
define('SMARTPONIC_REQUEST_MAX_AGE', 300);

// Database configuration (local MySQL)
define('SMARTPONIC_DB_HOST', '127.0.0.1');
define('SMARTPONIC_DB_PORT', '3306');
define('SMARTPONIC_DB_NAME', 'smartponic');
define('SMARTPONIC_DB_USER', 'root');
define('SMARTPONIC_DB_PASS', '');
