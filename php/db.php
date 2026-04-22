<?php
/**
 * Database Configuration
 * Edit these values to match your XAMPP MySQL setup
 */

$db_host = 'localhost';
$db_name = 'smartponic';
$db_user = 'root';
$db_password = '';  // Default XAMPP has no password

// Create connection
try {
    $pdo = new PDO(
        "mysql:host=$db_host;dbname=$db_name;charset=utf8mb4",
        $db_user,
        $db_password,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false
        ]
    );
} catch (PDOException $e) {
    http_response_code(500);
    die(json_encode(['error' => 'Database connection failed']));
}