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
elseif (preg_match('#/api/admin/items/(\d+)$#', $path, $matches) && $method === 'PUT') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/items/:id
    updateItem($link, $matches[1]);
}
elseif (strpos($path, '/api/admin/requests') !==false  && $method === 'GET') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/requests
    listRequests($link);
}

elseif (strpos($path, '/api/admin/dispatch') !== false && $method === 'POST') {
    //its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/dispatch
    dispatchItems($link);
}
elseif (preg_match('#/api/admin/items/(\d+)$#', $path, $matches) && $method === 'DELETE') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/items/:id
    deleteItem($link, $matches[1]);
}
elseif (preg_match('#/api/admin/approve-request/(\d+)$#', $path, $matches) && $method === 'PUT') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/approve-request/:id
    approveRequest($link, $matches[1]);
}
elseif (preg_match('#/api/admin/authorize-request/(\d+)$#', $path, $matches) && $method === 'PUT') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/authorize-request/:id
    authorizeRequest($link, $matches[1]);
} 
// Item Categories
elseif (strpos($path, '/api/admin/item-categories') !== false && $method === 'POST') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/item-categories
    createItemCategory($link);
}
elseif (preg_match('#/api/admin/item-categories/(\d+)$#', $path, $matches) && $method === 'DELETE') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/item-categories/:id
    deleteItemCategory($link, $matches[1]);
}

// Role Permissions
elseif (strpos($path, '/api/admin/role-permissions') !== false && $method === 'POST') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/role-permissions
    addRolePermission($link);
}
elseif (preg_match('#/api/admin/role-permissions/(\d+)$#', $path, $matches) && $method === 'PUT') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/role-permissions/:id
    updateRolePermission($link, $matches[1]);
}
elseif (preg_match('#/api/admin/role-permissions/(\d+)$#', $path, $matches) && $method === 'DELETE') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/role-permissions/:id
    deleteRolePermission($link, $matches[1]);
}

// Roles
elseif (strpos($path, '/api/admin/roles') !== false && $method === 'POST') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/roles
    createRole($link);
}
elseif (preg_match('#/api/admin/roles/(\d+)$#', $path, $matches) && $method === 'DELETE') {
    // its api-end point is  http://localhost/unfedZombie/Controllers/admin/api/admin/roles/:id
    deleteRole($link, $matches[1]);
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
    mysqli_stmt_bind_param($stmt, "iii", $data['item_id'], $data['quantity'], $data['dispatched_by']);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Items dispatched"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function createItemCategory($link) {
    $data = json_decode(file_get_contents("php://input"), true);
    if (empty($data['name'])) {
        http_response_code(400);
        echo json_encode(["message" => "Category name is required"]);
        return;
    }
    $stmt = mysqli_prepare($link, "INSERT INTO item_categories (name, description) VALUES (?, ?)");
    mysqli_stmt_bind_param($stmt, "ss", $data['name'], $data['description']);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Category created"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function deleteItemCategory($link, $id) {
    $check = mysqli_prepare($link, "SELECT id FROM item_categories WHERE id = ?");
    mysqli_stmt_bind_param($check, "i", $id);
    mysqli_stmt_execute($check);
    mysqli_stmt_store_result($check);
    if (mysqli_stmt_num_rows($check) === 0) {
        http_response_code(404);
        echo json_encode(["error" => "Category not found"]);
        return;
    }
    mysqli_stmt_close($check);

    $stmt = mysqli_prepare($link, "DELETE FROM item_categories WHERE id = ?");
    mysqli_stmt_bind_param($stmt, "i", $id);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Category deleted"]);
    } else {
        if (mysqli_errno($link) == 1451) {
            http_response_code(400);
            echo json_encode(["error" => "Cannot delete category: it is in use by one or more items."]);
        } else {
            http_response_code(500);
            echo json_encode(["error" => mysqli_error($link)]);
        }
    }
}

function addRolePermission($link) {
    $data = json_decode(file_get_contents("php://input"), true);
    if (empty($data['role_id']) || empty($data['permission_id'])) {
        http_response_code(400);
        echo json_encode(["message" => "role_id and permission_id are required"]);
        return;
    }
    $stmt = mysqli_prepare($link, "INSERT INTO role_permissions (role_id, permission_id) VALUES (?, ?)");
    mysqli_stmt_bind_param($stmt, "ii", $data['role_id'], $data['permission_id']);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Role permission added"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function updateRolePermission($link, $id) {
    $data = json_decode(file_get_contents("php://input"), true);
    if (empty($data['role_id']) || empty($data['permission_id'])) {
        http_response_code(400);
        echo json_encode(["message" => "role_id and permission_id are required"]);
        return;
    }
    $stmt = mysqli_prepare($link, "UPDATE role_permissions SET role_id = ?, permission_id = ? WHERE id = ?");
    mysqli_stmt_bind_param($stmt, "iii", $data['role_id'], $data['permission_id'], $id);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Role permission updated"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function deleteRolePermission($link, $id) {
    $stmt = mysqli_prepare($link, "DELETE FROM role_permissions WHERE id = ?");
    mysqli_stmt_bind_param($stmt, "i", $id);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Role permission deleted"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function createRole($link) {
    $data = json_decode(file_get_contents("php://input"), true);
    if (empty($data['name'])) {
        http_response_code(400);
        echo json_encode(["message" => "Role name is required"]);
        return;
    }
    $stmt = mysqli_prepare($link, "INSERT INTO roles (name, description) VALUES (?, ?)");
    mysqli_stmt_bind_param($stmt, "ss", $data['name'], $data['description']);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Role created"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function deleteRole($link, $id) {
    $stmt = mysqli_prepare($link, "DELETE FROM roles WHERE id = ?");
    mysqli_stmt_bind_param($stmt, "i", $id);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Role deleted"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}
?>
