<?php
// CORS headers
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type, Authorization");

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

require '../vendor/autoload.php';
require '../Config/config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

$issuer_claim = "localhost";
$audience_claim = "localhost";
$issuedat_claim = time();
$expire_claim = $issuedat_claim + 3600;

header("Content-Type: application/json");

$method = $_SERVER['REQUEST_METHOD'];
$path = $_SERVER['REQUEST_URI'];

if (strpos($path, '/signup') !== false && $method === 'POST') {
    signup($link);
} elseif (strpos($path, '/login') !== false && $method === 'POST') {
    login($link);
} else {
    http_response_code(404);
    echo json_encode(["message" => "Route not found"]);
}

// SIGNUP FUNCTION
//api endpoint ake ni "http://localhost/unfedZombie/Controllers/authController.php/signup"
function signup($link) {
    $data = json_decode(file_get_contents("php://input"), true);
    $name = $data['name'] ?? '';
    $email = $data['email'] ?? '';
    $password = $data['password'] ?? '';
    $role_id = $data['role_id'] ?? null;

    if (!$name || !$email || !$password || !$role_id) {
        http_response_code(400);
        echo json_encode(["message" => "All fields (name, email, password, role_id) are required"]);
        return;
    }

    $check = "SELECT id FROM users WHERE email = ?";
    $stmt = mysqli_prepare($link, $check);
    mysqli_stmt_bind_param($stmt, "s", $email);
    mysqli_stmt_execute($stmt);
    mysqli_stmt_store_result($stmt);

    if (mysqli_stmt_num_rows($stmt) > 0) {
        http_response_code(409);
        echo json_encode(["message" => "Email already registered"]);
        return;
    }

    $hashed_password = password_hash($password, PASSWORD_DEFAULT);
    $insert = "INSERT INTO users (name, email, password, role_id) VALUES (?, ?, ?, ?)";
    $stmt = mysqli_prepare($link, $insert);
    mysqli_stmt_bind_param($stmt, "sssi", $name, $email, $hashed_password, $role_id);

    if (mysqli_stmt_execute($stmt)) {
        http_response_code(201);
        echo json_encode(["message" => "User registered successfully"]);
    } else {
        http_response_code(500);
        echo json_encode(["message" => "Registration failed"]);
    }
}

// LOGIN FUNCTION
//api endpoint ake ni "http://localhost/unfedZombie/Controllers/authController.php/login"
function login($link) {
    global $secret_key, $issuer_claim, $audience_claim, $issuedat_claim, $expire_claim;

    $data = json_decode(file_get_contents("php://input"), true);
    $email = $data['email'] ?? '';
    $password = $data['password'] ?? '';

    if (!$email || !$password) {
        http_response_code(400);
        echo json_encode(["message" => "Email and password are required"]);
        return;
    }

    $query = "SELECT id, name, email, password, role_id FROM users WHERE email = ?";
    $stmt = mysqli_prepare($link, $query);
    mysqli_stmt_bind_param($stmt, "s", $email);
    mysqli_stmt_execute($stmt);
    $result = mysqli_stmt_get_result($stmt);
    $user = mysqli_fetch_assoc($result);

    if ($user && password_verify($password, $user['password'])) {
        $update = "UPDATE users SET last_login = NOW() WHERE id = ?";
        $stmt = mysqli_prepare($link, $update);
        mysqli_stmt_bind_param($stmt, "i", $user['id']);
        mysqli_stmt_execute($stmt);

        $payload = [
            "iss" => $issuer_claim,
            "aud" => $audience_claim,
            "iat" => $issuedat_claim,
            "exp" => $expire_claim,
            "sub" => $user['id'],
            "name" => $user['name'],
            "email" => $user['email'],
            "role_id" => $user['role_id']
        ];

        $jwt = JWT::encode($payload, $secret_key, 'HS256');

        echo json_encode([
            "message" => "Login successful",
            "token" => $jwt,
            "expires" => $expire_claim
        ]);
    } else {
        http_response_code(401);
        echo json_encode(["message" => "Invalid email or password"]);
    }
}
?>
