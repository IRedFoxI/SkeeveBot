require 'time'
# require 'speech'
# require 'celt-ruby'

requireLibrary 'IO'
requireLibrary 'Mumble'
requireLibrary 'TribesAPI'


Player = Struct.new( :session, :mumbleNick, :admin, :aliasNick, :muted, :elo, :playerName, :level, :noCaps, :noMaps, :match, :roles, :team )
Match = Struct.new( :id, :status, :date, :teams, :players, :comment, :results )
Result = Struct.new( :map, :teams, :scores, :comment )

class Bot

	def initialize options
		@clientcount = 0
		@options = options
		@connections = Hash.new
		@chanRoles = Hash.new
		@rolesRequired = Hash.new
		@defaultTeamNum = 2
		@teamNum = Hash.new
		@defaultPlayerNum = 7
		@playerNum = Hash.new
		@players = Hash.new
		@currentMatch = Hash.new
		@nextMatchId = 0
		@matches = Array.new
		@defaultMute = 2

		load_matches_ini
	end

	def exit_by_user
		puts ""
		puts "user exited bot."
		if @connections.keys.first
			@connections.keys.first.debug
		end
	end

	def connected?
		return true
	end

	def on_connected client, message
		client.switch_channel @connections[ client ][ :channel ]
	end
	

	def on_user_state client, message
		# Check whether it is the bot itself
		return if client.find_user_session( message.session ).name.eql? @connections[ client ][ :nick ]

		# Check if there is a channel change
		return unless message.instance_variable_get( "@values").has_key?( :channel_id )

		session = message.session
		chanPath = client.channels[ message.channel_id ].path

		change_user( client, session, chanPath )
	end

	def on_user_remove client, message
		# Check whether it is the bot itself
		return if client.find_user_session( message.session ).name.eql? @connections[ client ][ :nick ]

		session = message.session

		change_user( client, session )
	end

	# def on_audio client, message
	# 	packet = message.packet.bytes.to_a

	# 	index = 0
	# 	tt = Kesh::Mumble::Tools.decode_type_target( packet[ index ] )

	# 	index = 1
	# 	vi1 = Kesh::Mumble::Tools.decode_varint packet, index
	# 	index = vi1[ :new_index ]
	# 	session = vi1[ :result ]

	# 	vi2 = Kesh::Mumble::Tools.decode_varint packet, index
	# 	index = vi2[ :new_index ]
	# 	sequence = vi2[ :result ]

	# 	data = packet[ index..-1 ]
	# end

	def run servers
		servers.each do |server|

			@clientcount += 1

			client = Kesh::Mumble::MumbleClient.new( server[:host], server[:port], server[:nick], @options )
			@connections[ client ] = server

			client.register_handler :ServerSync, method( :on_connected )
			client.register_handler :UserState, method( :on_user_state )
			client.register_handler :UserRemove, method( :on_user_remove )
			# client.register_handler :UDPTunnel, method( :on_audio )
			client.register_text_handler "!help", method( :cmd_help )
			client.register_text_handler "!find", method( :cmd_find )
			client.register_text_handler "!goto", method( :cmd_goto )
			client.register_text_handler "!test", method( :cmd_test )
			client.register_text_handler "!info", method( :cmd_info )
			client.register_text_handler "!admin", method( :cmd_admin )
			client.register_text_handler "!mute", method( :cmd_mute )
			client.register_text_handler "!result", method( :cmd_result )
			client.register_text_handler "!list", method( :cmd_list )
			client.register_text_handler "!debug", method( :cmd_debug )

			load_roles_ini client

			create_new_match( client )

			client.connect

		end

		while connected? do
			sleep 0.2
		end
	end

	private

	def change_user client, session, *chanPath

		return unless @chanRoles[ client ]

		mumbleNick = client.find_user_session( session ).name

		prevRolesNeeded = check_requirements client
		prevPlayersNeeded = prevRolesNeeded.shift

		noTeams = @teamNum[ client ] ? @teamNum[ client ] : @defaultTeamNum

		match = @matches.select{ |m| m.id.eql?( @currentMatch[ client ] ) }.first

		if defined?( chanPath )
			chanPath = chanPath.first
		end

		if ( defined?( chanPath ) && @chanRoles[ client ].has_key?( chanPath ) )
			# In a monitored channel

			roles = @chanRoles[ client ][ chanPath ]

			if ( @players[ client ] && @players[ client ].has_key?( mumbleNick ) )
				# Already signed up

				player = @players[ client ][ mumbleNick ]
				oldMatchId = player.match

				if player.roles.eql?( roles ) && player.team.nil?
					# No change in role

					return

				else
					# Role changed

					firstRoleReq = @rolesRequired[ client ][ roles.first ]

					if  firstRoleReq.to_i < 0
						# Became spectator

						player.roles = roles
						player.team = nil
						player.match = nil
						messagePlayer = "You became a spectator."
						messageAll = "Player #{player.playerName} (level: #{player.level}) became a spectator."

					elsif firstRoleReq.eql? "T"
						# Joined a team channel

						if player.team.eql?( roles.first )
							# Just joined a different channel of the same team
							return
						end

						if !player.match.nil? && player.match != @currentMatch[ client ]
							# Switched team in a running game
							return
						end

						# Player returning to a running game
						@matches.each do |match|
							next unless match.status.eql?( "Started" )
							if match.players.has_key?( player.playerName )
								@players[ client ][ mumbleNick ].team = roles.first
								@players[ client ][ mumbleNick ].match = match.id
								return
							end
						end

						# Sub entering running game
						channel = client.find_channel( chanPath )
						channel.localusers.each do |user|
							if @players[ client ] && @players[ client ].has_key?( user.name )
								next if user.name.eql?( mumbleNick )
								id = @players[ client ][ user.name ].match
								if id != @currentMatch[ client ]
									@players[ client ][ mumbleNick ].team = roles.first
									@players[ client ][ mumbleNick ].match = id
									index = @matches.index{ |m| m.id.eql?( id ) }
									@matches[ index ].players[ mumbleNick ] = roles.first
									return
								end
							end
						end

						player.team = roles.first
						player.match = @currentMatch[ client ]

						if match.teams.include?( player.team )

							match.players[ player.playerName ] = player.team
							messagePlayer = "You joined team '#{player.team}'."
							messageAll = "Player #{player.playerName} (level: #{player.level}) joined team '#{player.team}'."

						else

							match.teams << player.team
							match.teams = match.teams.sort
							match.players[ player.playerName ] = player.team
							messagePlayer = "You became captain of team '#{player.team}'."
							messageAll = "Player #{player.playerName} (level: #{player.level}) became captain of team '#{player.team}'."
							if match.teams.length >= noTeams
								match.status = "Picking"
								messageAll << " Picking has started!"
							end

						end

					elsif firstRoleReq.eql? "Q"
						# Joined a queue channel

						player.roles = roles
						player.team = nil
						player.match = nil
						messagePlayer = "You joined the queue."
						messageAll = "Player #{player.playerName} (level: #{player.level}) joined the queue."

					else
						
						player.roles = roles
						player.team = nil
						player.match = @currentMatch[ client ]

						if match.status.eql?( "Picking" )
							messagePlayer = "Picking has already started. Please join the queue."
							messageAll = "Player #{player.playerName} (level: #{player.level}) jumped the queue."
						else
							messagePlayer = "Your role(s) changed to '#{roles.join(' ')}'."
							messageAll = "Player #{player.playerName} (level: #{player.level}) changed role(s) to '#{roles.join(' ')}'."
						end

					end

					# Clean up players
					match.players.each_key do |plName|
						muNick = @players[ client ].select{ |m, p| p.playerName.eql?( plName ) }.keys.first
						if muNick && @players[ client ][ muNick ].team.nil?
							match.players.delete( plName )
						end
					end

					# Clean up emtpy teams
					match.teams.each do |team|
						if !match.players.has_value?( team )
							match.teams.delete( team )
						end
					end

					# If leaving a match, check if it is over
					if !oldMatchId.nil? && !oldMatchId.eql?( player.match )
						check_match_over( client, oldMatchId )
					end

				end

			else
				# New Signup

				if @players[ client ].nil?
					@players[ client ] = Hash.new
				end

				playerData = get_player_data( client, mumbleNick )
				admin = playerData[ "admin" ]
				aliasNick = playerData[ "aliasNick" ]
				muted = playerData[ "muted" ]
				elo = playerData[ "elo" ]
				playerName = playerData[ "playerName" ]
				level = playerData[ "level" ]
				player = Player.new( session, mumbleNick, admin, aliasNick, muted, elo, playerName, level, nil, nil, nil, roles, nil )

				firstRoleReq = @rolesRequired[ client ][ roles.first ]

				if  firstRoleReq.to_i < 0
					# Became spectator

					messagePlayer = "You became a spectator."
					messageAll = "Player #{player.playerName} (level: #{player.level}) became a spectator."

				elsif firstRoleReq.eql? "T"

					# Player returning to a running game
					@matches.each do |match|
						next unless match.status.eql?( "Started" )
						if match.players.has_key?( player.playerName )
							player.team = roles.first
							player.match = match.id
							@players[ client ][ mumbleNick ] = player
							return
						end
					end

					# Sub entering running game
					channel = client.find_channel( chanPath )
					channel.localusers.each do |user|
						if @players[ client ] && @players[ client ].has_key?( user.name )
							next if user.name.eql?( mumbleNick )
							id = @players[ client ][ user.name ].match
							if id != @currentMatch[ client ]
								player.team = roles.first
								player.match = id
								@players[ client ][ mumbleNick ] = player
								index = @matches.index{ |m| m.id.eql?( id ) }
								@matches[ index ].players[ mumbleNick ] = roles.first
								return
							end
						end
					end

					player.team = roles.first
					player.match = @currentMatch[ client ]

					if match.teams.include?( player.team )

						match.players[ player.playerName ] = player.team
						messagePlayer = "You joined team '#{player.team}'."
						messageAll = "Player #{player.playerName} (level: #{player.level}) joined team '#{player.team}'."

					else

						match.teams << player.team
						match.teams = match.teams.sort
						match.players[ player.playerName ] = player.team
						messagePlayer = "You became captain of team '#{player.team}'."
						messageAll = "Player #{player.playerName} (level: #{player.level}) became captain of team '#{player.team}'."
						noTeams = @teamNum[ client ] ? @teamNum[ client ] : @defaultTeamNum
						if match.teams.length >= noTeams
							match.status = "Picking"
							messageAll << " Picking has started!"
						end

					end

				elsif firstRoleReq.eql? "Q"

					messagePlayer = "You joined the queue."
					messageAll = "Player #{player.playerName} (level: #{player.level}) joined the queue."

				else

					player.match = @currentMatch[ client ]

					if match.status.eql?( "Picking" )
						messagePlayer = "Picking has already started. Please join the queue."
						messageAll = "Player #{player.playerName} (level: #{player.level}) jumped the queue."
					else
						messagePlayer = "You signed up with role(s) '#{roles.join(' ')}'."
						messageAll = "Player #{player.playerName} (level: #{player.level}) signed up with role(s) '#{roles.join(' ')}'."
					end

				end
				
				if @players[ client ].nil?
					@players[ client ] = Hash.new
				end

			end

			@players[ client ][ mumbleNick ] = player
			index = @matches.index{ |m| m.id.eql?( @currentMatch[ client ] ) }
			@matches[ index ] = match

		else
			# Not in a monitored channel

			return unless @players[ client ] && @players[ client ].has_key?( mumbleNick )

			player = @players[ client ][ mumbleNick ]

			# If leaving a match, check if it is over
			if !player.match.nil?
				check_match_over( client, player.match )
			end

			messagePlayer = "You left the PuG/mixed channels."
			messageAll = "Player #{player.playerName} (level: #{player.level}) left."

			@players[ client ].delete( mumbleNick )

		end

		if defined?( chanPath ) && player.muted < 2
			client.send_user_message( player.session, messagePlayer )
		end

		message_all( client, messageAll, 1, player.session )

		if match.status.eql?( "Picking" )

			teamsPicked = 0
			playerNum = @playerNum[ client ] ? @playerNum[ client ] : @defaultPlayerNum

			match.teams.each do |team|
				if match.players.select{ |pN, t| t.eql?( team ) }.length >= playerNum
					teamsPicked += 1
				end
			end

			if teamsPicked >= noTeams

				index = @matches.index{ |m| m.id.eql?( @currentMatch[ client ] ) }
				@matches[ index ].status = "Started"
				@matches[ index ].date = Time.now
				message_all( client, "The teams are picked, match (id: #{match.id}) started.", 2 )

				# Create new match
				previousMatch = @currentMatch[ client ]
				create_new_match( client )
				match = @matches.select{ |m| m.id.eql?( @currentMatch[ client ] ) }.first

				# Move everyone over to the new match apart from picked players
				@players[ client ].each_pair do |mumbleNick, player|
					if player.team.nil?
						@players[ client ][ mumbleNick ].match = @currentMatch[ client ]
					end
				end

				write_matches_ini

			end

		end

		if match.status.eql?( "Signup" )

			rolesNeeded = check_requirements client
			playersNeeded = rolesNeeded.shift

			if prevPlayersNeeded >0 && playersNeeded > 0
				# Nothing

			elsif prevPlayersNeeded <= 0 && playersNeeded > 0
				message_all( client, "No longer enough players to start a match.", 2 )

			elsif ( prevPlayersNeeded > 0 && playersNeeded <= 0 ) || !rolesNeeded.eql?( prevRolesNeeded ) 

				if rolesNeeded.empty?
					message_all( client, "Enough players and all required roles are most likely covered. Start picking!", 2 )
				else
					message_all( client, "Enough players but missing #{rolesNeeded.join(' and ')}", 2 )
				end
				
			end

		end

	end

	def check_match_over client, matchId

		return if matchId.nil?

		index = @matches.index{ |m| m.id.eql?( matchId ) }
		match = @matches[ index ]

		return unless match.status.eql?( "Started" )

		stillPlaying = 0

		match.players.each_key do |plName|
			player = @players[ client ].select{ |m, p| p.playerName.eql?( plName ) }.values.first
			if player && player.match.eql?( matchId )
				stillPlaying += 1
			end
		end

		return if stillPlaying > match.players.keys.length / 2

		@matches[ index ].status = "Pending"

	end

	def create_new_match client
		id = @nextMatchId
		@nextMatchId += 1
		status = "Signup"
		date = nil
		teams = Array.new
		players = Hash.new
		comment= ""
		result = Array.new
		match = Match.new( id, status, date, teams, players, comment,result )
		@matches << match
		@currentMatch[ client ] = id
	end

	def check_requirements client

		noTeams = @teamNum[ client ] ? @teamNum[ client ] : @defaultTeamNum
		playersNeeded = @playerNum[ client ] ? @playerNum[ client ] * noTeams : @defaultPlayerNum * noTeams

		rolesToFill = @rolesRequired[ client ].inject({}) do |h,(role, value)| 
			h[ role ] = value.to_i * noTeams
			h
		end

		if @players[ client ]

			signups = @players[ client ].select { |mumbleNick,player| player.match.eql? @currentMatch[ client ] }

			signups.each_value do |player|
				if @rolesRequired[ client ][ player.roles.first ].to_i >= 0
					playersNeeded -= 1
					player.roles.each do |role|
						rolesToFill[ role ] -= 1
					end
				end
			end

		end

		rolesNeeded = Array.new
		rolesToFill.each do |role, value|
			if value > 0
				rolesNeeded << "#{value} #{role}"
			end
		end

		return rolesNeeded.unshift( playersNeeded )

	end

	def cmd_help client, message
		text = message.message
		command = text.split(' ')[ 1 ]

		case command
		when "find"
			help_msg_find( client, message )
		when "goto"
			help_msg_goto( client, message )
		when "info"
			help_msg_info( client, message )
		when "mute"
			help_msg_mute( client, message )
		when "result"
			help_msg_result( client, message )
		when "list"
			help_msg_list( client, message )
		when "admin"
			help_msg_admin( client, message )
		else
			client.send_user_message message.actor, "The following commands are available:"
			client.send_user_message message.actor, "!help \"command\" - detailed help on the command"
			client.send_user_message message.actor, "!find \"mumble_nick\" - find which channel someone is in"
			client.send_user_message message.actor, "!goto \"mumble_nick\" - move yourself to someone's channel"
			client.send_user_message message.actor, "!info \"tribes_nick\" \"stat\" - detailed stats on player"
			client.send_user_message message.actor, "!mute - 0/1/2 - mute the bots spam messages from 0 (no mute) to 2 (all muted)"
			client.send_user_message message.actor, "!result \"scores\"- sets the result of your last match"
			client.send_user_message message.actor, "!list - shows the latest matches"
			client.send_user_message message.actor, "!admin \"command\" - admin commands"
		end
	end

	def cmd_find client, message
		text = message.message
		nick = text.split(' ')[ 1 ]
		user = client.find_user nick
		
		if user
			client.send_user_message message.actor, "User '#{user.name}' is in Channel '#{user.channel.path}'"
		else
			client.send_user_message message.actor, "There is no user '#{nick}' on the Server"
		end
	end

	def help_msg_find client, message
		client.send_user_message message.actor, "Syntax: !find \"mumble_nick\""
		client.send_user_message message.actor, "Returns \"mumble_nick\"'s channel"
	end

	def cmd_goto client, message
		text = message.message
		nick = text.split(' ')[ 1 ]
		target = client.find_user nick
		source = client.find_user message.actor
		client.move_user source, target.channel
	end

	def help_msg_goto client, message
		client.send_user_message message.actor, "Syntax: !goto \"mumble_nick\""
		client.send_user_message message.actor, "The bot tries to move you to \"mumble_nick\"'s"
		client.send_user_message message.actor, "Fails if the bot doesn't have sufficient rights"
	end

	def cmd_test client, message
		client.channels.each do |id, ch|
			client.send_acl id
		end
	end

	def cmd_info client, message

		mumbleNick = client.find_user( message.actor ).name
		ownNick = mumbleNick

		if @players[ client ] && @players[ client ].has_key?( mumbleNick ) && @players[ client ][ mumbleNick ].aliasNick
			ownNick = @players[ client ][ mumbleNick ].aliasNick
		end

		text = message.message

		nick = text.split(' ')[ 1 ]
		nick = nick.nil? ? ownNick : nick

		if @players[ client ]
			playersNick = @players[ client ].values.select{ |v| v.mumbleNick.downcase.eql?( nick.downcase ) }
			if playersNick.length > 0 && playersNick.first.aliasNick
				nick = playersNick.first.aliasNick
			end
		end

		stats = Array.new
		stats << "Name"
		stats << "Level"
		stats.push( *text.split(" ")[ 2..-1 ] )
		stats.map! do |stat|
			stat.split('_').map!( &:capitalize ).join('_')
		end

		statsVals = get_player_stats( nick, stats )

		if ( statsVals.nil? && nick != ownNick )

			stats.insert( 2, nick.split('_').map!( &:capitalize ).join('_') )
			statsVals = get_player_stats( ownNick, stats )

			if statsVals.nil?
				client.send_user_message message.actor, "Player #{nick} not found. Also didn't find #{ownNick}."
				return
			else
				client.send_user_message message.actor, "Player #{nick} not found. Trying #{ownNick} and looking for stat #{nick}."
			end

		end

		if statsVals.nil?
			client.send_user_message message.actor, "Player #{nick} not found."
			return
		end

		if ( stats[ 2 ] == nick && statsVals[ 2 ].nil? )
			client.send_user_message message.actor, "Player #{nick} not found."
		else
			name = statsVals.shift
			level = statsVals.shift
			stats.shift( 2 )
			client.send_user_message message.actor, "Player #{name} has level #{level}."
			while stat = stats.shift
				statVal = statsVals.shift
				if statVal
					client.send_user_message message.actor, "#{stat}: #{statVal}."
				else
					client.send_user_message message.actor, "Unknown stat #{stat}."
				end
			end			
		end

	end

	def help_msg_info client, message
		client.send_user_message message.actor, "Syntax !info"
		client.send_user_message message.actor, "Returns your playername and level based on your mumble nick"
		client.send_user_message message.actor, "Syntax !info \"stat\""
		client.send_user_message message.actor, "As above but also shows your \"stat\""
		client.send_user_message message.actor, "Syntax !info \"tribes_nick\""
		client.send_user_message message.actor, "Returns \"tribes_nick\"'s your playername and level"
		client.send_user_message message.actor, "Syntax !info \"tribes_nick\" \"stat\""
		client.send_user_message message.actor, "As above but also shows \"tribes_nick\"'s \"stat\""
		client.send_user_message message.actor, "\"stat\" can be a space delimited list of these stats:"
		stats = get_player_stats "SomeFakePlayerName"
		stats.each do |stat|
			client.send_user_message message.actor, stat unless stat.eql? "ret_msg"
		end
	end

	def cmd_admin client, message

		text = message.message
		command = text.split(' ')[ 1 ]

		if !@players[ client ]
			@players[ client ] = Hash.new
		end

		mumbleNick = client.find_user_session( message.actor ).name

		if !@players[ client ].has_key?( mumbleNick )
			playerData = get_player_data( client, mumbleNick )
			admin = playerData[ "admin" ]
			aliasNick = playerData[ "aliasNick" ]
			muted = playerData[ "muted" ]
			elo = playerData[ "elo" ]
			playerName = playerData[ "playerName" ]
			level = playerData[ "level" ]
			player = Player.new( message.actor, mumbleNick, admin, aliasNick, muted, elo, playerName, level, nil, nil, nil, nil, nil )
			@players[ client ][ mumbleNick ] = player
		end

		case command
		when "login"
			cmd_admin_login( client, message )
		when "setchan"
			cmd_admin_setchan( client, message )
		when "setrole"
			cmd_admin_setrole( client, message )
		when "delrole"
			cmd_admin_delrole( client, message )
		when "playernum"
			cmd_admin_playernum( client, message )
		when "alias"
			cmd_admin_alias( client, message )
		when "come"
			cmd_admin_come( client, message )
		when "op"
			cmd_admin_op( client, message )
		when "result"
			cmd_admin_result( client, message )
		when "delete"
			cmd_admin_delete( client, message )
		else
			client.send_user_message message.actor, "Please specify an admin command."
		end

	end

	def help_msg_admin client, message
		text = message.message
		command = text.split(' ')[ 2 ]
		case command
		when "login"
			help_msg_admin_login( client, message )
		when "setchan"
			help_msg_admin_setchan( client, message )
		when "setrole"
			help_msg_admin_setrole( client, message )
		when "delrole"
			help_msg_admin_delrole( client, message )
		when "playernum"
			help_msg_admin_playernum( client, message )
		when "alias"
			help_msg_admin_alias( client, message )
		when "come"
			help_msg_admin_come( client, message )
		when "op"
			help_msg_admin_op( client, message )
		when "result"
			help_msg_admin_result( client, message )
		when "delete"
			help_msg_admin_delete( client, message )
		else
			client.send_user_message message.actor, "The following admin commands are available:"
			client.send_user_message message.actor, "!help admin \"command\" - detailed help on the admin command"
			client.send_user_message message.actor, "!admin login \"password\" - login as SuperUser"
			client.send_user_message message.actor, "!admin setchan \"role\" - set a channel's role"
			client.send_user_message message.actor, "!admin setrole \"role\" \"parameter\" - set a role"
			client.send_user_message message.actor, "!admin delrole \"role\" - delete a role"
			client.send_user_message message.actor, "!admin playernum \"number\" - set the required number of players per team"
			client.send_user_message message.actor, "!admin alias \"player\" \"alias\" - set a player's alias"
			client.send_user_message message.actor, "!admin come - make the bot move to your channel"
			client.send_user_message message.actor, "!admin op \"player\" - make \"player\" an admin"
			client.send_user_message message.actor, "!admin result \"match_id\" \"scores\"- set the result of a match"
			client.send_user_message message.actor, "!admin delete \"match_id\" - delete a match"
		end
	end

	def cmd_admin_login client, message
		text = message.message
		password = text.split(' ')[ 2 ]

		mumbleNick = client.find_user_session( message.actor ).name

		player = @players[ client ][ mumbleNick ]

		if password.eql? @connections[ client ][ :pass ]

			client.send_user_message message.actor, "Login accepted."

			if player.admin.eql? "SuperUser"

				client.send_user_message message.actor, "Already a SuperUser."
				return

			else

				player.admin = "SuperUser"

				@players[ client ][ mumbleNick ] = player

				if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )
					ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )
				else
					ini = Kesh::IO::Storage::IniFile.new
				end

				sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}:admin"
				ini.setValue( sectionName, player.mumbleNick, player.admin )

				ini.writeToFile( 'players.ini' )

			end

		else

			client.send_user_message message.actor, "Wrong password."

		end

	end

	def help_msg_admin_login client, message
		client.send_user_message message.actor, "Syntax: !admin login \"password\""
		client.send_user_message message.actor, "Logs you in to the bot as a SuperUser"
	end

	def cmd_admin_setchan client, message 

		mumbleNick = client.find_user_session( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			text = message.message
			chanPath = client.find_user( message.actor ).channel.path
			roles = text.split(' ')[ 2..-1 ]

			if !@rolesRequired[ client ]
				client.send_user_message message.actor, "No roles defined."
				return
			end

			if !roles.nil?
				roles.each do |role|
					if !@rolesRequired[ client ].has_key? role
						client.send_user_message message.actor, "Unknown role: '#{role}'."
						return
					end
				end
			end


			if @chanRoles[ client ]

				if @chanRoles[ client ].has_key? chanPath
					prevValue = @chanRoles[ client ][ chanPath ]
					if roles.nil?
						@chanRoles[ client ].delete chanPath
					else
						@chanRoles[ client ][ chanPath ] = roles
					end
				else
					@chanRoles[ client ].merge! chanPath => roles
				end

			else
				@chanRoles[ client ] = { chanPath => roles }
			end

			write_roles_ini client

			if prevValue
				if roles.nil?
					client.send_user_message message.actor, "Channel #{chanPath} removed (was '#{prevValue.join(' ')}')."
				else
					client.send_user_message message.actor, "Channel #{chanPath} changed from '#{prevValue.join(' ')}' to '#{roles.join(' ')}'."
				end
			else
				client.send_user_message message.actor, "Channel #{chanPath} set to '#{roles.join(' ')}'."
			end

		else
			client.send_user_message message.actor, "No admin privileges."
		end

	end

	def help_msg_admin_setchan client, message
		client.send_user_message message.actor, "Syntax: !admin setchan \"role\""
		client.send_user_message message.actor, "Sets the channel you are in to \"role\""
		client.send_user_message message.actor, "You can set multiple roles by separating them with a space"
	end

	def cmd_admin_setrole client, message

		mumbleNick = client.find_user_session( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			text = message.message
			chanPath = client.find_user( message.actor ).channel.path
			role = text.split(' ')[ 2 ]
			required = text.split(' ')[ 3 ]

			if ( required.nil? && @chanRoles[ client ] && @chanRoles[ client ][ chanPath ] && @chanRoles[ client ][ chanPath ].length == 1 )
				role = @chanRoles[ client ][ chanPath ].first
				required = text.split(' ')[ 2 ]
			end

			if required.nil?
				client.send_user_message message.actor, "Missing argument."
				return
			end

			required.upcase!

			if required.to_i.to_s != required && required != "T" && required != "Q"
				client.send_user_message message.actor, "Argument must be numeric, 'T' or 'Q'."
				return
			end

			if @rolesRequired[ client ]

				if @rolesRequired[ client ].has_key? role
					prevValue = @rolesRequired[ client ][ role ]
					@rolesRequired[ client ][ role ] = required
				else
					@rolesRequired[ client ].merge! role => required
				end

			else
				@rolesRequired[ client ] = { role => required }
			end

			write_roles_ini client

			if prevValue
				client.send_user_message message.actor, "Role #{role} changed from '#{prevValue}' to '#{required}'."
			else
				client.send_user_message message.actor, "Role #{role} set to '#{required}'."
			end

		else
			client.send_user_message message.actor, "No admin privileges."
		end

	end

	def help_msg_admin_setrole client, message
		client.send_user_message message.actor, "Syntax: !admin setrole \"role\" \"requirement\""
		client.send_user_message message.actor, "Create a new role with or sets an existing role to \"requirement\""
		client.send_user_message message.actor, "The \"requirement\" is:"
		client.send_user_message message.actor, "- the number of players with that role required per team"
		client.send_user_message message.actor, "- '-1' if the channel holds spectators"
		client.send_user_message message.actor, "- 'T' if the channel is a team channel"
		client.send_user_message message.actor, "- 'Q' if the channel is a queuing channel"
	end

	def cmd_admin_delrole client, message

		mumbleNick = client.find_user_session( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			text = message.message
			chanPath = client.find_user( message.actor ).channel.path
			role = text.split(' ')[ 2 ]

			if ( role.nil? && @chanRoles[ client ][ chanPath ] && @chanRoles[ client ][ chanPath ].length == 1 )
				role = @chanRoles[ client ][ chanPath ] 
			end

			if role.nil?
				client.send_user_message message.actor, "Missing argument."
				return
			end

			if !@rolesRequired[ client ].has_key? role
					client.send_user_message message.actor, "Unknown role: '#{role}'."
				return
			end

			@rolesRequired[ client ].delete rolesRequired

			write_roles_ini

			client.send_user_message message.actor, "Role deleted ('#{role}')."

		end

	end

	def help_msg_admin_delrole client, message
		client.send_user_message message.actor, "Syntax: !admin delrole \"role\""
		client.send_user_message message.actor, "Removes an existing role"
	end

	def cmd_admin_come client, message

		mumbleNick = client.find_user_session( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			chanPath = client.find_user( message.actor ).channel.path
			client.switch_channel chanPath

		else
			client.send_user_message message.actor, "No admin privileges."
		end

	end

	def help_msg_admin_come client, message
		client.send_user_message message.actor, "Syntax: !admin come"
		client.send_user_message message.actor, "Makes the bot join the channel you are in"
	end

	def cmd_admin_playernum client, message 

		mumbleNick = client.find_user_session( message.actor ).name
		
		if @players[ client ][ mumbleNick ].admin

			newPlayerNum = message.message.split(' ')[ 2 ].to_i

			if newPlayerNum.nil? || newPlayerNum == @defaultPlayerNum
				@playerNum.delete( client )
				write_roles_ini client
				client.send_user_message message.actor, "Required number of players set to default value ('#{@defaultPlayerNum}')."
			else
				@playerNum[ client ] = newPlayerNum
				write_roles_ini client
				client.send_user_message message.actor, "Required number of players set to '#{newPlayerNum}'."
			end

		else
			client.send_user_message message.actor, "No admin privileges."
		end

	end

	def help_msg_admin_playernum client, message
		client.send_user_message message.actor, "Syntax: !admin playernum \"number\""
		client.send_user_message message.actor, "Sets the required number of players per team"
	end

	def cmd_admin_alias client, message

		mumbleNick = client.find_user_session( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			text = message.message

			player = @players[ client ].values.select{ |v| v.mumbleNick.downcase.eql?( text.split(' ')[ 2 ].downcase ) }.first

			if player.nil?
				client.send_user_message message.actor, "Player #{text.split(' ')[ 2 ]} has to be in one of the PUG channels."
				return
			end

			aliasValue = text.split(' ')[ 3 ]
			aliasValue = aliasValue ? aliasValue : player.mumbleNick

			statsVals = get_player_stats( aliasValue, [ "Name", "Level" ] )

			if statsVals.nil?
				client.send_user_message message.actor, "Player #{aliasValue} has not been found in the TribesAPI, alias not set."
				return
			end

			aliasValue = statsVals.shift
			level = statsVals.shift

			oldPlayerName = player.playerName

			if player.aliasNick

				if aliasValue.downcase.eql? player.mumbleNick.downcase
					player.aliasNick = nil
					client.send_user_message message.actor, "Alias of #{player.mumbleNick} removed."
					client.send_user_message player.session, "Your alias has been reset to #{player.mumbleNick} by #{mumbleNick}."
				else
					player.aliasNick = aliasValue
					client.send_user_message message.actor, "Alias of #{player.mumbleNick} set to #{aliasValue}."
					client.send_user_message player.session, "Your alias has been set to #{aliasValue} by #{mumbleNick}."
				end

			else

				if aliasValue.downcase.eql? player.mumbleNick.downcase
					client.send_user_message message.actor, "Alias not set: equal to mumble username."
					return
				else
					player.aliasNick = aliasValue
					client.send_user_message message.actor, "Alias of #{player.mumbleNick} set to #{aliasValue}."
					client.send_user_message player.session, "Your alias has been set to #{aliasValue} by #{mumbleNick}."
				end

			end

			player.playerName = aliasValue
			player.level = level

			@players[ client ][ player.mumbleNick ] = player

			if player.match
				index = @matches.index{ |m| m.id.eql?( player.match ) }
				if @matches[ index ].players.has_key?( oldPlayerName )
					@matches[ index ].players[ player.playerName ] = @matches[ index ].players[ oldPlayerName ]
					@matches[ index ].players.delete( oldPlayerName )
				end
			end

			if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )
				ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )
			else
				ini = Kesh::IO::Storage::IniFile.new
			end

			sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}:aliases"

			if player.aliasNick
				ini.setValue( sectionName, player.mumbleNick, player.aliasNick )
			else
				ini.removeValue( sectionName, player.mumbleNick )
			end

			sectionName = "Muted"

			if !player.muted.eql?( @defaultMute )
				ini.removeValue( sectionName, oldPlayer.aliasNick ? oldPlayer.aliasNick : oldPlayer.mumbleNick )
				ini.setValue( sectionName, player.aliasNick ? player.aliasNick : player.mumbleNick, player.muted.to_s )
			end

			sectionName = "ELO"

			if !player.elo.nil? && !player.elo.eql?( 1000 )
				ini.removeValue( sectionName, oldPlayer.aliasNick ? oldPlayer.aliasNick : oldPlayer.mumbleNick )
				ini.setValue( sectionName, player.aliasNick ? player.aliasNick : player.mumbleNick, player.elo.to_s )
			end

			ini.writeToFile( 'players.ini' )

		else
			client.send_user_message message.actor, "No admin privileges."
		end

	end

	def help_msg_admin_alias client, message
		client.send_user_message message.actor, "Syntax: !admin alias \"mumble_nick\" \"alias\""
		client.send_user_message message.actor, "Sets \"mumble_nick\"'s alias to \"alias\""
	end

	def cmd_admin_op client, message

		mumbleNick = client.find_user_session( message.actor ).name

		if @players[ client ][ mumbleNick ].admin
	
			text = message.message

			player = @players[ client ].values.select{ |v| v.mumbleNick.downcase.eql?( text.split(' ')[ 2 ].downcase ) }.first

			if player.nil?
				client.send_user_message message.actor, "Player #{text.split(' ')[ 2 ]} has to be in one of the PUG channels."
				return
			end

			if player.admin.eql?( "SuperUser" ) || player.admin.eql?( "Admin" )

				client.send_user_message message.actor, "Already a #{player.admin}."
				return

			else

				player.admin = "Admin"

				@players[ client ][ mumbleNick ] = player

				if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )
					ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )
				else
					ini = Kesh::IO::Storage::IniFile.new
				end

				sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}:admin"
				ini.setValue( sectionName, player.mumbleNick, player.admin )

				ini.writeToFile( 'players.ini' )

			end


		else
			client.send_user_message message.actor, "No admin privileges."
		end

	end

	def help_msg_admin_op client, message
		client.send_user_message message.actor, "Syntax: !admin op \"mumble_nick\""
		client.send_user_message message.actor, "Makes \"mumble_nick\" an admin if you are a SuperUser"
	end

	def cmd_debug client, message
		if @players[ client ]
			@players[ client ].each_pair do |session, player|
				client.send_user_message message.actor, "Player: #{player.playerName}, level: #{player.level}, roles: #{player.roles}, match: #{player.match}, team: #{player.team}"
			end
		else
			client.send_user_message message.actor, "No players registered"
		end
		if @matches
			@matches.each do |match|
				players = []
				match.players.each_pair do |playerName, team|
					players << "#{playerName}(#{team})"
				end
				results = ""
				if match.results.length > 0
					results << ", results:"
					match.results.each do |res|
						results << " #{res.scores.join('-')}"
					end
				end
			client.send_user_message message.actor, "Id: #{match.id}, status: #{match.status}, players: #{players.join(', ')}#{results}"
			end
		else
			client.send_user_message message.actor, "No matches registered - this is not good!"
		end
	end

	def cmd_mute client, message 

		text = message.message
		mumbleNick = client.find_user_session( message.actor ).name

		if !@players[ client ] || !@players[ client ].has_key?( mumbleNick )
			client.send_user_message message.actor, "You need to join one of the PUG channels set the mute level."
			return
		end

		player = @players[ client ][ mumbleNick ]

		nick = player.aliasNick ? player.aliasNick : player.mumbleNick

		muteValue = text.split(' ')[ 1 ]

		if muteValue 
			if muteValue.to_i.to_s != muteValue
				client.send_user_message message.actor, "The mute level has to be numeric: 0(off), 1(default) or 2(all muted)."
				return
			else
				muteValue = muteValue.to_i
			end
		else
			muteValue = player.muted + 1
			if muteValue > 2
				muteValue = 0
			end
		end

		if muteValue.eql?( player.muted )
			client.send_user_message message.actor, "No change in mute level."
			return
		end

		player.muted = muteValue

		@players[ client ][ mumbleNick ] = player

		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )
			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )
		else
			ini = Kesh::IO::Storage::IniFile.new
		end

		sectionName = "Muted"

		if player.muted.eql?( @defaultMute )
			ini.removeValue( sectionName, nick )
		else
			ini.setValue( sectionName, nick, player.muted.to_s )
		end

		ini.writeToFile( 'players.ini' )

		client.send_user_message message.actor, "Mute level set to #{player.muted.to_s}."

	end

	def help_msg_mute client, message
		client.send_user_message message.actor, "Syntax: !mute on/off"
		client.send_user_message message.actor, "Mute the bots spam messages from 0 (no mute) to 2 (all muted)"
	end

	def cmd_result client, message
		text = message.message
		if text.split(' ').length == 1
			client.send_user_message message.actor, "You need to enter at least one score."
			return
		end
		mumbleNick = client.find_user_session( message.actor ).name

		if !@players[ client ] || !@players[ client ].has_key?( mumbleNick )
			client.send_user_message message.actor, "You need to join one of the PUG channels set a result."
			return
		end

		player = @players[ client ][ mumbleNick ]

		match = @matches.select{ |m| m.status.eql?( "Pending" ) && m.players.has_key?( player.playerName ) }.first

		if match.nil?
			match = @matches.select{ |m| m.status.eql?( "Started" ) && m.players.has_key?( player.playerName ) }.first
		end

		if match

			scores = text.split(' ')[ 1..-1 ]
			ownTeam = match.players[ player.playerName ]

			scores.each do |score|
				ownScore = score.split('-')[0]
				otherScore = score.split('-')[1]
				result = Result.new
				result.teams = match.teams
				result.scores = Array.new
				if result.teams[0].eql?( ownTeam )
					result.scores << ownScore
					result.scores << otherScore
				else
					result.scores << otherScore
					result.scores << ownScore
				end
				match.results << result
			end

			match.status = "Finished"
			index = @matches.index{ |m| m.id.eql?( match.id ) }
			@matches[ index ] = match

			write_matches_ini

		else

			client.send_user_message message.actor, "No match found. Maybe the match has already been reported."

		end

	end

	def help_msg_result client, message
		client.send_user_message message.actor, "Syntax: !result \"scores\""
		client.send_user_message message.actor, "\"scores\" are the scores for all maps in form \"ourcaps\"-\"theircaps\" separated by a space."
	end

	def cmd_admin_result client, message
		text = message.message
		matchId = text.split(' ')[ 2 ]
		scores = text.split(' ')[ 3..-1 ]

		if matchId.nil?
			client.send_user_message message.actor, "You need to enter a match id and at least one score."
			return
		elsif scores.nil?
			client.send_user_message message.actor, "You need to enter at least one score."
			return
		end

		if matchId.to_i.to_s != matchId
			client.send_user_message message.actor, "The match id has to be numerical."
			return
		end
		matchId = matchId.to_i

		mumbleNick = client.find_user_session( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			match = @matches.select{ |m| m.id.eql?( matchId ) }.first

			if match

				firstTeam = match.teams[ 0 ]

				scores.each do |score|
					firstScore = score.split('-')[0]
					secondScore = score.split('-')[1]
					result = Result.new
					result.teams = match.teams
					result.scores = Array.new
					if result.teams[0].eql?( ownTeam )
						result.scores << firstScore
						result.scores << secondScore
					else
						result.scores << secondScore
						result.scores << firstScore
					end
					match.results << result
				end

				match.status = "Finished"
				index = @matches.index{ |m| m.id.eql?( match.id ) }
				@matches[ index ] = match

				write_matches_ini

			else

				client.send_user_message message.actor, "No match with id \"#{matchId}\" found."

			end

		else
			client.send_user_message message.actor, "No admin privileges."
		end

	end

	def help_msg_admin_result client, message
		client.send_user_message message.actor, "Syntax: !admin result \"match_id\" \"scores\""
		client.send_user_message message.actor, "Sets the \"scores\" of \"match_id\" for all maps in form \"ourcaps\"-\"theircaps\" separated by a space."
	end

	def cmd_admin_delete client, message
		text = message.message
		matchId = text.split(' ')[ 2 ]

		if matchId.nil?
			client.send_user_message message.actor, "You need to enter a match id."
			return
		end

		if matchId.to_i.to_s != matchId
			client.send_user_message message.actor, "The match id has to be numerical."
			return
		end
		matchId = matchId.to_i

		mumbleNick = client.find_user_session( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			index = @matches.index{ |m| m.id.eql?( match.id ) }
			match = @matches[ index ]

			if match

				if match.status.eql?( "Signup" ) 
					client.send_user_message message.actor, "Can't delete the current signup match."
					return
				end

				@players[ client ].select{ |mN, pl| pl.match.eql?( matchId ) }.each_key do |mN|
					@players[ client ][ mN ].match = @currentMatch[ client ]
				end
				
				match.status = "Deleted"
				@matches[ index ] = match

				write_matches_ini

				@matches.delete_at( index )

			else

				client.send_user_message message.actor, "No match with id \"#{matchId}\" found."

			end

		else
			client.send_user_message message.actor, "No admin privileges."
		end

	end

	def help_msg_admin_delete client, message
		client.send_user_message message.actor, "Syntax: !admin delete \"match_id\""
		client.send_user_message message.actor, "Delete match with id \"match_id\"."
	end

	def cmd_list client, message
		text = message.message
		matchId = text.split(' ')[ 1 ]

		if matchId.to_i.to_s != matchId
			client.send_user_message message.actor, "The match id has to be numerical."
			return
		end
		matchId = matchId.to_i

		if matchId.nil?
			selection = @matches
		else
			selection = @matches.select{ |m| m.id.eql?( matchId ) }
		end

		if selection
			selection.each do |match|
				players = []
				match.players.each_pair do |playerName, team|
					players << "#{playerName}(#{team})"
				end
				results = ""
				if match.results.length > 0
					results << ", results:"
					match.results.each do |res|
						results << " #{res.scores.join('-')}"
					end
				end
			client.send_user_message message.actor, "Id: #{match.id}, status: #{match.status}, players: #{players.join(', ')}#{results}"
			end
		else
			client.send_user_message message.actor, "No match found."
		end
	end

	def help_msg_list client, message
		client.send_user_message message.actor, "Syntax: !list"
		client.send_user_message message.actor, "Shows all registered matches"
	end

	def get_player_stats nick, *stats
		if nick != "SomeFakePlayerName"
			query = Kesh::TribesAPI::TribesAPI.new( @options[ :base_url ], @options[ :devId ], @options[ :authKey ] )
			result = query.send_method( "getplayer", nick )

			stats = stats.first

			statsVals = Array.new
			stats.each do |stat|
				statsVals << result[ stat ]
			end
			return statsVals
		else
			query = Kesh::TribesAPI::TribesAPI.new( @options[ :base_url ], @options[ :devId ], @options[ :authKey ] )
			result = query.send_method( "getplayer", "Player" )
			stats = result.keys
			return stats
		end
	rescue
		return
	end

	def write_roles_ini client

		sectionNameBase = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}"

		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/roles.ini' ) )
			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'roles.ini' )
		else
			ini = Kesh::IO::Storage::IniFile.new
		end

		sectionName = "#{sectionNameBase}:roles"

		ini.removeSection( sectionName )
		ini.addSection( sectionName )

		if @playerNum[ client ]
			ini.setValue( sectionName, "PlayerNum", @playerNum[ client ].to_s )
		end

		@rolesRequired[ client ].each_pair do |role, value|
			ini.setValue( sectionName, role, value )
		end

		sectionName = "#{sectionNameBase}:channels"

		ini.removeSection( sectionName )

		if @chanRoles[ client ]
			ini.addSection( sectionName )

			@chanRoles[ client ].each_pair do |channel, value|
				ini.setValue( sectionName, channel, value.join(',') )
			end
		end

		ini.writeToFile( 'roles.ini' )
	end

	def load_roles_ini client
		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/roles.ini' ) )

			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'roles.ini' )

			sectionNameBase = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}"

			sectionName = "#{sectionNameBase}:roles"
			section = ini.getSection( sectionName )

			if section
				rolesHash = Hash.new

				section.values.each do |value|
					if value.name.eql? "PlayerNum"
						@playerNum[ client ] = value.value.to_i
					else
						rolesHash[ value.name ] = value.value
					end
				end

				@rolesRequired[ client ] = rolesHash
			end

			sectionName = "#{sectionNameBase}:channels"
			section = ini.getSection( sectionName )

			if section
				channelsHash = Hash.new

				section.values.each do |value|
					channelsHash[ value.name ] = value.value.split(',')
				end

				@chanRoles[ client ] = channelsHash
			end

		end
	end

	def write_matches_ini
		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/matches.ini' ) )
			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'matches.ini' )
			FileUtils.cp( 'matches.ini', 'matches.bak' )
		else
			ini = Kesh::IO::Storage::IniFile.new
		end

		@matches.each do |match|

			next if ( match.status.eql?( "Signup") || match.status.eql?( "Picking") )

			sectionName = "#{match.id}"
			ini.removeSection( sectionName )

			ini.setValue( sectionName, "Status", match.status )
			if match.date
				ini.setValue( sectionName, "Date", match.date.utc.to_s )
			end
			ini.setValue( sectionName, "Teams", match.teams.join( " " ) )

			match.teams.each do |team|
				playerNames = match.players.select{ |pN, t| t.eql?( team ) }.keys
				ini.setValue( sectionName, "#{team}", playerNames.join( " " ) )
			end

			ini.setValue( sectionName, "Comment", match.comment )
			ini.setValue( sectionName, "ResultCount", match.results.length.to_s )

			match.results.each_index do |r|
				result = match.results[ r ]
				ini.setValue( sectionName, "Result#{r.to_s}Map", "#{result.map}")
				result.teams.each_index do |t|
					ini.setValue( sectionName, "Result#{r.to_s}#{result.teams[ t ]}", "#{result.scores[ t ]}")
				end
				ini.setValue( sectionName, "Result#{r.to_s}Comment", "#{result.comment}")
			end

		end

		ini.writeToFile( 'matches.ini' )
	end

	def load_matches_ini
		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/matches.ini' ) )

			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'matches.ini' )

			ini.sections.each do |section|

				id = section.name

				if ( id[ /^\d+$/ ] == nil )
					puts "Invalid ID: " + id.to_s
					raise SyntaxError
				end

				idInt = id.to_i
				@nextMatchId = ( idInt + 1 ) if ( idInt >= @nextMatchId )

				status = section.getValue( "Status" )
				next unless ( status.eql?( "Started" ) || status.eql?( "Pending" ) )

				date = Time.parse( section.getValue( "Date" ) )

				# if ( date == nil )
				# 	puts "Invalid Date: " + section.getValue( 'Date' ).to_s
				# 	raise SyntaxError
				# end

				players = Hash.new

				teams = section.getValue( "Teams" )

				if teams.nil?
					teams = Array.new
				else
					teams = teams.split( ' ' )

					teams.each do |team|

						playerNames = section.getValue( "#{team}" )

						if !playerNames.nil?
							playerNames = playerNames.split( ' ' )
							playerNames.each do |pN|
								players[ pN ] = team
							end
						end

					end

				end

				comment = section.getValue( "Comment" )
				resultCount = section.getValue( "ResultCount" )

				if ( resultCount[ /^\d+$/ ] == nil )
					puts "Invalid Result Count: " + resultCount.to_s
					raise SyntaxError
				end

				results = Array.new

				rCount = resultCount.to_i
				rIndex = 0

				while ( rIndex < rCount )

					rMap = section.getValue( "Result#{rIndex}Map")
					rTeams = teams
					rScores = Array.new

					match.teams.each do |team|
						rScores << section.getValue( "Result#{rIndex}#{team}" ).to_i
					end

					rComment = section.getValue( "Result#{rIndex}Comment")

					results << Result.new( rMap, rTeams, rScores, rComment )

					rIndex = rIndex + 1

				end

				@matches << Match.new( idInt, status, date, teams, players, comment, results )

			end

		end

	end

	def get_player_data client, mumbleNick

		session = client.find_user( mumbleNick ).session

		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )

			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )

			sectionNameBase = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}"

			sectionName = "#{sectionNameBase}:admin"
			admin = ini.getValue( sectionName, mumbleNick )

			sectionName = "#{sectionNameBase}:aliases"
			aliasNick = ini.getValue( sectionName, mumbleNick )

			nick = aliasNick ? aliasNick : mumbleNick

			sectionName = "Muted"
			muted = ini.getValue( sectionName, nick )
			if muted
				muted = muted.to_i
			else
				muted = @defaultMute
			end

			sectionName = "ELO"
			elo = ini.getValue( sectionName, nick )

		else

			nick = mumbleNick

		end

		stats = Array.new
		stats << "Name"
		stats << "Level"

		statsVals = get_player_stats( nick, stats )

		if statsVals.nil?
			playerName = nick
			level = "unknown"
		else
			playerName = statsVals.shift
			level = statsVals.shift
		end

		return { "session" => session, "mumbleNick" => mumbleNick, "admin" => admin, "aliasNick" => aliasNick, "muted" => muted, "elo" => elo, "playerName" => playerName, "level" => level }

	end

	def message_all client, message, importance, *exclude

		if @players[ client ]
			@players[ client ].each_pair do |mumbleNick, player|
				next if player.muted >= importance
				next if exclude && exclude.include?( player.session )
				client.send_user_message( player.session, message )
			end
		end

	end

end