SkeeveBot
=========

It is spamming me text messages, make it stop!
----------------------------------------------

Send the bot this text message:  

	!mute

Outline
-------

The goal is to create a mumble bot that keeps track of Pick-Up Games
organised on the different Tribes Ascend community mumble servers. 
Based on the outcome of the games it will calculate players (ELO based)
ratings and help captains pick teams (or suggest entire lineups).


Commands
--------

The following commands are available:

	!help <command> - detailed help on the command
	!find <nick> - find which channel someone is in (mumble or tribes nick)
	!goto <mumble_nick> - move yourself to someone's channel
	!info <nick> <stat> - detailed stats on player
	!mute 0/1/2 - mute the bots spam messages from 0 (no mute) to 2 (all muted)
	!result <map1> <map2> <map3> - report the results of your last PUG (use <yourcaps>-<theircaps> for each map)
	!list - shows all the matches in the last 24h

Command details
---------------

### !find ###
	!find <nick>  
Returns &lt;nick&gt;'s channel. &lt;nick&gt; can be a mumble nick or a player name.

### !goto ###
	!goto <mumble_nick>  
The bot tries to move you to &lt;mumble_nick&gt;'s. Fails if the bot doesn't have sufficient rights.

### !info ###
	!info  
Returns your tag, playername and level based on your mumble nick or alias, if set.  

	!info <stat>  
As above but also shows your additional statistic &lt;stat&gt;  

	!info <nick>  
Returns &lt;nick&gt;'s tag, playername and level, seaching for the alias if set.  

	!info <nick> <stat>  
As above but also shows additional statistics &lt;stat&gt;  

For all of the above &lt;stat&gt; can be a space delimited, case-insensitive list of statistics that are supported by the TribesAPI.  

	!help info  
Returns a list of available statistics

### !mute ###
	!mute 0/1/2
Mute the bot's spam messages from 0 (no mute) to 2 (all muted)

### !result ###
	!result <map1> <map2> <map3>
Report the results of your last game with the scores for all maps in form &lt;yourcaps&gt;-&lt;theircaps&gt;.

### !list ###
	!list
Shows the latest matches that have been registered on the bot.


Admin Commands
--------------

The following admin commands are available:

	!help admin <command> - detailed help on the admin command
	!admin login <password> - login as SuperUser
	!admin setchan <role> - set a channel's role
	!admin setrole <role> <parameter> - set a role
	!admin delrole <role> - delete a role
	!admin playernum <number> - set the required number of players per team
	!admin alias <mumble nick> <tribes nick> - set a player's alias
	!admin come - make the bot move to your channel
	!admin op <player> - make a player an admin
	!admin result <match_id> <map1> <map2> <map3> - set the result of a match"
	!admin delete <match_id> - delete a match"

### !admin alias ###

	!admin alias <mumble nick> <tribes nick>  
Set a player's alias; if either nick has a space in it please use double
quotes around it "like this".

### !admin come ###

	!admin come  
Make the bot move to your channel.

### !admin result ####

	!admin result <match_id> <map1> <map2> <map3>  
Set the result of a match, with the scores for all maps in form &lt;BEcaps&gt;-&lt;DScaps&gt;.

### !admin delete ###

	!admin delete <match_id>  
Deletes a match; Actually, they are just hidden and can be
undeleted.

### !admin playernum ###

	!admin playernum <number>  
Set the required number of players per team .


Installation
------------

You need to install they protobuf gem:

	sudo gem install ruby_protobuf

You need to copy config.rb.example and adapt it to your liking:
	
	cp config.rb.example config.rb
	vim config.rb

Then you can run the bot with:

	./run_bot.rb

For the ELO plotter you need to install

	sudo apt-get install librmagick-ruby libmagickcore-dev libmagickwand-dev
	sudo gem install rmagick
	sudo gem install gruff

Then run it with 

	./ELOCalculator.rb

Thanks
------

Big thank you to [Orvid](https://github.com/Orvid) for helping, Lumberjack for the IRC library and general Ruby help and [FreeApophis](https://github.com/FreeApophis) for the mumble library.
