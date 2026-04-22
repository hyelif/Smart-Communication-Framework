<?php

/**
 * Central security configuration for SmartPonic PHP endpoints.
 * Keep these values consistent with the HQ firmware.
 */

const SMARTPONIC_API_KEY = 'smartponic-hq-key';
const SMARTPONIC_HMAC_SECRET = 'smartponic-hq-signature-secret';
const SMARTPONIC_ALLOWED_ORIGINS = [
    'http://localhost',
    'http://127.0.0.1',
    'http://172.20.10.4'
];
const SMARTPONIC_REQUEST_MAX_AGE_SECONDS = 300;
