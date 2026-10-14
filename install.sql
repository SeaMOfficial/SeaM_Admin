CREATE TABLE IF NOT EXISTS `seam_admin_staff` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(80) NOT NULL,
  `role` varchar(32) NOT NULL DEFAULT 'support',
  `created_by` varchar(100) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_seam_admin_staff_role` (`role`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `seam_admin_staff_identifiers` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `staff_id` int unsigned NOT NULL,
  `identifier` varchar(100) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_seam_admin_identifier` (`identifier`),
  KEY `idx_seam_admin_identifier_staff` (`staff_id`),
  CONSTRAINT `fk_seam_admin_identifier_staff` FOREIGN KEY (`staff_id`) REFERENCES `seam_admin_staff` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `seam_admin_warnings` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) DEFAULT NULL,
  `license` varchar(100) DEFAULT NULL,
  `player_name` varchar(80) NOT NULL,
  `reason` varchar(500) NOT NULL,
  `admin_name` varchar(80) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_seam_warnings_citizenid` (`citizenid`),
  KEY `idx_seam_warnings_license` (`license`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `seam_admin_reports` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `reporter_source` int DEFAULT NULL,
  `reporter_name` varchar(80) NOT NULL,
  `reporter_license` varchar(100) DEFAULT NULL,
  `category` varchar(32) NOT NULL DEFAULT 'general',
  `subject` varchar(120) NOT NULL DEFAULT 'Support request',
  `message` varchar(1000) NOT NULL,
  `status` enum('open','claimed','closed') NOT NULL DEFAULT 'open',
  `claimed_by` varchar(80) DEFAULT NULL,
  `closed_by` varchar(80) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_seam_reports_status` (`status`, `created_at`),
  KEY `idx_seam_reports_reporter` (`reporter_license`, `updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `seam_admin_report_messages` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `report_id` int unsigned NOT NULL,
  `sender_name` varchar(80) NOT NULL,
  `sender_type` enum('player','staff') NOT NULL,
  `message` varchar(1000) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_seam_report_messages_report` (`report_id`, `created_at`),
  CONSTRAINT `fk_seam_report_messages_report` FOREIGN KEY (`report_id`) REFERENCES `seam_admin_reports` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `seam_admin_logs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `action` varchar(80) NOT NULL,
  `admin_name` varchar(80) NOT NULL,
  `admin_identifier` varchar(100) NOT NULL,
  `target_name` varchar(80) DEFAULT NULL,
  `target_identifier` varchar(100) DEFAULT NULL,
  `details` longtext DEFAULT NULL,
  `source_type` enum('game','web','system') NOT NULL DEFAULT 'game',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_seam_logs_action` (`action`, `created_at`),
  KEY `idx_seam_logs_admin` (`admin_identifier`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `seam_admin_metrics` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `players` smallint unsigned NOT NULL DEFAULT 0,
  `staff` smallint unsigned NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_seam_metrics_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `seam_admin_player_notes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) DEFAULT NULL,
  `license` varchar(100) DEFAULT NULL,
  `player_name` varchar(80) NOT NULL,
  `note` varchar(1000) NOT NULL,
  `admin_name` varchar(80) NOT NULL,
  `admin_identifier` varchar(100) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_seam_notes_citizenid` (`citizenid`, `created_at`),
  KEY `idx_seam_notes_license` (`license`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `seam_admin_duty_sessions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `staff_identifier` varchar(100) NOT NULL,
  `staff_name` varchar(80) NOT NULL,
  `role_name` varchar(32) NOT NULL,
  `player_source` int unsigned DEFAULT NULL,
  `started_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ended_at` timestamp NULL DEFAULT NULL,
  `duration_seconds` int unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `idx_seam_duty_staff` (`staff_identifier`, `started_at`),
  KEY `idx_seam_duty_open` (`ended_at`, `started_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
