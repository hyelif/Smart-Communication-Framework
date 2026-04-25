<?php
/**
 * Database Configuration
 * Edit these values to match your XAMPP MySQL setup
 */

$db_host = 'localhost';
$db_name = 'smartponic';
$db_user = 'root';
$db_password = '';  // Default XAMPP has no password

function smartponicConnect(bool $throwOnError = false): PDO
{
    global $db_host, $db_name, $db_user, $db_password;

    try {
        return new PDO(
            "mysql:host=$db_host;dbname=$db_name;charset=utf8mb4",
            $db_user,
            $db_password,
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                PDO::ATTR_EMULATE_PREPARES => false,
            ]
        );
    } catch (PDOException $e) {
        if ($throwOnError) {
            throw $e;
        }

        if (PHP_SAPI === 'cli') {
            fwrite(STDERR, "Database connection failed: " . $e->getMessage() . "\n");
            exit(1);
        }

        http_response_code(500);
        die(json_encode(['error' => 'Database connection failed']));
    }
}

$pdo = smartponicConnect();
