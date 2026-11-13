-- Glyphs each character knows: every glyph that has been in one of its sockets, and glyphs a spec load inscribed
-- from an item in the bags. Saved specs put known glyphs in for free.
CREATE TABLE IF NOT EXISTS `talent_manager_glyph` (
  `guid` INT UNSIGNED NOT NULL,
  `glyph_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`guid`, `glyph_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
