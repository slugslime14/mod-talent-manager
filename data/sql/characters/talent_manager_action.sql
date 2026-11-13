-- Action bars saved with each spec (mod-talent-manager): the bars you had when another spec was loaded over it, put
-- back when it loads again. action and type as in character_action. A row with button 255 only marks a spec whose
-- saved bars were all empty.
CREATE TABLE IF NOT EXISTS `talent_manager_action` (
  `guid` INT UNSIGNED NOT NULL,
  `spec_id` INT UNSIGNED NOT NULL,
  `button` TINYINT UNSIGNED NOT NULL,
  `action` INT UNSIGNED NOT NULL DEFAULT 0,
  `type` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `spec_id`, `button`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
