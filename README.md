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
	!admin "command" - admin commands

Command details
---------------

### !find ###
	!find "nick"
Returns "nick"'s channel. "nick" can be a mumble nick or a player name.

### !goto ###
	!goto "mumble_nick"
The bot tries to move you to "mumble_nick"'s. Fails if the bot doesn't have sufficient rights.

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
