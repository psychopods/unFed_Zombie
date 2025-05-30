<?php
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

function isAdmin($link, $role_id) {
    $query = "SELECT name FROM roles WHERE id = ?";
    $stmt = mysqli_prepare($link, $query);
    mysqli_stmt_bind_param($stmt, "i", $role_id);
    mysqli_stmt_execute($stmt);
    $result = mysqli_stmt_get_result($stmt);
    $role = mysqli_fetch_assoc($result);
    return $role && strtolower($role['name']) === 'admin';
}

if (!isAdmin($link, $role_id)) {
    http_response_code(403);
    echo json_encode(["message" => "Access denied. Admins only."]);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'];
$path = $_SERVER["REQUEST_URI"];

if (strpos($path, '/api/admin/users') !== false && $method === 'GET') { 
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/users
    listUsers($link);
} 

elseif(strpos($path, "/api/admin/getitems") !== false && $method === "GET"){
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/getitems
    listItems($link);
}

elseif (strpos($path, '/api/admin/items') !== false && $method === 'POST') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/items
    createItem($link);
}

elseif (strpos($path, '/api/admin/requests') !==false  && $method === 'GET') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/requests
    listRequests($link);
}

elseif (strpos($path, '/api/admin/dispatch') !== false && $method === 'POST') {
    //its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/dispatch
    dispatchItems($link);
}


elseif (strpos($path, "/api/admin/items/:id", $matches) !== false && $method === 'DELETE') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/items/:id
    deleteItem($link, $matches[1]);
}

elseif (strpos($path,"/api/admin/approve-request/:id", $matches) !== false && $method === 'PUT') {
    //its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/approve-request/:id
    approveRequest($link, $matches[1]);
}

elseif (strpos($path, "/api/admin/authorize-request/:id", $matches) !== false && $method === 'PUT') {
    //its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/authorize-request/:id
    authorizeRequest($link, $matches[1]);
}



else {
    http_response_code(404);
    echo json_encode(["message" => "Endpoint not found"]);
}

function listUsers($link) {
    $query = "SELECT u.id, u.name, u.email, r.name AS role FROM users u JOIN roles r ON u.role_id = r.id";
    $result = mysqli_query($link, $query);
    $users = mysqli_fetch_all($result, MYSQLI_ASSOC);
    echo json_encode($users);
}

function listItems($link){
    $query = "SELECT i.id, i.name, i.sku, c.name AS category_id, i.unit, i.description FROM items i JOIN item_categories c ON i.category_id = c.id";
    $result = mysqli_query($link, $query);
    $items = mysqli_fetch_all($result, MYSQLI_ASSOC);
    echo json_encode($items);
}

function createItem($link) {
    $data = json_decode(file_get_contents("php://input"), true);
    $stmt = mysqli_prepare($link, "INSERT INTO items (name, description, sku, category_id, unit, reorder_level) VALUES (?, ?, ?, ?, ?, ?)");
    mysqli_stmt_bind_param($stmt, "sssisi", $data['name'], $data['description'], $data['sku'], $data['category_id'], $data['unit'], $data['reorder_level']);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Item created"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function updateItem($link, $id) {
    $data = json_decode(file_get_contents("php://input"), true);
    $stmt = mysqli_prepare($link, "UPDATE items SET name=?, description=?, sku=?, category_id=?, unit=?, reorder_level=? WHERE id=?");
    mysqli_stmt_bind_param($stmt, "sssissi", $data['name'], $data['description'], $data['sku'], $data['category_id'], $data['unit'], $data['reorder_level'], $id);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Item updated"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function deleteItem($link, $id) {
    $stmt = mysqli_prepare($link, "DELETE FROM items WHERE id = ?");
    mysqli_stmt_bind_param($stmt, "i", $id);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Item deleted"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function listRequests($link) {
    $query = "SELECT * FROM item_requests";
    $result = mysqli_query($link, $query);
    $requests = mysqli_fetch_all($result, MYSQLI_ASSOC);
    echo json_encode($requests);
}

function approveRequest($link, $id) {
    $stmt = mysqli_prepare($link, "UPDATE item_requests SET approved = 1, approved_at = NOW() WHERE id = ?");
    mysqli_stmt_bind_param($stmt, "i", $id);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Request approved"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function authorizeRequest($link, $id) {
    $stmt = mysqli_prepare($link, "UPDATE item_requests SET authorized = 1, authorized_at = NOW() WHERE id = ?");
    mysqli_stmt_bind_param($stmt, "i", $id);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Request authorized"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function dispatchItems($link) {
    $data = json_decode(file_get_contents("php://input"), true);
    $stmt = mysqli_prepare($link, "INSERT INTO dispatches (item_id, quantity, dispatched_by, dispatched_at) VALUES (?, ?, ?, NOW())");
    mysqli_stmt_bind_param($stmt, "iis", $data['item_id'], $data['quantity'], $data['dispatched_by']);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Items dispatched"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}
?>
