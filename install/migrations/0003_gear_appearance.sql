-- Per-character gear appearance.
--
-- Turnout gear carries a name tape and rank markings, so the drawable is shared across a
-- department while the texture is personal. That makes it identity rather than equipment:
-- it belongs to the firefighter, not to the coat they happened to pick up.
--
-- Storing it on item metadata would be wrong twice over. Gear issued from an apparatus
-- rack has no item at all, and a coat handed to someone else would carry the previous
-- owner's name across with it.

CREATE TABLE IF NOT EXISTS `mi_fire_gear_appearance` (
    `id`         INT UNSIGNED NOT NULL AUTO_INCREMENT,

    -- Framework character identifier. citizenid on Qbox, identifier on ESX.
    `identifier` VARCHAR(64)  NOT NULL,

    -- Gear tier from config/gear.lua: structural, wildland, proximity, hazmat_*.
    -- A firefighter can have different markings on different sets.
    `tier`       VARCHAR(32)  NOT NULL,

    -- Slot overrides, as { slot = { drawable = n, texture = n } }. Merged over the tier's
    -- base appearance at don time, so a character only stores what differs -- usually a
    -- texture, occasionally a drawable for a differently cut coat.
    `overrides`  JSON         NOT NULL,

    `label`      VARCHAR(64)      NULL,   -- e.g. "Casey / Deputy District Chief"
    `updated_by` VARCHAR(64)      NULL,
    `created_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_gear_identifier_tier` (`identifier`, `tier`),
    KEY `idx_gear_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
