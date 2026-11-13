-- The saved spec last loaded into each talent group (dual spec), so the addon can mark it and show when your live
-- talents have drifted from it. talent_group is 0 for the primary group, 1 for the secondary.
CREATE TABLE IF NOT EXISTS `talent_manager_loaded` (
  `guid` INT UNSIGNED NOT NULL,
  `talent_group` TINYINT UNSIGNED NOT NULL,
  `spec_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`guid`, `talent_group`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
