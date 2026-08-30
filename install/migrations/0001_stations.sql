-- Stations, and the points and zones that make one up.
--
-- Station configuration is runtime data, not config-file data. A station is something a
-- server owner builds by walking around it with the placement tool, and every row here is
-- expected to be written in game rather than typed.

CREATE TABLE IF NOT EXISTS `mi_fire_stations` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name`        VARCHAR(64)  NOT NULL,
    `label`       VARCHAR(128) NOT NULL,
    `district`    VARCHAR(64)      NULL,
    `x`           DOUBLE       NOT NULL DEFAULT 0,
    `y`           DOUBLE       NOT NULL DEFAULT 0,
    `z`           DOUBLE       NOT NULL DEFAULT 0,
    `heading`     FLOAT        NOT NULL DEFAULT 0,
    `jobs`        JSON             NULL,
    `enabled`     TINYINT(1)   NOT NULL DEFAULT 1,
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_station_name` (`name`),
    KEY `idx_station_district` (`district`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Every placed point on a station, whatever it does.
--
-- One table rather than one per kind, because a light and a speaker differ only in what
-- happens when the tones drop. Adding a new kind should be a row, not a migration.
--
--   light          alert light driven up on dispatch
--   speaker        3D audio source for tones
--   panel          ox_target interaction: acknowledge, silence, test, reset
--   bay_door       door to open on turnout
--   apparatus_bay  where a rig lives, for the station board
CREATE TABLE IF NOT EXISTS `mi_fire_station_points` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `station_id`  INT UNSIGNED NOT NULL,
    `kind`        VARCHAR(32)  NOT NULL,
    `label`       VARCHAR(128)     NULL,
    `x`           DOUBLE       NOT NULL,
    `y`           DOUBLE       NOT NULL,
    `z`           DOUBLE       NOT NULL,
    `rot_x`       FLOAT        NOT NULL DEFAULT 0,
    `rot_y`       FLOAT        NOT NULL DEFAULT 0,
    `rot_z`       FLOAT        NOT NULL DEFAULT 0,
    `prop_model`  VARCHAR(64)      NULL,
    `metadata`    JSON             NULL,
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_point_station_kind` (`station_id`, `kind`),
    CONSTRAINT `fk_point_station` FOREIGN KEY (`station_id`)
        REFERENCES `mi_fire_stations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Areas rather than points, drawn by walking the perimeter.
--
--   coverage   the response area that decides which station is toned
--   interior   inside the building, for "push the call to anyone in here"
--   bay        an apparatus bay footprint
CREATE TABLE IF NOT EXISTS `mi_fire_station_zones` (
    `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
    `station_id`  INT UNSIGNED NOT NULL,
    `kind`        VARCHAR(32)  NOT NULL,
    `label`       VARCHAR(128)     NULL,
    `vertices`    JSON         NOT NULL,
    `min_z`       DOUBLE       NOT NULL DEFAULT -1000,
    `max_z`       DOUBLE       NOT NULL DEFAULT 1000,
    `created_at`  TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_zone_station_kind` (`station_id`, `kind`),
    CONSTRAINT `fk_zone_station` FOREIGN KEY (`station_id`)
        REFERENCES `mi_fire_stations` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
