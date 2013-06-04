SkeeveBot
=========

It is spamming me text messages, make it stop!
----------------------------------------------

Send the bot this text message: "!mute".

Outline
-------

The goal is to create a mumble bot that keeps track of Pick-Up Games
organised on the different Tribes Ascend community mumble servers. 
Based on the outcome of the games it will calculate players (ELO based)
ratings and help captains pick teams (or suggest entire lineups).


Commands
--------

The following commands are available:

	!help "command" - detailed help on the command
	!find "nick" - find which channel someone is in (mumble or tribes nick)
	!goto "mumble_nick" - move yourself to someone's channel
	!info "nick" "stat" - detailed stats on player
	!mute 0/1/2 - mute the bots spam messages from 0 (no mute) to 2 (all muted)
	!result "scores" - report the results of your last PUG ("yourcaps"-"theircaps" for each map)
	!list - shows the latest matches

Command details
---------------

### !find ###
	!find "nick"
Returns "nick"'s channel. "nick" can be a mumble nick or a player name.

### !goto ###
	!goto "mumble_nick"
The bot tries to move you to "mumble_nick"'s. Fails if the bot doesn't have sufficient rights.

### !info ###
	!info  
Returns your tag, playername and level based on your mumble nick or alias, if set.  

	!info "stat"  
As above but also shows specific statistcs "stat"  

	!info "nick"  
Returns "nick"'s tag, playername and level, seaching for the alias if set.  

	!info "nick" "stat"  
As above but also shows additional statistics "stat"  

For all above "stat" can be a space delimited case-insensitive list of statistics that are supported by the TribesAPI.  

	!help info  
Returns a list of available statistics

### !mute ###
	!mute 0/1/2
Mute the bot's spam messages from 0 (no mute) to 2 (all muted)

### !result ###
	!result "scores"
Report the results of a game with "scores" the scores for all maps in form "yourcaps"-"theircaps" separated by a space.

### !list ###
	!list
Shows the latest matches that have been registered on the bot.


Admin Commands
--------------

The following admin commands are available:

	!help admin "command" - detailed help on the admin command
	!admin login "password" - login as SuperUser
	!admin setchan "role" - set a channel's role
	!admin setrole "role" "parameter" - set a role
	!admin delrole "role" - delete a role
	!admin playernum "number" - set the required number of players per team
	!admin alias "player" "alias" - set a player's alias
	!admin come - make the bot move to your channel
	!admin op "player" - make "player" an admin
	!admin result "match_id" "scores"- set the result of a match"
	!admin delete "match_id" - delete a match"

Installation
------------

You need to install they protobuf gem:

	sudo gem install ruby_protobuf

You need to copy config.rb.example and adapt it to your liking:
	
	cp config.rb.example config.rb
	vim config.rb

Then you can run the bot with:

	./run_bot.rb

Thanks
------

Big thank you to [Orvid](https://github.com/Orvid) for helping, Lumberjack for the IRC library and general Ruby help and [FreeApophis](https://github.com/FreeApophis) for the mumble library.
