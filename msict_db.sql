-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Jun 04, 2025 at 12:19 PM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `msict_db`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_create_item_request` (IN `p_item_id` INT, IN `p_quantity_requested` INT, IN `p_requested_by` INT, IN `p_purpose` TEXT, IN `p_priority` ENUM('low','medium','high','urgent'))   BEGIN
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
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_dispatch_item` (IN `p_request_id` INT, IN `p_dispatched_by` INT, IN `p_quantity_dispatched` INT, IN `p_receiver_name` VARCHAR(100), IN `p_remarks` TEXT)   BEGIN
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
    
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `audit_logs`
--

CREATE TABLE `audit_logs` (
  `id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `action` varchar(100) NOT NULL,
  `table_name` varchar(50) NOT NULL,
  `record_id` int(11) DEFAULT NULL,
  `old_values` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`old_values`)),
  `new_values` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`new_values`)),
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `audit_logs`
--

INSERT INTO `audit_logs` (`id`, `user_id`, `action`, `table_name`, `record_id`, `old_values`, `new_values`, `ip_address`, `user_agent`, `created_at`) VALUES
(1, 1, 'UPDATE', 'users', 1, '{\"name\": \"Paschal Timoth\", \"email\": \"paschaltimoth@gmx.us\", \"status\": \"active\", \"role_id\": 1}', '{\"name\": \"Paschal Timoth\", \"email\": \"paschaltimoth@gmx.us\", \"status\": \"active\", \"role_id\": 1}', NULL, NULL, '2025-06-03 21:22:20'),
(2, 1, 'UPDATE', 'users', 1, '{\"name\": \"Paschal Timoth\", \"email\": \"paschaltimoth@gmx.us\", \"status\": \"active\", \"role_id\": 1}', '{\"name\": \"Paschal Timoth\", \"email\": \"paschaltimoth@gmx.us\", \"status\": \"active\", \"role_id\": 1}', NULL, NULL, '2025-06-03 22:23:07');

-- --------------------------------------------------------

--
-- Table structure for table `authorizations`
--

CREATE TABLE `authorizations` (
  `id` int(11) NOT NULL,
  `item_request_id` int(11) NOT NULL,
  `authorized_by` int(11) NOT NULL,
  `authorized_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `authorization_status` enum('authorized','rejected') NOT NULL,
  `remarks` text DEFAULT NULL,
  `conditions` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `dispatches`
--

CREATE TABLE `dispatches` (
  `id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `quantity` int(11) NOT NULL,
  `dispatched_by` int(11) NOT NULL,
  `dispatched_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `dispatches`
--

INSERT INTO `dispatches` (`id`, `item_id`, `quantity`, `dispatched_by`, `dispatched_at`) VALUES
(4, 8, 53, 1, '2025-06-03 22:26:33');

-- --------------------------------------------------------

--
-- Table structure for table `dispatch_logs`
--

CREATE TABLE `dispatch_logs` (
  `id` int(11) NOT NULL,
  `item_request_id` int(11) NOT NULL,
  `dispatched_by` int(11) NOT NULL,
  `dispatch_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `quantity_dispatched` int(11) NOT NULL,
  `batch_number` varchar(100) DEFAULT NULL,
  `receiver_name` varchar(100) DEFAULT NULL,
  `receiver_signature` text DEFAULT NULL,
  `remarks` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `inventory_stock`
--

CREATE TABLE `inventory_stock` (
  `id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `quantity` int(11) DEFAULT 0,
  `reserved_quantity` int(11) DEFAULT 0,
  `last_updated` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `updated_by` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `inventory_stock`
--

INSERT INTO `inventory_stock` (`id`, `item_id`, `quantity`, `reserved_quantity`, `last_updated`, `updated_by`) VALUES
(1, 1, 50, 0, '2025-06-03 20:54:06', NULL),
(2, 2, 12, 0, '2025-06-03 20:54:06', NULL),
(3, 3, 25, 0, '2025-06-03 20:54:06', NULL),
(4, 4, 8, 0, '2025-06-03 20:54:06', NULL),
(5, 5, 6, 0, '2025-06-03 20:54:06', NULL),
(6, 6, 30, 0, '2025-06-03 20:54:06', NULL),
(7, 7, 4, 0, '2025-06-03 20:54:06', NULL),
(8, 8, 10, 0, '2025-06-03 20:54:06', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `items`
--

CREATE TABLE `items` (
  `id` int(11) NOT NULL,
  `name` varchar(200) NOT NULL,
  `description` text DEFAULT NULL,
  `sku` varchar(100) NOT NULL,
  `category_id` int(11) NOT NULL,
  `unit` varchar(50) NOT NULL,
  `reorder_level` int(11) DEFAULT 0,
  `is_active` tinyint(1) DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `items`
--

INSERT INTO `items` (`id`, `name`, `description`, `sku`, `category_id`, `unit`, `reorder_level`, `is_active`, `created_at`, `updated_at`) VALUES
(1, 'A4 Paper', 'White A4 copy paper, 80gsm', 'OFF-001', 1, 'reams', 20, 1, '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(2, 'Black Ink Cartridge', 'HP Compatible black ink cartridge', 'OFF-002', 1, 'pieces', 5, 1, '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(3, 'Wireless Mouse', 'Optical wireless mouse with USB receiver', 'IT-001', 2, 'pieces', 10, 1, '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(4, 'Updated Item Name', 'Updated description', 'SKU12345', 1, 'pieces', 10, 1, '2025-06-03 20:54:06', '2025-06-03 22:34:45'),
(5, 'Desk Lamp', 'LED desk lamp with adjustable brightness', 'FUR-002', 3, 'pieces', 3, 1, '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(6, 'Hand Sanitizer', '500ml antibacterial hand sanitizer', 'CLN-001', 4, 'bottles', 15, 1, '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(7, 'First Aid Kit', 'Complete first aid kit for office use', 'MED-001', 7, 'kits', 2, 1, '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(8, 'Extension Cord', '5-meter extension cord with surge protection', 'ELC-001', 8, 'pieces', 5, 1, '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(9, 'Laptop', 'Acer Gaming Laptop', 'ACGM-LPTP 001', 2, '120', NULL, 1, '2025-06-03 21:37:38', '2025-06-03 21:37:38');

-- --------------------------------------------------------

--
-- Table structure for table `item_categories`
--

CREATE TABLE `item_categories` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `item_categories`
--

INSERT INTO `item_categories` (`id`, `name`, `description`, `created_at`, `updated_at`) VALUES
(1, 'Office Supplies', 'General office supplies and stationery', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(2, 'IT Equipment', 'Computers, peripherals, and IT accessories', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(3, 'Furniture', 'Office furniture and fixtures', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(4, 'Cleaning Supplies', 'Cleaning materials and maintenance items', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(5, 'Safety Equipment', 'Personal protective equipment and safety gear', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(6, 'Tools', 'Hand tools and equipment for maintenance', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(7, 'Medical Supplies', 'First aid and medical equipment', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(8, 'Electrical', 'Electrical components and supplies', '2025-06-03 20:54:06', '2025-06-03 20:54:06');

-- --------------------------------------------------------

--
-- Table structure for table `item_requests`
--

CREATE TABLE `item_requests` (
  `id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `quantity_requested` int(11) NOT NULL,
  `requested_by` int(11) NOT NULL,
  `request_date` timestamp NOT NULL DEFAULT current_timestamp(),
  `status` enum('pending','approved','denied','authorized','dispatched','cancelled') DEFAULT 'pending',
  `priority` enum('low','medium','high','urgent') DEFAULT 'medium',
  `purpose` text DEFAULT NULL,
  `remarks` text DEFAULT NULL,
  `approved_by` int(11) DEFAULT NULL,
  `approved_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Triggers `item_requests`
--
DELIMITER $$
CREATE TRIGGER `tr_request_status_change` AFTER UPDATE ON `item_requests` FOR EACH ROW BEGIN
    -- If request is cancelled or denied, release reserved stock
    IF OLD.status IN ('pending', 'approved') AND NEW.status IN ('denied', 'cancelled') THEN
        UPDATE inventory_stock
        SET reserved_quantity = reserved_quantity - OLD.quantity_requested
        WHERE item_id = OLD.item_id;
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `permissions`
--

CREATE TABLE `permissions` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `permissions`
--

INSERT INTO `permissions` (`id`, `name`, `description`, `created_at`, `updated_at`) VALUES
(1, 'manage_users', 'Create, update, and delete user accounts', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(2, 'manage_roles', 'Create and modify user roles and permissions', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(3, 'manage_items', 'Create, update, and delete inventory items', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(4, 'manage_categories', 'Create and modify item categories', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(5, 'manage_stock', 'Update inventory stock levels', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(6, 'create_requests', 'Create new item requests', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(7, 'view_own_requests', 'View own item requests and their status', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(8, 'view_all_requests', 'View all item requests in the system', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(9, 'approve_requests', 'Approve or reject pending item requests', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(10, 'authorize_requests', 'Provide final authorization for approved requests', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(11, 'dispatch_items', 'Dispatch authorized items and update stock', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(12, 'view_inventory_reports', 'Access inventory status and stock reports', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(13, 'view_request_reports', 'Access request status and history reports', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(14, 'view_audit_logs', 'Access system audit logs and trails', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(15, 'manage_system_settings', 'Configure system-wide settings', '2025-06-03 20:54:06', '2025-06-03 20:54:06');

-- --------------------------------------------------------

--
-- Table structure for table `roles`
--

CREATE TABLE `roles` (
  `id` int(11) NOT NULL,
  `name` varchar(50) NOT NULL,
  `description` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `roles`
--

INSERT INTO `roles` (`id`, `name`, `description`, `created_at`, `updated_at`) VALUES
(1, 'Admin', 'System administrator with full access to all functions', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(2, 'QuarterMaster', 'Manages inventory, updates stock levels, and dispatches items,Final gatekeeper who authorizes approved requests before dispatch', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(3, 'Department', 'Can request items from inventory and track request status', '2025-06-03 20:54:06', '2025-06-03 20:54:06'),
(4, 'CO', 'Department head or manager who approves item requests', '2025-06-03 20:54:06', '2025-06-03 21:17:06'),
(5, 'Auditor', 'Read-only access for oversight and audit purposes', '2025-06-03 20:54:06', '2025-06-03 20:54:06');

-- --------------------------------------------------------

--
-- Table structure for table `role_permissions`
--

CREATE TABLE `role_permissions` (
  `id` int(11) NOT NULL,
  `role_id` int(11) NOT NULL,
  `permission_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `role_permissions`
--

INSERT INTO `role_permissions` (`id`, `role_id`, `permission_id`, `created_at`) VALUES
(1, 1, 9, '2025-06-03 20:54:06'),
(2, 1, 10, '2025-06-03 20:54:06'),
(3, 1, 6, '2025-06-03 20:54:06'),
(4, 1, 11, '2025-06-03 20:54:06'),
(5, 1, 4, '2025-06-03 20:54:06'),
(6, 1, 3, '2025-06-03 20:54:06'),
(7, 1, 2, '2025-06-03 20:54:06'),
(8, 1, 5, '2025-06-03 20:54:06'),
(9, 1, 15, '2025-06-03 20:54:06'),
(10, 1, 1, '2025-06-03 20:54:06'),
(11, 1, 8, '2025-06-03 20:54:06'),
(12, 1, 14, '2025-06-03 20:54:06'),
(13, 1, 12, '2025-06-03 20:54:06'),
(14, 1, 7, '2025-06-03 20:54:06'),
(15, 1, 13, '2025-06-03 20:54:06'),
(16, 2, 10, '2025-06-03 20:54:06'),
(17, 2, 11, '2025-06-03 20:54:06'),
(18, 2, 5, '2025-06-03 20:54:06'),
(19, 2, 8, '2025-06-03 20:54:06'),
(20, 2, 12, '2025-06-03 20:54:06'),
(21, 2, 13, '2025-06-03 20:54:06'),
(23, 3, 6, '2025-06-03 20:54:06'),
(24, 3, 12, '2025-06-03 20:54:06'),
(25, 3, 7, '2025-06-03 20:54:06'),
(26, 4, 9, '2025-06-03 20:54:06'),
(27, 4, 8, '2025-06-03 20:54:06'),
(28, 4, 12, '2025-06-03 20:54:06'),
(29, 4, 13, '2025-06-03 20:54:06'),
(33, 5, 8, '2025-06-03 20:54:06'),
(34, 5, 14, '2025-06-03 20:54:06'),
(35, 5, 12, '2025-06-03 20:54:06'),
(36, 5, 13, '2025-06-03 20:54:06');

-- --------------------------------------------------------

--
-- Table structure for table `stock_movements`
--

CREATE TABLE `stock_movements` (
  `id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `movement_type` enum('IN','OUT','ADJUSTMENT','TRANSFER') NOT NULL,
  `quantity_change` int(11) NOT NULL,
  `previous_quantity` int(11) NOT NULL,
  `new_quantity` int(11) NOT NULL,
  `reference_type` enum('PURCHASE','DISPATCH','ADJUSTMENT','RETURN','TRANSFER') NOT NULL,
  `reference_id` int(11) DEFAULT NULL,
  `performed_by` int(11) NOT NULL,
  `notes` text DEFAULT NULL,
  `movement_date` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(255) NOT NULL,
  `password` varchar(255) NOT NULL,
  `role_id` int(11) NOT NULL,
  `status` enum('active','inactive','suspended') DEFAULT 'active',
  `last_login` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`id`, `name`, `email`, `password`, `role_id`, `status`, `last_login`, `created_at`, `updated_at`) VALUES
(1, 'Paschal Timoth', 'paschaltimoth@gmx.us', '$2y$10$hqeFIdtmBk6uXQ44fZPHGeshnP2VFbpsFgg23YeQ5cVXqy84NgImi', 1, 'active', '2025-06-03 22:23:07', '2025-06-03 21:08:38', '2025-06-03 22:23:07'),
(2, 'Gabriel Timoth', 'gabrieltimoth@gmx.us', '$2y$10$QfyIBrLhsp8Tp7Rlj/k5Z.M0hhvGC92OzZX2HN7/6O.neLdpySjJ.', 2, 'active', NULL, '2025-06-03 21:09:01', '2025-06-03 21:09:01'),
(3, 'Maria Timoth', 'mariatimoth@gmx.us', '$2y$10$7IxGSLi6skkWDuNHCx.oGeRMYd8U4cTxNkFo1dgFj1JqbN6NZ/qIy', 3, 'active', NULL, '2025-06-03 21:09:21', '2025-06-03 21:09:21'),
(4, 'Joseph Timoth', 'josephtimoth@gmx.us', '$2y$10$VhGtmi.G68JoBVlEs9P8muHOz2eJy3sBwV3heE193HUicZu72Dwua', 4, 'active', NULL, '2025-06-03 21:09:42', '2025-06-03 21:09:42');

--
-- Triggers `users`
--
DELIMITER $$
CREATE TRIGGER `tr_users_audit` AFTER UPDATE ON `users` FOR EACH ROW BEGIN
    INSERT INTO audit_logs (user_id, action, table_name, record_id, old_values, new_values)
    VALUES (
        NEW.id,
        'UPDATE',
        'users',
        NEW.id,
        JSON_OBJECT('name', OLD.name, 'email', OLD.email, 'status', OLD.status, 'role_id', OLD.role_id),
        JSON_OBJECT('name', NEW.name, 'email', NEW.email, 'status', NEW.status, 'role_id', NEW.role_id)
    );
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Stand-in structure for view `v_current_stock`
-- (See below for the actual view)
--
CREATE TABLE `v_current_stock` (
`id` int(11)
,`name` varchar(200)
,`sku` varchar(100)
,`unit` varchar(50)
,`category_name` varchar(100)
,`current_quantity` int(11)
,`reserved_quantity` int(11)
,`available_quantity` bigint(12)
,`reorder_level` int(11)
,`stock_status` varchar(12)
,`last_updated` timestamp
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `v_request_summary`
-- (See below for the actual view)
--
CREATE TABLE `v_request_summary` (
`id` int(11)
,`request_date` timestamp
,`item_name` varchar(200)
,`sku` varchar(100)
,`quantity_requested` int(11)
,`status` enum('pending','approved','denied','authorized','dispatched','cancelled')
,`priority` enum('low','medium','high','urgent')
,`requested_by_name` varchar(100)
,`approved_by_name` varchar(100)
,`approved_at` timestamp
,`authorization_status` enum('authorized','rejected')
,`authorized_by_name` varchar(100)
,`authorized_at` timestamp
,`dispatch_date` timestamp
,`dispatched_by_name` varchar(100)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `v_user_permissions`
-- (See below for the actual view)
--
CREATE TABLE `v_user_permissions` (
`user_id` int(11)
,`user_name` varchar(100)
,`email` varchar(255)
,`role_name` varchar(50)
,`permission_name` varchar(100)
,`permission_description` text
);

-- --------------------------------------------------------

--
-- Structure for view `v_current_stock`
--
DROP TABLE IF EXISTS `v_current_stock`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_current_stock`  AS SELECT `i`.`id` AS `id`, `i`.`name` AS `name`, `i`.`sku` AS `sku`, `i`.`unit` AS `unit`, `ic`.`name` AS `category_name`, coalesce(`ist`.`quantity`,0) AS `current_quantity`, coalesce(`ist`.`reserved_quantity`,0) AS `reserved_quantity`, coalesce(`ist`.`quantity`,0) - coalesce(`ist`.`reserved_quantity`,0) AS `available_quantity`, `i`.`reorder_level` AS `reorder_level`, CASE WHEN coalesce(`ist`.`quantity`,0) <= `i`.`reorder_level` THEN 'LOW_STOCK' WHEN coalesce(`ist`.`quantity`,0) = 0 THEN 'OUT_OF_STOCK' ELSE 'ADEQUATE' END AS `stock_status`, `ist`.`last_updated` AS `last_updated` FROM ((`items` `i` left join `inventory_stock` `ist` on(`i`.`id` = `ist`.`item_id`)) join `item_categories` `ic` on(`i`.`category_id` = `ic`.`id`)) WHERE `i`.`is_active` = 1 ;

-- --------------------------------------------------------

--
-- Structure for view `v_request_summary`
--
DROP TABLE IF EXISTS `v_request_summary`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_request_summary`  AS SELECT `ir`.`id` AS `id`, `ir`.`request_date` AS `request_date`, `i`.`name` AS `item_name`, `i`.`sku` AS `sku`, `ir`.`quantity_requested` AS `quantity_requested`, `ir`.`status` AS `status`, `ir`.`priority` AS `priority`, `u_req`.`name` AS `requested_by_name`, `u_app`.`name` AS `approved_by_name`, `ir`.`approved_at` AS `approved_at`, `a`.`authorization_status` AS `authorization_status`, `u_auth`.`name` AS `authorized_by_name`, `a`.`authorized_at` AS `authorized_at`, `dl`.`dispatch_date` AS `dispatch_date`, `u_disp`.`name` AS `dispatched_by_name` FROM (((((((`item_requests` `ir` join `items` `i` on(`ir`.`item_id` = `i`.`id`)) join `users` `u_req` on(`ir`.`requested_by` = `u_req`.`id`)) left join `users` `u_app` on(`ir`.`approved_by` = `u_app`.`id`)) left join `authorizations` `a` on(`ir`.`id` = `a`.`item_request_id`)) left join `users` `u_auth` on(`a`.`authorized_by` = `u_auth`.`id`)) left join `dispatch_logs` `dl` on(`ir`.`id` = `dl`.`item_request_id`)) left join `users` `u_disp` on(`dl`.`dispatched_by` = `u_disp`.`id`)) ;

-- --------------------------------------------------------

--
-- Structure for view `v_user_permissions`
--
DROP TABLE IF EXISTS `v_user_permissions`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_user_permissions`  AS SELECT `u`.`id` AS `user_id`, `u`.`name` AS `user_name`, `u`.`email` AS `email`, `r`.`name` AS `role_name`, `p`.`name` AS `permission_name`, `p`.`description` AS `permission_description` FROM (((`users` `u` join `roles` `r` on(`u`.`role_id` = `r`.`id`)) join `role_permissions` `rp` on(`r`.`id` = `rp`.`role_id`)) join `permissions` `p` on(`rp`.`permission_id` = `p`.`id`)) WHERE `u`.`status` = 'active' ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `audit_logs`
--
ALTER TABLE `audit_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user_id` (`user_id`),
  ADD KEY `idx_action` (`action`),
  ADD KEY `idx_table_name` (`table_name`),
  ADD KEY `idx_created_at` (`created_at`),
  ADD KEY `idx_audit_logs_user_date` (`user_id`,`created_at`);

--
-- Indexes for table `authorizations`
--
ALTER TABLE `authorizations`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `item_request_id` (`item_request_id`),
  ADD KEY `idx_authorization_status` (`authorization_status`),
  ADD KEY `idx_authorized_by` (`authorized_by`);

--
-- Indexes for table `dispatches`
--
ALTER TABLE `dispatches`
  ADD PRIMARY KEY (`id`),
  ADD KEY `item_id` (`item_id`),
  ADD KEY `dispatched_by` (`dispatched_by`);

--
-- Indexes for table `dispatch_logs`
--
ALTER TABLE `dispatch_logs`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `item_request_id` (`item_request_id`),
  ADD KEY `idx_dispatch_date` (`dispatch_date`),
  ADD KEY `idx_dispatched_by` (`dispatched_by`);

--
-- Indexes for table `inventory_stock`
--
ALTER TABLE `inventory_stock`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `item_id` (`item_id`),
  ADD KEY `updated_by` (`updated_by`),
  ADD KEY `idx_item_id` (`item_id`);

--
-- Indexes for table `items`
--
ALTER TABLE `items`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `sku` (`sku`),
  ADD KEY `idx_sku` (`sku`),
  ADD KEY `idx_category_id` (`category_id`),
  ADD KEY `idx_is_active` (`is_active`);

--
-- Indexes for table `item_categories`
--
ALTER TABLE `item_categories`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `item_requests`
--
ALTER TABLE `item_requests`
  ADD PRIMARY KEY (`id`),
  ADD KEY `approved_by` (`approved_by`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_requested_by` (`requested_by`),
  ADD KEY `idx_request_date` (`request_date`),
  ADD KEY `idx_item_id` (`item_id`),
  ADD KEY `idx_item_requests_status_date` (`status`,`request_date`);

--
-- Indexes for table `permissions`
--
ALTER TABLE `permissions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `roles`
--
ALTER TABLE `roles`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `role_permissions`
--
ALTER TABLE `role_permissions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `unique_role_permission` (`role_id`,`permission_id`),
  ADD KEY `permission_id` (`permission_id`);

--
-- Indexes for table `stock_movements`
--
ALTER TABLE `stock_movements`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_item_id` (`item_id`),
  ADD KEY `idx_movement_type` (`movement_type`),
  ADD KEY `idx_movement_date` (`movement_date`),
  ADD KEY `idx_performed_by` (`performed_by`),
  ADD KEY `idx_stock_movements_item_date` (`item_id`,`movement_date`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `email` (`email`),
  ADD KEY `idx_email` (`email`),
  ADD KEY `idx_status` (`status`),
  ADD KEY `idx_role_id` (`role_id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `audit_logs`
--
ALTER TABLE `audit_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `authorizations`
--
ALTER TABLE `authorizations`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `dispatches`
--
ALTER TABLE `dispatches`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `dispatch_logs`
--
ALTER TABLE `dispatch_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `inventory_stock`
--
ALTER TABLE `inventory_stock`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `items`
--
ALTER TABLE `items`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT for table `item_categories`
--
ALTER TABLE `item_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=9;

--
-- AUTO_INCREMENT for table `item_requests`
--
ALTER TABLE `item_requests`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `permissions`
--
ALTER TABLE `permissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT for table `roles`
--
ALTER TABLE `roles`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `role_permissions`
--
ALTER TABLE `role_permissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=37;

--
-- AUTO_INCREMENT for table `stock_movements`
--
ALTER TABLE `stock_movements`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `audit_logs`
--
ALTER TABLE `audit_logs`
  ADD CONSTRAINT `audit_logs_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `authorizations`
--
ALTER TABLE `authorizations`
  ADD CONSTRAINT `authorizations_ibfk_1` FOREIGN KEY (`item_request_id`) REFERENCES `item_requests` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `authorizations_ibfk_2` FOREIGN KEY (`authorized_by`) REFERENCES `users` (`id`);

--
-- Constraints for table `dispatches`
--
ALTER TABLE `dispatches`
  ADD CONSTRAINT `dispatches_ibfk_1` FOREIGN KEY (`item_id`) REFERENCES `items` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `dispatches_ibfk_2` FOREIGN KEY (`dispatched_by`) REFERENCES `users` (`id`);

--
-- Constraints for table `dispatch_logs`
--
ALTER TABLE `dispatch_logs`
  ADD CONSTRAINT `dispatch_logs_ibfk_1` FOREIGN KEY (`item_request_id`) REFERENCES `item_requests` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `dispatch_logs_ibfk_2` FOREIGN KEY (`dispatched_by`) REFERENCES `users` (`id`);

--
-- Constraints for table `inventory_stock`
--
ALTER TABLE `inventory_stock`
  ADD CONSTRAINT `inventory_stock_ibfk_1` FOREIGN KEY (`item_id`) REFERENCES `items` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `inventory_stock_ibfk_2` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `items`
--
ALTER TABLE `items`
  ADD CONSTRAINT `items_ibfk_1` FOREIGN KEY (`category_id`) REFERENCES `item_categories` (`id`);

--
-- Constraints for table `item_requests`
--
ALTER TABLE `item_requests`
  ADD CONSTRAINT `item_requests_ibfk_1` FOREIGN KEY (`item_id`) REFERENCES `items` (`id`),
  ADD CONSTRAINT `item_requests_ibfk_2` FOREIGN KEY (`requested_by`) REFERENCES `users` (`id`),
  ADD CONSTRAINT `item_requests_ibfk_3` FOREIGN KEY (`approved_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `role_permissions`
--
ALTER TABLE `role_permissions`
  ADD CONSTRAINT `role_permissions_ibfk_1` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `role_permissions_ibfk_2` FOREIGN KEY (`permission_id`) REFERENCES `permissions` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `stock_movements`
--
ALTER TABLE `stock_movements`
  ADD CONSTRAINT `stock_movements_ibfk_1` FOREIGN KEY (`item_id`) REFERENCES `items` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `stock_movements_ibfk_2` FOREIGN KEY (`performed_by`) REFERENCES `users` (`id`);

--
-- Constraints for table `users`
--
ALTER TABLE `users`
  ADD CONSTRAINT `users_ibfk_1` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
