DROP DATABASE IF EXISTS msict_db;
CREATE DATABASE msict_db;
USE msict_db;

-- ==================== CORE TABLES ====================

-- 1. Roles Table - Defines user roles in the system
CREATE TABLE roles (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 2. Permissions Table - Defines what actions can be performed
CREATE TABLE permissions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 3. Role-Permission Junction Table - Many-to-many relationship
CREATE TABLE role_permissions (
    id INT PRIMARY KEY AUTO_INCREMENT,
    role_id INT NOT NULL,
    permission_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE,
    FOREIGN KEY (permission_id) REFERENCES permissions(id) ON DELETE CASCADE,
    UNIQUE KEY unique_role_permission (role_id, permission_id)
);

-- 4. Users Table - System users with role-based access
CREATE TABLE users (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL, -- Hashed password
    role_id INT NOT NULL,
    status ENUM('active', 'inactive', 'suspended') DEFAULT 'active',
    last_login TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE RESTRICT,
    INDEX idx_email (email),
    INDEX idx_status (status),
    INDEX idx_role_id (role_id)
);

-- 5. Item Categories Table - Organize inventory items
CREATE TABLE item_categories (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 6. Items Table - Core inventory items
CREATE TABLE items (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    sku VARCHAR(100) NOT NULL UNIQUE,
    category_id INT NOT NULL,
    unit VARCHAR(50) NOT NULL, -- e.g., 'pieces', 'kg', 'liters'
    reorder_level INT DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (category_id) REFERENCES item_categories(id) ON DELETE RESTRICT,
    INDEX idx_sku (sku),
    INDEX idx_category_id (category_id),
    INDEX idx_is_active (is_active)
);

-- 7. Inventory Stock Table - Current stock levels
CREATE TABLE inventory_stock (
    id INT PRIMARY KEY AUTO_INCREMENT,
    item_id INT NOT NULL UNIQUE,
    quantity INT DEFAULT 0,
    location VARCHAR(100) DEFAULT 'Main Store',
    reserved_quantity INT DEFAULT 0, -- Items reserved for pending requests
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    updated_by INT,
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
    FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_item_id (item_id),
    INDEX idx_location (location)
);

-- 8. Item Requests Table - Workflow for requesting items
CREATE TABLE item_requests (
    id INT PRIMARY KEY AUTO_INCREMENT,
    item_id INT NOT NULL,
    quantity_requested INT NOT NULL,
    requested_by INT NOT NULL,
    request_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status ENUM('pending', 'approved', 'denied', 'authorized', 'dispatched', 'cancelled') DEFAULT 'pending',
    priority ENUM('low', 'medium', 'high', 'urgent') DEFAULT 'medium',
    purpose TEXT, -- Why the item is needed
    remarks TEXT,
    approved_by INT NULL,
    approved_at TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE RESTRICT,
    FOREIGN KEY (requested_by) REFERENCES users(id) ON DELETE RESTRICT,
    FOREIGN KEY (approved_by) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_status (status),
    INDEX idx_requested_by (requested_by),
    INDEX idx_request_date (request_date),
    INDEX idx_item_id (item_id)
);

-- 9. Authorizations Table - Final authorization before dispatch
CREATE TABLE authorizations (
    id INT PRIMARY KEY AUTO_INCREMENT,
    item_request_id INT NOT NULL UNIQUE,
    authorized_by INT NOT NULL,
    authorized_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    authorization_status ENUM('authorized', 'rejected') NOT NULL,
    remarks TEXT,
    conditions TEXT, -- Any special conditions for the authorization
    FOREIGN KEY (item_request_id) REFERENCES item_requests(id) ON DELETE CASCADE,
    FOREIGN KEY (authorized_by) REFERENCES users(id) ON DELETE RESTRICT,
    INDEX idx_authorization_status (authorization_status),
    INDEX idx_authorized_by (authorized_by)
);

-- 10. Dispatch Logs Table - Track actual item dispatch
CREATE TABLE dispatch_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    item_request_id INT NOT NULL UNIQUE,
    dispatched_by INT NOT NULL,
    dispatch_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    quantity_dispatched INT NOT NULL,
    batch_number VARCHAR(100),
    receiver_name VARCHAR(100),
    receiver_signature TEXT, -- Could store base64 encoded signature
    remarks TEXT,
    FOREIGN KEY (item_request_id) REFERENCES item_requests(id) ON DELETE CASCADE,
    FOREIGN KEY (dispatched_by) REFERENCES users(id) ON DELETE RESTRICT,
    INDEX idx_dispatch_date (dispatch_date),
    INDEX idx_dispatched_by (dispatched_by)
);

-- 11. Stock Movement History Table - Audit trail for stock changes
CREATE TABLE stock_movements (
    id INT PRIMARY KEY AUTO_INCREMENT,
    item_id INT NOT NULL,
    movement_type ENUM('IN', 'OUT', 'ADJUSTMENT', 'TRANSFER') NOT NULL,
    quantity_change INT NOT NULL, -- Positive for IN, negative for OUT
    previous_quantity INT NOT NULL,
    new_quantity INT NOT NULL,
    reference_type ENUM('PURCHASE', 'DISPATCH', 'ADJUSTMENT', 'RETURN', 'TRANSFER') NOT NULL,
    reference_id INT, -- References the related record (e.g., dispatch_log_id)
    performed_by INT NOT NULL,
    notes TEXT,
    movement_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE,
    FOREIGN KEY (performed_by) REFERENCES users(id) ON DELETE RESTRICT,
    INDEX idx_item_id (item_id),
    INDEX idx_movement_type (movement_type),
    INDEX idx_movement_date (movement_date),
    INDEX idx_performed_by (performed_by)
);

-- 12. Audit Logs Table - System-wide audit trail
CREATE TABLE audit_logs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    user_id INT,
    action VARCHAR(100) NOT NULL,
    table_name VARCHAR(50) NOT NULL,
    record_id INT,
    old_values JSON,
    new_values JSON,
    ip_address VARCHAR(45),
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_user_id (user_id),
    INDEX idx_action (action),
    INDEX idx_table_name (table_name),
    INDEX idx_created_at (created_at)
);

-- ==================== VIEWS FOR REPORTING ====================

-- View: Current Stock Status with Item Details
CREATE VIEW v_current_stock AS
SELECT 
    i.id,
    i.name,
    i.sku,
    i.unit,
    ic.name AS category_name,
    COALESCE(ist.quantity, 0) AS current_quantity,
    COALESCE(ist.reserved_quantity, 0) AS reserved_quantity,
    (COALESCE(ist.quantity, 0) - COALESCE(ist.reserved_quantity, 0)) AS available_quantity,
    i.reorder_level,
    CASE 
        WHEN COALESCE(ist.quantity, 0) <= i.reorder_level THEN 'LOW_STOCK'
        WHEN COALESCE(ist.quantity, 0) = 0 THEN 'OUT_OF_STOCK'
        ELSE 'ADEQUATE'
    END AS stock_status,
    ist.location,
    ist.last_updated
FROM items i
LEFT JOIN inventory_stock ist ON i.id = ist.item_id
JOIN item_categories ic ON i.category_id = ic.id
WHERE i.is_active = TRUE;

-- View: Request Status Summary
CREATE VIEW v_request_summary AS
SELECT 
    ir.id,
    ir.request_date,
    i.name AS item_name,
    i.sku,
    ir.quantity_requested,
    ir.status,
    ir.priority,
    u_req.name AS requested_by_name,
    u_app.name AS approved_by_name,
    ir.approved_at,
    a.authorization_status,
    u_auth.name AS authorized_by_name,
    a.authorized_at,
    dl.dispatch_date,
    u_disp.name AS dispatched_by_name
FROM item_requests ir
JOIN items i ON ir.item_id = i.id
JOIN users u_req ON ir.requested_by = u_req.id
LEFT JOIN users u_app ON ir.approved_by = u_app.id
LEFT JOIN authorizations a ON ir.id = a.item_request_id
LEFT JOIN users u_auth ON a.authorized_by = u_auth.id
LEFT JOIN dispatch_logs dl ON ir.id = dl.item_request_id
LEFT JOIN users u_disp ON dl.dispatched_by = u_disp.id;

-- View: User Permissions
CREATE VIEW v_user_permissions AS
SELECT 
    u.id AS user_id,
    u.name AS user_name,
    u.email,
    r.name AS role_name,
    p.name AS permission_name,
    p.description AS permission_description
FROM users u
JOIN roles r ON u.role_id = r.id
JOIN role_permissions rp ON r.id = rp.role_id
JOIN permissions p ON rp.permission_id = p.id
WHERE u.status = 'active';

-- ==================== STORED PROCEDURES ====================

DELIMITER //

-- Procedure: Create Item Request with Stock Validation
CREATE PROCEDURE sp_create_item_request(
    IN p_item_id INT,
    IN p_quantity_requested INT,
    IN p_requested_by INT,
    IN p_purpose TEXT,
    IN p_priority ENUM('low', 'medium', 'high', 'urgent')
)
BEGIN
    DECLARE v_available_quantity INT DEFAULT 0;
    DECLARE v_request_id INT;
    
    -- Check available stock
    SELECT (COALESCE(quantity, 0) - COALESCE(reserved_quantity, 0))
    INTO v_available_quantity
    FROM inventory_stock
    WHERE item_id = p_item_id;
    
    -- Validate stock availability
    IF v_available_quantity < p_quantity_requested THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient stock available';
    END IF;
    
    -- Create the request
    INSERT INTO item_requests (item_id, quantity_requested, requested_by, purpose, priority)
    VALUES (p_item_id, p_quantity_requested, p_requested_by, p_purpose, p_priority);
    
    SET v_request_id = LAST_INSERT_ID();
    
    -- Reserve the stock
    UPDATE inventory_stock 
    SET reserved_quantity = reserved_quantity + p_quantity_requested
    WHERE item_id = p_item_id;
    
    SELECT v_request_id AS request_id;
END //

-- Procedure: Dispatch Item and Update Stock
CREATE PROCEDURE sp_dispatch_item(
    IN p_request_id INT,
    IN p_dispatched_by INT,
    IN p_quantity_dispatched INT,
    IN p_receiver_name VARCHAR(100),
    IN p_remarks TEXT
)
BEGIN
    DECLARE v_item_id INT;
    DECLARE v_quantity_requested INT;
    DECLARE v_current_stock INT;
    DECLARE v_reserved_stock INT;
    
    -- Get request details
    SELECT item_id, quantity_requested
    INTO v_item_id, v_quantity_requested
    FROM item_requests
    WHERE id = p_request_id AND status = 'authorized';
    
    IF v_item_id IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Request not found or not authorized';
    END IF;
    
    -- Get current stock
    SELECT quantity, reserved_quantity
    INTO v_current_stock, v_reserved_stock
    FROM inventory_stock
    WHERE item_id = v_item_id;
    
    -- Validate dispatch quantity
    IF p_quantity_dispatched > v_quantity_requested THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Dispatch quantity cannot exceed requested quantity';
    END IF;
    
    IF p_quantity_dispatched > v_current_stock THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Insufficient stock for dispatch';
    END IF;
    
    -- Update stock
    UPDATE inventory_stock
    SET quantity = quantity - p_quantity_dispatched,
        reserved_quantity = reserved_quantity - v_quantity_requested,
        updated_by = p_dispatched_by
    WHERE item_id = v_item_id;
    
    -- Create dispatch log
    INSERT INTO dispatch_logs (item_request_id, dispatched_by, quantity_dispatched, receiver_name, remarks)
    VALUES (p_request_id, p_dispatched_by, p_quantity_dispatched, p_receiver_name, p_remarks);
    
    -- Update request status
    UPDATE item_requests
    SET status = 'dispatched'
    WHERE id = p_request_id;
    
    -- Log stock movement
    INSERT INTO stock_movements (item_id, movement_type, quantity_change, previous_quantity, new_quantity, reference_type, reference_id, performed_by)
    VALUES (v_item_id, 'OUT', -p_quantity_dispatched, v_current_stock, v_current_stock - p_quantity_dispatched, 'DISPATCH', LAST_INSERT_ID(), p_dispatched_by);
    
END //

DELIMITER ;

-- ==================== TRIGGERS ====================

-- Trigger: Audit log for user changes
DELIMITER //
CREATE TRIGGER tr_users_audit
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    INSERT INTO audit_logs (user_id, action, table_name, record_id, old_values, new_values)
    VALUES (
        NEW.id,
        'UPDATE',
        'users',
        NEW.id,
        JSON_OBJECT('name', OLD.name, 'email', OLD.email, 'status', OLD.status, 'role_id', OLD.role_id),
        JSON_OBJECT('name', NEW.name, 'email', NEW.email, 'status', NEW.status, 'role_id', NEW.role_id)
    );
END //
DELIMITER ;

-- Trigger: Update reserved quantity when request is cancelled/denied
DELIMITER //
CREATE TRIGGER tr_request_status_change
AFTER UPDATE ON item_requests
FOR EACH ROW
BEGIN
    -- If request is cancelled or denied, release reserved stock
    IF OLD.status IN ('pending', 'approved') AND NEW.status IN ('denied', 'cancelled') THEN
        UPDATE inventory_stock
        SET reserved_quantity = reserved_quantity - OLD.quantity_requested
        WHERE item_id = OLD.item_id;
    END IF;
END //
DELIMITER ;

SELECT 'Inventory Management Database Schema Created Successfully!' AS status;