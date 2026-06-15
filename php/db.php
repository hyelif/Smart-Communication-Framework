<?php
/**
 * SmartPonic Database Connection
 *
 * PDO-based connection with error handling.
 * All database access goes through this file.
 */

require_once __DIR__ . '/security_config.php';

function getDb(): PDO {
    static $pdo = null;

    if ($pdo === null) {
        try {
            $dsn = 'mysql:host=' . SMARTPONIC_DB_HOST . ';port=' . SMARTPONIC_DB_PORT
                 . ';dbname=' . SMARTPONIC_DB_NAME . ';charset=utf8mb4';

            $pdo = new PDO($dsn, SMARTPONIC_DB_USER, SMARTPONIC_DB_PASS, [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES   => false,
            ]);
        } catch (PDOException $e) {
            http_response_code(500);
            echo json_encode(['error' => 'Database connection failed']);
            error_log('SmartPonic DB connection error: ' . $e->getMessage());
            exit;
        }
    }

    return $pdo;
}
