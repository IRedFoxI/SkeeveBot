-- This script requires a minimum of MySQL version 4.1.1

SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO';


CREATE TABLE IF NOT EXISTS `Map` (
	`ID` INT(10) unsigned NOT NULL,
	`Name` VARCHAR(128) COLLATE utf8_bin NOT NULL,
	`Comment` TEXT COLLATE utf8_bin NOT NULL DEFAULT '',
	PRIMARY KEY (`ID`),
	UNIQUE KEY `UK_Name` (`Name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

ALTER TABLE `Map` DISABLE KEYS;
REPLACE INTO `Map` (`ID`, `Name`) VALUES
	(1447, 'Katabatic'),
	(1456, 'Arx Novena'),
	(1457, 'Drydock'),
	(1462, 'Crossfire'),
	(1473, 'Bella Omega'),
	(1493, 'Temple Ruins'),
	(1512, 'Tartarus'),
	(1514, 'Canyon Crusade Revival'),
	(1516, 'Raindance'),
	(1522, 'Stonehenge'),
	(1523, 'Sunstar'),
	(1534, 'Permafrost'),
	(1538, 'Dangerous Crossing'),
	(1543, 'Blueshift'),
	(1551, 'Bella Omega (No Sandstorm)')
;
ALTER TABLE `Map` ENABLE KEYS;


CREATE TABLE IF NOT EXISTS `Region` (
	`ID` INT(10) unsigned NOT NULL AUTO_INCREMENT,
	`Name` VARCHAR(64) NOT NULL,
	PRIMARY KEY (`ID`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

ALTER TABLE `Region` DISABLE KEYS;
REPLACE INTO `Region` (`ID`, `Name`) VALUES
	(1, 'Europe'),
	(2, 'North America')
;
ALTER TABLE `Region` ENABLE KEYS;


CREATE TABLE IF NOT EXISTS `Match` (
	`ID` INT(10) unsigned NOT NULL AUTO_INCREMENT,
	`RegionID` INT(10) unsigned NOT NULL,
	`State` ENUM('Signup','Picking','Started','Finished','Deleted') COLLATE utf8_bin NOT NULL DEFAULT 'Signup',
	`Time` DATETIME NOT NULL,
	`Comment` TEXT COLLATE utf8_bin NOT NULL DEFAULT '',
	PRIMARY KEY (`ID`),
	KEY `K_RegionID_State` (`RegionID`, `State`),
	KEY `K_RegionID` (`RegionID`),
	KEY `K_State` (`State`),
	CONSTRAINT `FK_Match_RegionID` FOREIGN KEY (`RegionID`) REFERENCES `Region` (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


CREATE TABLE IF NOT EXISTS `MatchResult` (
	`ResultID` INT(10) unsigned NOT NULL AUTO_INCREMENT,
	`RegionID` INT(10) unsigned NOT NULL,
	`MatchID` INT(10) unsigned NOT NULL,
	`MapID` INT(10) unsigned NOT NULL,
	`BECaps` TINYINT unsigned NOT NULL,
	`DSCaps` TINYINT unsigned NOT NULL,
	`Comment` TEXT COLLATE utf8_bin NOT NULL DEFAULT '',
	PRIMARY KEY (`ResultID`),
	KEY `K_RegionID_MapID` (`RegionID`, `MapID`),
	KEY `K_RegionID` (`RegionID`),
	KEY `K_MatchID` (`MatchID`),
	KEY `K_MapID` (`MapID`),
	CONSTRAINT `FK_MatchResults_MapID` FOREIGN KEY (`MapID`) REFERENCES `Map` (`ID`),
	CONSTRAINT `FK_MatchResults_MatchID` FOREIGN KEY (`MatchID`) REFERENCES `Match` (`ID`),
	CONSTRAINT `FK_MatchResults_RegionID` FOREIGN KEY (`RegionID`) REFERENCES `Region` (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


CREATE TABLE IF NOT EXISTS `MatchTeam` (
	`MatchID` INT(10) unsigned NOT NULL,
	`TeamID` INT(10) unsigned NOT NULL,
	PRIMARY KEY (`MatchID`,`TeamID`),
	KEY `K_MatchTeam_TeamID` (`TeamID`),
	CONSTRAINT `FK_MatchTeam_MatchID` FOREIGN KEY (`MatchID`) REFERENCES `Match` (`ID`),
	CONSTRAINT `FK_MatchTeam_TeamID` FOREIGN KEY (`TeamID`) REFERENCES `Team` (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


CREATE TABLE IF NOT EXISTS `Player` (
	`ID` INT(10) unsigned NOT NULL AUTO_INCREMENT,
	`Created` DATETIME NOT NULL,
	`LastUpdated` DATETIME NOT NULL,
	`RegionID` INT(10) unsigned NOT NULL,
	`Playername` VARCHAR(64) COLLATE utf8_bin NOT NULL,
	`Admin` ENUM('None', 'Admin', 'SuperUser') COLLATE utf8_bin NOT NULL DEFAULT 'None',
	`MuteLevel` INT(10) unsigned NOT NULL DEFAULT 0,
	`ELO` INT(10) unsigned NOT NULL,
	`Level` TINYINT unsigned NOT NULL,
	`Tag` VARCHAR(4) COLLATE utf8_bin NOT NULL DEFAULT '',
	PRIMARY KEY (`ID`),
	UNIQUE KEY `UK_RegionID_Playername` (`RegionID`, `Playername`),
	KEY `K_RegionID` (`RegionID`),
	KEY `K_Admin` (`Admin`),
	CONSTRAINT `FK_Player_RegionID` FOREIGN KEY (`RegionID`) REFERENCES `Region` (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;

DROP TRIGGER IF EXISTS `Trigger_Player_BeforeInsert`;
CREATE TRIGGER `Trigger_Player_BeforeInsert` BEFORE INSERT ON `Player` FOR EACH ROW BEGIN
	DECLARE Time DATETIME DEFAULT UTC_TIMESTAMP();
	SET NEW.Created = Time;
	SET NEW.LastUpdated = Time;
END;

DROP TRIGGER IF EXISTS `Trigger_Player_BeforeUpdate`;
CREATE TRIGGER `Trigger_Player_BeforeUpdate` BEFORE UPDATE ON `Player` FOR EACH ROW BEGIN
	SET NEW.LastUpdated = UTC_TIMESTAMP();
END;

-- Ensure that we always have SuperUser access.
ALTER TABLE `Player` DISABLE KEYS;
CREATE PROCEDURE AddSuperUsers() BEGIN
	-- Unfortunately, we have to be inside of a procedure in
	-- order to declare any variables, as well as to use Cursors.

	DECLARE LoopDone BOOL DEFAULT FALSE;
	DECLARE CurrentRegion INT(10) DEFAULT 0;
	DECLARE RegionCursor CURSOR FOR SELECT `ID` FROM `Region`;
	DECLARE CONTINUE HANDLER FOR NOT FOUND SET LoopDone = TRUE;

	OPEN RegionCursor;
	UpdateSuperUsers: LOOP
		FETCH RegionCursor INTO CurrentRegion;
		IF LoopDone THEN
			LEAVE UpdateSuperUsers;
		END IF;
		INSERT INTO `Player` (`RegionID`, `Playername`, `Admin`) VALUES (CurrentRegion, 'Orvid', 'SuperUser') ON DUPLICATE KEY UPDATE `Admin`='SuperUser';
	END LOOP;
	CLOSE RegionCursor;

END;
CALL AddSuperUsers();
DROP PROCEDURE AddSuperUsers;
ALTER TABLE `Player` ENABLE KEYS;


CREATE TABLE IF NOT EXISTS `PlayerAlias` (
	`PlayerID` INT(10) UNSIGNED NOT NULL,
	`Type` ENUM('Mumble', 'IRC') NOT NULL,
	`Name` VARCHAR(64) NOT NULL,
	PRIMARY KEY (`Type`, `Name`),
	KEY `K_PlayerID_Type` (`PlayerID`, `Type`),
	KEY `K_PlayerID` (`PlayerID`),
	KEY `K_Type` (`Type`),
	CONSTRAINT `FK_PlayerAlias_PlayerID` FOREIGN KEY (`PlayerID`) REFERENCES `Player` (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


CREATE TABLE IF NOT EXISTS `Team` (
	`ID` INT(10) unsigned NOT NULL AUTO_INCREMENT,
	`Comment` TEXT COLLATE utf8_bin NOT NULL DEFAULT '',
	PRIMARY KEY (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


CREATE TABLE IF NOT EXISTS `TeamPlayer` (
	`TeamID` INT(10) unsigned NOT NULL,
	`PlayerID` INT(10) unsigned NOT NULL,
	PRIMARY KEY (`TeamID`,`PlayerID`),
	KEY `K_TeamPlayer_PlayerID` (`PlayerID`),
	CONSTRAINT `FK_TeamPlayer_TeamID` FOREIGN KEY (`TeamID`) REFERENCES `Team` (`ID`),
	CONSTRAINT `FK_TeamPlayer_PlayerID` FOREIGN KEY (`PlayerID`) REFERENCES `Player` (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


SET SQL_MODE=IFNULL(@OLD_SQL_MODE, '');
SET FOREIGN_KEY_CHECKS=IF(@OLD_FOREIGN_KEY_CHECKS IS NULL, 1, @OLD_FOREIGN_KEY_CHECKS);
SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT;