-- This script requires a minimum of MySQL version 4.1.1

SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT;
SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0;
SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO';


CREATE TABLE IF NOT EXISTS `Map` (
  `ID` int(10) unsigned NOT NULL,
  `Name` varchar(128) COLLATE utf8_bin NOT NULL,
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


CREATE TABLE IF NOT EXISTS `Match` (
  `ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `State` enum('Signup','Picking','Started','Finished','Deleted') COLLATE utf8_bin NOT NULL DEFAULT 'Signup',
  `Date` datetime NOT NULL,
  `Comment` text COLLATE utf8_bin NOT NULL,
  PRIMARY KEY (`ID`),
  KEY `K_Status` (`State`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


CREATE TABLE IF NOT EXISTS `MatchResult` (
  `MatchID` int(10) unsigned NOT NULL,
  `MapID` int(10) unsigned NOT NULL,
  `Score` varchar(32) COLLATE utf8_bin NOT NULL,
  `Comment` text COLLATE utf8_bin NOT NULL,
  KEY `K_MatchID` (`MatchID`),
  KEY `K_MapID` (`MapID`),
  CONSTRAINT `FK_MatchResults_MapID` FOREIGN KEY (`MapID`) REFERENCES `Map` (`ID`),
  CONSTRAINT `FK_MatchResults_MatchID` FOREIGN KEY (`MatchID`) REFERENCES `Match` (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


CREATE TABLE IF NOT EXISTS `MatchTeam` (
  `MatchID` int(10) unsigned NOT NULL,
  `TeamID` int(10) unsigned NOT NULL,
  PRIMARY KEY (`MatchID`,`TeamID`),
  KEY `K_MatchTeam_TeamID` (`TeamID`),
  CONSTRAINT `FK_MatchTeam_MatchID` FOREIGN KEY (`MatchID`) REFERENCES `Match` (`ID`),
  CONSTRAINT `FK_MatchTeam_TeamID` FOREIGN KEY (`TeamID`) REFERENCES `Team` (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


CREATE TABLE IF NOT EXISTS `Player` (
	`ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
	`MumbleNick` varchar(64) COLLATE utf8_bin NOT NULL,

	-- TODO: There are multiple other fields that need to be added here.

	PRIMARY KEY (`ID`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


CREATE TABLE IF NOT EXISTS `Team` (
  `ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Comment` text COLLATE utf8_bin NOT NULL,
  PRIMARY KEY (`ID`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


CREATE TABLE IF NOT EXISTS `TeamPlayer` (
  `TeamID` int(10) unsigned NOT NULL,
  `PlayerID` int(10) unsigned NOT NULL,
  PRIMARY KEY (`TeamID`,`PlayerID`),
  KEY `K_TeamPlayer_PlayerID` (`PlayerID`),
  CONSTRAINT `FK_TeamPlayer_TeamID` FOREIGN KEY (`TeamID`) REFERENCES `Team` (`ID`),
  CONSTRAINT `FK_TeamPlayer_PlayerID` FOREIGN KEY (`PlayerID`) REFERENCES `Player` (`ID`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_bin;


SET SQL_MODE=IFNULL(@OLD_SQL_MODE, '');
SET FOREIGN_KEY_CHECKS=IF(@OLD_FOREIGN_KEY_CHECKS IS NULL, 1, @OLD_FOREIGN_KEY_CHECKS);
SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT;