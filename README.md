SkeeveBot
=========

### Installation ###

You need to install

	sudo gem install ruby_protobuf

You need to copy config.rb.example and adapt it to your liking
	
	cp config.rb.example config.rb

Run the bot with

	./run_bot.rb

### Commands ###

The following commands are available:

	!help "command" - detailed help on the command
	!find "mumble_nick" - find which channel someone is in
	!goto "mumble_command" - move yourself to someone's channel
	!info "tribes_nick" "stat" - detailed stats on player
	!mute on/off- mute the bots spam messages
	!admin "command" - admin commands

### Admin Commands ###

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

### Thanks ###

Big thank you to Lumberjack for the IRC library and general Ruby help and [FreeApophis](https://github.com/FreeApophis) for the mumble library.
