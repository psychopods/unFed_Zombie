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

function isStoreKeeper($link, $role_id) {
    $query = "SELECT name FROM roles WHERE id = ?";
    $stmt = mysqli_prepare($link, $query);
    mysqli_stmt_bind_param($stmt, "i", $role_id);
    mysqli_stmt_execute($stmt);
    $result = mysqli_stmt_get_result($stmt);
    $role = mysqli_fetch_assoc($result);
    return $role && strtolower($role['name']) === 'quartermaster';
}

if (!isStoreKeeper($link, $role_id)) {
    http_response_code(403);
    echo json_encode(["message" => "Access denied. QuarterMasters only."]);
    exit;
}

$method = $_SERVER['REQUEST_METHOD'];
$route = $_GET['route'] ?? '';

// Inventory management
if ($route === 'stock/view' && $method === 'GET') {
    viewStock($link);
} elseif ($route === 'stock/update' && $method === 'PUT') {
    updateStock($link);
} elseif ($route === 'items/add' && $method === 'POST') {
    addItem($link);
} elseif ($route === 'items/update' && $method === 'PUT') {
    updateItem($link);
} elseif ($route === 'items/delete' && $method === 'DELETE') {
    deleteItem($link);
} elseif ($route === 'requests/ready' && $method === 'GET') {
    viewDispatchableRequests($link);
} elseif ($route === 'dispatch/item' && $method === 'POST') {
    dispatchItem($link, $user_id);
} elseif ($route === 'requests/authorize' && $method === 'PUT') {
    authorizeRequest($link, $user_id);
} else {
    http_response_code(404);
    echo json_encode(["message" => "Route not found"]);
}

// --- Inventory Management Functions ---

function addItem($link) {
    $data = json_decode(file_get_contents("php://input"), true);
    $stmt = mysqli_prepare($link, "INSERT INTO items (name, description, sku, category_id, unit, reorder_level) VALUES (?, ?, ?, ?, ?, ?)");
    mysqli_stmt_bind_param($stmt, "sssisi", $data['name'], $data['description'], $data['sku'], $data['category_id'], $data['unit'], $data['reorder_level']);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Item added"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function updateItem($link) {
    $data = json_decode(file_get_contents("php://input"), true);
    $stmt = mysqli_prepare($link, "UPDATE items SET name=?, description=?, sku=?, category_id=?, unit=?, reorder_level=? WHERE id=?");
    mysqli_stmt_bind_param($stmt, "sssissi", $data['name'], $data['description'], $data['sku'], $data['category_id'], $data['unit'], $data['reorder_level'], $data['id']);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Item updated"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function deleteItem($link) {
    $data = json_decode(file_get_contents("php://input"), true);
    $stmt = mysqli_prepare($link, "DELETE FROM items WHERE id = ?");
    mysqli_stmt_bind_param($stmt, "i", $data['id']);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Item deleted"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

function updateStock($link) {
    $data = json_decode(file_get_contents("php://input"), true);
    $stmt = mysqli_prepare($link, "UPDATE inventory_stock SET quantity = ?, reserved_quantity = ? WHERE item_id = ?");
    mysqli_stmt_bind_param($stmt, "iii", $data['quantity'], $data['reserved_quantity'], $data['item_id']);
    if (mysqli_stmt_execute($stmt)) {
        echo json_encode(["message" => "Stock updated"]);
    } else {
        http_response_code(500);
        echo json_encode(["error" => mysqli_error($link)]);
    }
}

// --- Authorize Request Function ---

function authorizeRequest($link, $user_id) {
    $data = json_decode(file_get_contents("php://input"), true);
    $request_id = $data['request_id'] ?? null;
    if (!$request_id) {
        http_response_code(400);
        echo json_encode(["message" => "Request ID is required"]);
        return;
    }
    $stmt = mysqli_prepare($link, "UPDATE item_requests SET authorized = 1, authorized_at = NOW(), authorized_by = ? WHERE id = ? AND approved = 1 AND authorized = 0");
    mysqli_stmt_bind_param($stmt, "ii", $user_id, $request_id);
    if (mysqli_stmt_execute($stmt) && mysqli_stmt_affected_rows($stmt) > 0) {
        echo json_encode(["message" => "Request authorized"]);
    } else {
        http_response_code(400);
        echo json_encode(["message" => "Request not found or already authorized"]);
    }
}

// --- Existing Functions ---

function viewStock($link) {
    $query = "SELECT i.id, i.name, s.quantity, i.unit FROM items i JOIN inventory_stock s ON i.id = s.item_id";
    $result = mysqli_query($link, $query);
    $stock = mysqli_fetch_all($result, MYSQLI_ASSOC);
    echo json_encode($stock);
}

function viewDispatchableRequests($link) {
    $query = "SELECT r.id, r.item_id, i.name as item_name, r.quantity_requested, r.requested_by
              FROM item_requests r
              JOIN items i ON r.item_id = i.id
              WHERE r.status = 'authorized'";

    $result = mysqli_query($link, $query);
    $requests = mysqli_fetch_all($result, MYSQLI_ASSOC);
    echo json_encode($requests);
}

function dispatchItem($link, $dispatched_by) {
    $data = json_decode(file_get_contents("php://input"), true);
    $request_id = $data['request_id'] ?? null;

    if (!$request_id) {
        http_response_code(400);
        echo json_encode(["message" => "Request ID is required"]);
        return;
    }

 
    $req_query = "SELECT item_id, quantity_requested FROM item_requests WHERE id = ? AND approved = 1 AND authorized = 1 AND dispatched = 0";
    $stmt = mysqli_prepare($link, $req_query);
    mysqli_stmt_bind_param($stmt, "i", $request_id);
    mysqli_stmt_execute($stmt);
    $result = mysqli_stmt_get_result($stmt);
    $request = mysqli_fetch_assoc($result);

    if (!$request) {
        http_response_code(404);
        echo json_encode(["message" => "Approved and authorized request not found"]);
        return;
    }

    $item_id = $request['item_id'];
    $quantity = $request['quantity_requested'];

    $stock_query = "SELECT quantity FROM inventory_stock WHERE item_id = ?";
    $stmt = mysqli_prepare($link, $stock_query);
    mysqli_stmt_bind_param($stmt, "i", $item_id);
    mysqli_stmt_execute($stmt);
    $stock_result = mysqli_stmt_get_result($stmt);
    $stock = mysqli_fetch_assoc($stock_result);

    if (!$stock || $stock['quantity'] < $quantity) {
        http_response_code(400);
        echo json_encode(["message" => "Insufficient stock"]);
        return;
    }


    mysqli_begin_transaction($link);

    try {
        $update_stock = "UPDATE inventory_stock SET quantity = quantity - ? WHERE item_id = ?";
        $stmt = mysqli_prepare($link, $update_stock);
        mysqli_stmt_bind_param($stmt, "ii", $quantity, $item_id);
        mysqli_stmt_execute($stmt);

        $mark_dispatched = "UPDATE item_requests SET dispatched = 1, dispatched_at = NOW() WHERE id = ?";
        $stmt = mysqli_prepare($link, $mark_dispatched);
        mysqli_stmt_bind_param($stmt, "i", $request_id);
        mysqli_stmt_execute($stmt);

        $log = "INSERT INTO dispatches (item_id, quantity, dispatched_by, dispatched_at, request_id) VALUES (?, ?, ?, NOW(), ?)";
        $stmt = mysqli_prepare($link, $log);
        mysqli_stmt_bind_param($stmt, "iiii", $item_id, $quantity, $dispatched_by, $request_id);
        mysqli_stmt_execute($stmt);

        mysqli_commit($link);
        echo json_encode(["message" => "Item dispatched successfully"]);
    } catch (Exception $e) {
        mysqli_rollback($link);
        http_response_code(500);
        echo json_encode(["error" => "Dispatch failed", "details" => $e->getMessage()]);
    }
}
?>
