-- Saved talent specs (mod-talent-manager). `id` counts per character. `talents` is a talent calculator link (one
-- digit per talent in row, then column order, trees joined by '-'). glyph1..glyph6 are GlyphProperties.dbc ids by
-- glyph socket, 0 for an empty socket.
CREATE TABLE IF NOT EXISTS `talent_manager_spec` (
  `guid` INT UNSIGNED NOT NULL,
  `id` INT UNSIGNED NOT NULL,
  `sort` INT UNSIGNED NOT NULL DEFAULT 0,
  `name` VARCHAR(32) NOT NULL,
  `talents` VARCHAR(255) NOT NULL DEFAULT '',
  `glyph1` INT UNSIGNED NOT NULL DEFAULT 0,
  `glyph2` INT UNSIGNED NOT NULL DEFAULT 0,
  `glyph3` INT UNSIGNED NOT NULL DEFAULT 0,
  `glyph4` INT UNSIGNED NOT NULL DEFAULT 0,
  `glyph5` INT UNSIGNED NOT NULL DEFAULT 0,
  `glyph6` INT UNSIGNED NOT NULL DEFAULT 0,
  `updated` INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (`guid`, `id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
