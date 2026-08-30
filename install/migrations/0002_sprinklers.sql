-- Fixed fire protection systems installed in buildings.
--
-- Separate from the station tables on purpose. A station is fire department property and
-- its rows are static presentation; a sprinkler system is building infrastructure that
-- carries live state -- how much water is left, which heads have fused, whether it is in
-- service. Those states persist across a restart, because a system that ran dry stays dry
-- until someone resets it. A server restart is not a reset.

CREATE TABLE IF NOT EXISTS `mi_fire_sprinkler_systems` (
    `id`            INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name`          VARCHAR(64)  NOT NULL,
    `label`         VARCHAR(128) NOT NULL,
    `district`      VARCHAR(64)      NULL,

    -- wet | dry | preaction | deluge
    `system_type`   VARCHAR(24)  NOT NULL DEFAULT 'wet',
    -- water | foam | wet_chem -- runs through the same agent matrix a hose line does
    `agent`         VARCHAR(24)  NOT NULL DEFAULT 'water',

    -- The riser: control valve, gauges, and where most of the reset happens.
    `riser_x`       DOUBLE       NOT NULL,
    `riser_y`       DOUBLE       NOT NULL,
    `riser_z`       DOUBLE       NOT NULL,
    `riser_heading` FLOAT        NOT NULL DEFAULT 0,

    -- The fire department connection on the outside of the building. Nullable: a system
    -- without one simply cannot be supplemented, which is a meaningful thing to install.
    `fdc_x`         DOUBLE           NULL,
    `fdc_y`         DOUBLE           NULL,
    `fdc_z`         DOUBLE           NULL,
    `fdc_heading`   FLOAT            NULL,

    `tank_gallons`   DOUBLE      NOT NULL DEFAULT 750,
    `tank_remaining` DOUBLE      NOT NULL DEFAULT 750,

    -- armed | flowing | empty | impaired | needs_reset
    `status`        VARCHAR(24)  NOT NULL DEFAULT 'armed',

    -- Set false to take the system out of service. An impaired system does not flow.
    `in_service`    TINYINT(1)   NOT NULL DEFAULT 1,

    `interior_id`   INT              NULL,
    `installed_by`  VARCHAR(64)      NULL,
    `last_activated_at` TIMESTAMP    NULL DEFAULT NULL,
    `created_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_sprinkler_name` (`name`),
    KEY `idx_sprinkler_district` (`district`),
    KEY `idx_sprinkler_status` (`status`, `in_service`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Individual heads.
--
-- One row per head because heads operate individually: only the ones over the fire fuse,
-- and each one that does is a separate device a crew has to replace. Storing a system as
-- a single coverage volume would lose exactly the behaviour worth having.
CREATE TABLE IF NOT EXISTS `mi_fire_sprinkler_heads` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `system_id`   INT UNSIGNED NOT NULL,

    -- Key into MIFireSprinklers.headTypes: ordinary | intermediate | high | extra_high | esfr
    `head_type`   VARCHAR(24)  NOT NULL DEFAULT 'ordinary',

    `x`           DOUBLE       NOT NULL,
    `y`           DOUBLE       NOT NULL,
    `z`           DOUBLE       NOT NULL,
    `rot_x`       FLOAT        NOT NULL DEFAULT 0,
    `rot_y`       FLOAT        NOT NULL DEFAULT 0,
    `rot_z`       FLOAT        NOT NULL DEFAULT 0,

    -- intact | fused
    -- A fused head is scrap. It stays fused until a crew replaces it.
    `status`      VARCHAR(16)  NOT NULL DEFAULT 'intact',
    `fused_at`    TIMESTAMP        NULL DEFAULT NULL,

    `metadata`    JSON             NULL,
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    KEY `idx_head_system_status` (`system_id`, `status`),
    CONSTRAINT `fk_head_system` FOREIGN KEY (`system_id`)
        REFERENCES `mi_fire_sprinkler_systems` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
