# This is a sample data to be used in you MSQL database, 
# REMEMBER TO INSERT YOUR PREFERD DATA TO THIS FIELDS AS THEY ARE REQUIRED BEFORE-HAND

# -- Insert Roles  <-- Lazima data ziweko kabla haujasajil mtyu hata mmoja
INSERT INTO roles (name, description) VALUES
('Admin', 'System administrator with full access to all functions'),
('Storekeeper', 'Manages inventory, updates stock levels, and dispatches items'),
('Department', 'Can request items from inventory and track request status'),
('Approver', 'Department head or manager who approves item requests'),
('QuarterMaster', 'Final gatekeeper who authorizes approved requests before dispatch'),
('Auditor', 'Read-only access for oversight and audit purposes');

# -- Insert Permissions <-- Lazima data ziweko kabla haujasajil mtyu hata mmoja
INSERT INTO permissions (name, description) VALUES
('manage_users', 'Create, update, and delete user accounts'),
('manage_roles', 'Create and modify user roles and permissions'),
('manage_items', 'Create, update, and delete inventory items'),
('manage_categories', 'Create and modify item categories'),
('manage_stock', 'Update inventory stock levels and locations'),
('create_requests', 'Create new item requests'),
('view_own_requests', 'View own item requests and their status'),
('view_all_requests', 'View all item requests in the system'),
('approve_requests', 'Approve or reject pending item requests'),
('authorize_requests', 'Provide final authorization for approved requests'),
('dispatch_items', 'Dispatch authorized items and update stock'),
('view_inventory_reports', 'Access inventory status and stock reports'),
('view_request_reports', 'Access request status and history reports'),
('view_audit_logs', 'Access system audit logs and trails'),
('manage_system_settings', 'Configure system-wide settings');

# -- Assign Permissions to Roles  <-- Lazima data ziweko kabla haujasajil mtyu hata mmoja
INSERT INTO role_permissions (role_id, permission_id) 
SELECT r.id, p.id FROM roles r, permissions p 
WHERE r.name = 'Admin'; -- Admin gets all permissions

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'Storekeeper' AND p.name IN (
    'manage_stock', 'dispatch_items', 'view_inventory_reports', 
    'view_all_requests', 'view_request_reports'
);

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'Requester' AND p.name IN (
    'create_requests', 'view_own_requests', 'view_inventory_reports'
);

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'Approver' AND p.name IN (
    'approve_requests', 'view_all_requests', 'view_request_reports', 'view_inventory_reports'
);

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'Authorizer' AND p.name IN (
    'authorize_requests', 'view_all_requests', 'view_request_reports', 'view_inventory_reports'
);

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id FROM roles r, permissions p
WHERE r.name = 'Auditor' AND p.name IN (
    'view_inventory_reports', 'view_request_reports', 'view_audit_logs', 'view_all_requests'
);

# -- Insert Sample Item Categories <-- LAzima ufanye specification  ya vitu vya office 
INSERT INTO item_categories (name, description) VALUES
('Office Supplies', 'General office supplies and stationery'),
('IT Equipment', 'Computers, peripherals, and IT accessories');

# -- Insert Sample Items
INSERT INTO items (name, description, sku, category_id, unit, reorder_level) VALUES
('A4 Paper', 'White A4 copy paper, 80gsm', 'OFF-001', 1, 'reams', 20),
('Black Ink Cartridge', 'HP Compatible black ink cartridge', 'OFF-002', 1, 'pieces', 5),
('Wireless Mouse', 'Optical wireless mouse with USB receiver', 'IT-001', 2, 'pieces', 10);

# -- Insert Initial Stock
# you can opt to use the Location  field
INSERT INTO inventory_stock (item_id, quantity) VALUES
(1, 50, 'Main Store'),
(2, 12, 'Main Store'),
(3, 25, 'Main Store'),
(4, 8, 'Main Store'),
(5, 6, 'Main Store'),
(6, 30, 'Main Store'),
(7, 4, 'Main Store'),
(8, 10, 'Main Store');
