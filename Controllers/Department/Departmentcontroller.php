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

function isDepartment($link, $role_id) {
    $query = "SELECT name FROM roles WHERE id = ?";
    $stmt = mysqli_prepare($link, $query);
    mysqli_stmt_bind_param($stmt, "i", $role_id);
    mysqli_stmt_execute($stmt);
    $result = mysqli_stmt_get_result($stmt);
    $role = mysqli_fetch_assoc($result);
    return $role && strtolower($role['name']) === 'department';
}

if (!isDepartment($link, $role_id)) {
    http_response_code(403);
    echo json_encode(["message" => "Access denied. Department users only."]);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'];
$route = $_GET['route'] ?? '';
$id = $_GET['id'] ?? null;

// Create a new item request
if ($route === 'requests/add' && $method === 'POST') { //http://localhost/unfedZombie/Controllers/Department/api/requests/add
    createItemRequest($link, $user_id);
}
// View all requests made by this department user
elseif ($route === 'requests/my' && $method === 'GET') { //http://localhost/unfedZombie/Controllers/Department/api/requests/my
    viewMyRequests($link, $user_id);
}
// View a single request by id
elseif ($route === 'requests/view' && $method === 'GET' && $id) { //http://localhost/unfedZombie/Controllers/Department/api/requests/view?id=(:id)
    viewSingleRequest($link, $user_id, $id);
}
// Track the status of requests made by this department user
elseif ($route === 'requests/status' && $method === 'GET') { //http://localhost/unfedZombie/Controllers/Department/api/requests/status
    trackRequestStatus($link, $user_id);
}
else {
    http_response_code(404);
    echo json_encode(["message" => "Route not found"]);
}

function createItemRequest($link, $user_id) {
    $data = json_decode(file_get_contents("php://input"), true);

    if (empty($data['item_id']) || empty($data['quantity_requested'])) {
        http_response_code(400);
        echo json_encode(["message" => "item_id and quantity_requested are required"]);
        return;
    }

    $item_id = $data['item_id'];
    $quantity_requested = $data['quantity_requested'];
    $purpose = $data['purpose'] ?? null;
    $priority = $data['priority'] ?? 'medium';

    $stmt = mysqli_prepare($link, "INSERT INTO item_requests (item_id, quantity_requested, requested_by, purpose, priority) VALUES (?, ?, ?, ?, ?)");
    mysqli_stmt_bind_param($stmt, "iiiss", $item_id, $quantity_requested, $user_id, $purpose, $priority);

    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Request submitted", "request_id" => mysqli_insert_id($link)]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function viewMyRequests($link, $user_id) {
    $stmt = mysqli_prepare($link, "SELECT r.id, r.item_id, i.name as item_name, r.quantity_requested, r.status, r.priority, r.purpose, r.request_date, r.remarks FROM item_requests r JOIN items i ON r.item_id = i.id WHERE r.requested_by = ? ORDER BY r.request_date DESC");
    mysqli_stmt_bind_param($stmt, "i", $user_id);
    mysqli_stmt_execute($stmt);
    $result = mysqli_stmt_get_result($stmt);
    $requests = mysqli_fetch_all($result, MYSQLI_ASSOC);
    echo json_encode($requests);
}

function viewSingleRequest($link, $user_id, $request_id) {
    $stmt = mysqli_prepare($link, "SELECT r.id, r.item_id, i.name as item_name, r.quantity_requested, r.status, r.priority, r.purpose, r.request_date, r.remarks FROM item_requests r JOIN items i ON r.item_id = i.id WHERE r.id = ? AND r.requested_by = ?");
    mysqli_stmt_bind_param($stmt, "ii", $request_id, $user_id);
    mysqli_stmt_execute($stmt);
    $result = mysqli_stmt_get_result($stmt);
    $request = mysqli_fetch_assoc($result);
    if ($request) {
        echo json_encode($request);
    } else {
        http_response_code(404);
        echo json_encode(["message" => "Request not found"]);
    }
}


function trackRequestStatus($link, $user_id) {
    $stmt = mysqli_prepare($link, "SELECT r.id, r.item_id, i.name as item_name, r.quantity_requested, r.status, r.approved_by, r.created_at, r.remarks
        FROM item_requests r
        JOIN items i ON r.item_id = i.id
        WHERE r.requested_by = ?
        ORDER BY r.request_date DESC");
    mysqli_stmt_bind_param($stmt, "i", $user_id);
    mysqli_stmt_execute($stmt);
    $result = mysqli_stmt_get_result($stmt);
    $requests = [];
    while ($row = mysqli_fetch_assoc($result)) {
        if ($row['status'] === 'denied') {
            $row['progress'] = 'Denied';
        } elseif ($row['status'] === 'approved' && !empty($row['approved_by'])) {
            $row['progress'] = 'Approved by ' . $row['approved_by'];
        } elseif ($row['status'] === 'in_progress') {
            $row['progress'] = 'In Progress';
        } elseif ($row['status'] === 'pending') {
            $row['progress'] = 'Pending';
        } else {
            $row['progress'] = ucfirst($row['status']);
        }
        $requests[] = $row;
    }
    echo json_encode($requests);
}
?>