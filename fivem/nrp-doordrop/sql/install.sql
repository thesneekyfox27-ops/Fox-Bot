CREATE TABLE IF NOT EXISTS `nrp_doordrop` (
    `citizenid`  VARCHAR(64) NOT NULL,
    `offers`     LONGTEXT NULL,
    `ratings`    LONGTEXT NULL,
    `deliveries` INT NOT NULL DEFAULT 0,
    `earned`     INT NOT NULL DEFAULT 0,
    `history`    LONGTEXT NULL,
    `reviews`    LONGTEXT NULL,
    `refund`     INT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`citizenid`)
);
-- Upgrading from 1.0/1.1? The resource adds `reviews` and `refund` automatically on start.
