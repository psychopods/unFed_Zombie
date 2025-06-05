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
require '../../vendor/autoload.php';
require '../../Config/config.php';

use Firebase\JWT\JWT;
use Firebase\JWT\Key;

header("Content-Type: application/json");

$headers = getallheaders();

if (!isset($headers['Authorization'])) {
    http_response_code(401);
    echo json_encode(["message" => "Authorization header missing"]);
    exit;
}

$token = str_replace("Bearer ", "", $headers['Authorization']);

try {
    $decoded = JWT::decode($token, new Key($secret_key, 'HS256'));
    $user_id = $decoded->sub;
    $role_id = $decoded->role_id;
} catch (Exception $e) {
    http_response_code(401);
    echo json_encode(["message" => "Invalid token"]);
    exit;
}

function isCO($link, $role_id) {
    $query = "SELECT name FROM roles WHERE id = ?";
    $stmt = mysqli_prepare($link, $query);
    mysqli_stmt_bind_param($stmt, "i", $role_id);
    mysqli_stmt_execute($stmt);
    $result = mysqli_stmt_get_result($stmt);
    $role = mysqli_fetch_assoc($result);
    return $role && strtolower($role['name']) === 'co';
}

if (!isCO($link, $role_id)) {
    http_response_code(403);
    echo json_encode(["message" => "Access denied. CO users only."]);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'];
$route = $_GET['route'] ?? '';
$id = $_GET['id'] ?? null;

// View all pending requests for approval
if ($route === 'requests/pending' && $method === 'GET') { // http://localhost/unfedZombie/Controllers/CO/api/requests/pending
    viewPendingRequests($link);
}
// Approve a request
elseif ($route === 'requests/approve' && $method === 'PUT' && $id) { // http://localhost/unfedZombie/Controllers/CO/api/requests/approve?id=(:id)
    approveRequest($link, $user_id, $id);
}
// Deny a request
elseif ($route === 'requests/deny' && $method === 'PUT' && $id) { // http://localhost/unfedZombie/Controllers/CO/api/requests/deny?id=(:id)
    denyRequest($link, $user_id, $id);
}
// View approval history
elseif ($route === 'requests/approved' && $method === 'GET') { // http://localhost/unfedZombie/Controllers/CO/api/requests/approved
    viewApprovedRequests($link, $user_id);
}
else {
    http_response_code(404);
    echo json_encode(["message" => "Route not found"]);
}

function viewPendingRequests($link) {
    $sql = "SELECT r.id, r.item_id, i.name as item_name, r.quantity_requested, r.status, r.priority, r.purpose, r.request_date, u.name as requested_by
            FROM item_requests r
            JOIN items i ON r.item_id = i.id
            JOIN users u ON r.requested_by = u.id
            WHERE r.status = 'pending'
            ORDER BY r.request_date ASC";
    $result = mysqli_query($link, $sql);
    $requests = mysqli_fetch_all($result, MYSQLI_ASSOC);
    echo json_encode($requests);
}

function approveRequest($link, $user_id, $request_id) {
    $stmt = mysqli_prepare($link, "UPDATE item_requests SET status = 'approved', approved_by = ?, approved_at = NOW() WHERE id = ? AND status = 'pending'");
    mysqli_stmt_bind_param($stmt, "ii", $user_id, $request_id);
    mysqli_stmt_execute($stmt);
    if (mysqli_stmt_affected_rows($stmt) > 0) {
        echo json_encode(["message" => "Request approved"]);
    } else {
        http_response_code(400);
        echo json_encode(["message" => "Request not found or already processed"]);
    }
}

function denyRequest($link, $user_id, $request_id) {
    $data = json_decode(file_get_contents("php://input"), true);
    $remarks = $data['remarks'] ?? null;
    $stmt = mysqli_prepare($link, "UPDATE item_requests SET status = 'denied', approved_by = ?, approved_at = NOW(), remarks = ? WHERE id = ? AND status = 'pending'");
    mysqli_stmt_bind_param($stmt, "isi", $user_id, $remarks, $request_id);
    mysqli_stmt_execute($stmt);
    if (mysqli_stmt_affected_rows($stmt) > 0) {
        echo json_encode(["message" => "Request denied"]);
    } else {
        http_response_code(400);
        echo json_encode(["message" => "Request not found or already processed"]);
    }
}

function viewApprovedRequests($link, $user_id) {
    $stmt = mysqli_prepare($link, "SELECT r.id, r.item_id, i.name as item_name, r.quantity_requested, r.status, r.priority, r.purpose, r.request_date, r.approved_at, u.name as requested_by
        FROM item_requests r
        JOIN items i ON r.item_id = i.id
        JOIN users u ON r.requested_by = u.id
        WHERE r.approved_by = ?
        ORDER BY r.approved_at DESC");
    mysqli_stmt_bind_param($stmt, "i", $user_id);
    mysqli_stmt_execute($stmt);
    $result = mysqli_stmt_get_result($stmt);
    $requests = mysqli_fetch_all($result, MYSQLI_ASSOC);
    echo json_encode($requests);
}
?>