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

	def on_user_changed client, message

		# FIXME: joining server in a monitored channel: sign-up but also "You left the PuG/mixed channels."

		return if client.find_user_session( message.session ).name.eql? @connections[ client ][ :nick ]

		if defined?( message.channel_id )
			chanPath = client.channels[ message.channel_id ].path
		end

		mumbleNick = client.find_user_session( message.session ).name

		return unless @chanRoles[ client ]

		prevRolesNeeded = check_requirements client
		prevPlayersNeeded = prevRolesNeeded.shift

		noTeams = @teamNum[ client ] ? @teamNum[ client ] : @defaultTeamNum

		match = @matches[ @currentMatch[ client ] ]

		if ( defined?( chanPath ) && @chanRoles[ client ].has_key?( chanPath ) )
			# In a monitored channel

			roles = @chanRoles[ client ][ chanPath ]

			if ( @players[ client ] && @players[ client ].has_key?( message.session ) )
				# Already signed up

				player = @players[ client ][ message.session ]

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

						player.team = roles.first
						player.match = @currentMatch[ client ]

						if match.teams.include?( player.team )

							match.players << player
							messagePlayer = "You joined team '#{player.team}'."
							messageAll = "Player #{player.playerName} (level: #{player.level}) joined team '#{player.team}'."

						else

							match.teams << player.team
							match.players << player
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
					match.players.each do |player|
						if @players[ client ][ player.session] && @players[ client ][ player.session].team.nil?
							match.players.delete( player )
						end
					end

					# Clean up emtpy teams
					match.teams.each do |team|
						if match.players.select{|player| player.team.eql? team}.empty?
							match.teams.delete( team )
						end
					end

				end

			else
				# New Signup

				playerData = get_player_data( client, message.session )
				admin = playerData[ "admin" ]
				aliasNick = playerData[ "aliasNick" ]
				muted = playerData[ "muted" ]
				elo = playerData[ "elo" ]
				playerName = playerData[ "playerName" ]
				level = playerData[ "level" ]
				player = Player.new( message.session, mumbleNick, admin, aliasNick, muted, elo, playerName, level, nil, nil, nil, roles, nil )

				firstRoleReq = @rolesRequired[ client ][ roles.first ]

				if  firstRoleReq.to_i < 0
					# Became spectator

					messagePlayer = "You became a spectator."
					messageAll = "Player #{player.playerName} (level: #{player.level}) became a spectator."

				elsif firstRoleReq.eql? "T"

					player.team = roles.first
					player.match = @currentMatch[ client ]

					if match.teams.include?( player.team )

						match.players << player
						messagePlayer = "You joined team '#{player.team}'."
						messageAll = "Player #{player.playerName} (level: #{player.level}) joined team '#{player.team}'."

					else

						match.teams << player.team
						match.players << player
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

			@players[ client ][ message.session ] = player
			@matches[ @currentMatch[ client ] ] = match

		else
			# Not in a monitored channel

			return unless @players[ client ] && @players[ client ].has_key?( message.session )

			player = @players[ client ][ message.session ]

			messagePlayer = "You left the PuG/mixed channels."
			messageAll = "Player #{player.playerName} (level: #{player.level}) left."

			@players[ client ].delete message.session

		end

		if defined?( chanPath ) && !player.muted
			client.send_user_message( message.session, messagePlayer )
		end

		message_all( client, messageAll, message.session )

		if match.status.eql?( "Picking" )

			teamsPicked = 0
			playerNum = @playerNum[ client ] ? @playerNum[ client ] : @defaultPlayerNum

			match.teams.each do |team|
				if match.players.select{ |player| player.team.eql?( team ) }.length >= playerNum
					teamsPicked += 1
				end
			end

			if teamsPicked >= noTeams

				@matches[ @currentMatch[ client ] ].status = "Started"
				message_all( client, "The teams are picked, match (id: #{match.id}) started." )

				# Create new match
				previousMatch = @currentMatch[ client ]
				create_new_match
				@currentMatch[ client ] = @matches.length - 1
				match = @matches[ @currentMatch[ client ] ]

				# Move everyone over to the new match apart from picked players
				@players[ client ].each_pair do |session, player|
					if player.team.nil?
						@players[ client ][ session ].match = @currentMatch[ client ]
					end
				end

			end

		end

		if match.status.eql?( "Signup" )

			rolesNeeded = check_requirements client
			playersNeeded = rolesNeeded.shift

			if prevPlayersNeeded >0 && playersNeeded > 0
				return

			elsif prevPlayersNeeded <= 0 && playersNeeded > 0
				message_all( client, "No longer enough players to start a match." )

			elsif ( prevPlayersNeeded > 0 && playersNeeded <= 0 ) || !rolesNeeded.eql?( prevRolesNeeded ) 

				if rolesNeeded.empty?
					message_all( client, "Enough players and all required roles are most likely covered. Start picking!" )
				else
					message_all( client, "Enough players but missing #{rolesNeeded.join(' and ')}" )
				end
				
			end

		end

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
			client.register_handler :UserState, method( :on_user_changed )
			client.register_handler :UserRemove, method( :on_user_changed )
			# client.register_handler :UDPTunnel, method( :on_audio )
			client.register_text_handler "!help", method( :cmd_help )
			client.register_text_handler "!find", method( :cmd_find )
			client.register_text_handler "!goto", method( :cmd_goto )
			client.register_text_handler "!test", method( :cmd_test )
			client.register_text_handler "!info", method( :cmd_info )
			client.register_text_handler "!admin", method( :cmd_admin )
			client.register_text_handler "!mute", method( :cmd_mute )

			load_roles_ini client
			# load_matches_ini client # FIXME: not per connection but overall

			create_new_match
			@currentMatch[ client ] = @matches.length - 1

			client.connect

		end

		while connected? do
			sleep 0.2
		end
	end

	private

	def create_new_match
		id = @nextMatchId
		@nextMatchId += 1
		status = "Signup"
		date = ""
		teams = Array.new
		players = Array.new
		comment= ""
		result = Array.new
		match = Match.new( id, status, date, teams, players, comment )
		@matches << match
	end

	def check_requirements client

		noTeams = @teamNum[ client ] ? @teamNum[ client ] : @defaultTeamNum
		playersNeeded = @playerNum[ client ] ? @playerNum[ client ] * noTeams : @defaultPlayerNum * noTeams

		rolesToFill = @rolesRequired[ client ].inject({}) do |h,(role, value)| 
			h[ role ] = value.to_i * noTeams
			h
		end

		if @players[ client ]

			signups = @players[ client ].select { |session,player| player.match.eql? @currentMatch[ client ] }

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
		when "admin"
			help_msg_admin( client, message )
		else
			client.send_user_message message.actor, "The following commands are available:"
			client.send_user_message message.actor, "!help \"command\" - detailed help on the command"
			client.send_user_message message.actor, "!find \"mumble_nick\" - find which channel someone is in"
			client.send_user_message message.actor, "!goto \"mumble_command\" - move yourself to someone's channel"
			client.send_user_message message.actor, "!info \"tribes_nick\" \"stat\" - detailed stats on player"
			client.send_user_message message.actor, "!mute - mute the bots spam messages"
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

		if @players[ client ]
			if @players[ client ][ message.actor ]
				if @players[ client ][ message.actor ].aliasNick
					ownNick = @players[ client ][ message.actor ].aliasNick
				else
					ownNick = client.find_user( message.actor ).name
				end
			else
				ownNick = client.find_user( message.actor ).name
			end
		else
			ownNick = client.find_user( message.actor ).name
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

		if ( statsVals.nil? && nick != own_nick )

			stats.insert( 2, nick.split('_').map!( &:capitalize ).join('_') )
			statsVals = get_player_stats( own_nick, stats )

			if statsVals.nil?
				client.send_user_message message.actor, "Player #{own_nick} not found."
				return
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

		if !@players[ client ].has_key?( message.actor )
			mumbleNick = client.find_user_session( message.actor ).name
			playerData = get_player_data( client, message.actor )
			admin = playerData[ "admin" ]
			aliasNick = playerData[ "aliasNick" ]
			muted = playerData[ "muted" ]
			elo = playerData[ "elo" ]
			playerName = playerData[ "playerName" ]
			level = playerData[ "level" ]
			player = Player.new( message.actor, mumbleNick, admin, aliasNick, muted, elo, playerName, level, nil, nil, nil, nil, nil )
			@players[ client ][ message.actor ] = player
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
		end
	end

	def cmd_admin_login client, message
		text = message.message
		password = text.split(' ')[ 2 ]

		player = @players[ client ][ message.actor ]

		if password.eql? @connections[ client ][ :pass ]

			client.send_user_message message.actor, "Login accepted."

			if player.admin.eql? "SuperUser"

				client.send_user_message message.actor, "Already a SuperUser."
				return

			else

				player.admin = "SuperUser"

				@players[ client ][ message.actor ] = player

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

		if @players[ client ][ message.actor ].admin

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

		if @players[ client ][ message.actor ].admin

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

			if required.to_i.to_s != required && ( required != "T" || required != "Q" )
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

		if @players[ client ][ message.actor ].admin

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

		if @players[ client ][ message.actor ].admin

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
		
		if @players[ client ][ message.actor ].admin

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

		if @players[ client ][ message.actor ].admin

			text = message.message

			player = @players[ client ].values.select{ |v| v.mumbleNick.downcase.eql?( text.split(' ')[ 2 ].downcase ) }.first

			if player.nil?
				client.send_user_message message.actor, "Player #{text.split(' ')[ 2 ]} has to be in one of the PUG channels."
				return
			end

			aliasValue = text.split(' ')[ 3 ]
			aliasValue = aliasValue ? aliasValue : player.mumbleNick

			if player.aliasNick

				prevValue = player.aliasNick

				if aliasValue.downcase.eql? player.mumbleNick.downcase
					player.aliasNick = nil
					client.send_user_message message.actor, "Alias of #{player.mumbleNick} removed."
					client.send_user_message player.session, "Your alias has been reset to #{player.mumbleNick} by #{@players[ client ][ message.actor ].mumbleNick}."
				else
					player.aliasNick = aliasValue
					client.send_user_message message.actor, "Alias of #{player.mumbleNick} set to #{aliasValue}."
					client.send_user_message player.session, "Your alias has been set to #{aliasValue} by #{@players[ client ][ message.actor ].mumbleNick}."
				end

			else

				if aliasValue.downcase.eql? player.mumbleNick.downcase
					client.send_user_message message.actor, "Alias not set: equal to mumble username."
					return
				else
					player.aliasNick = aliasValue
					client.send_user_message message.actor, "Alias of #{player.mumbleNick} set to #{aliasValue}."
					client.send_user_message player.session, "Your alias has been set to #{aliasValue} by #{@players[ client ][ message.actor ].mumbleNick}."
				end

			end

			playerData = get_player_data( client, player.session)
			playerName = playerData[ "playerName" ]
			level = playerData[ "level" ]

			@players[ client ][ player.session ] = player

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

		if @players[ client ][ message.actor ].admin
	
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

				@players[ client ][ message.actor ] = player

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

	def cmd_mute client, message 

		text = message.message

		if !@players[ client ] || !@players[ client ].has_key?( message.actor )
			client.send_user_message message.actor, "You need to join one of the PUG channels to (un)mute."
			return
		end

		player = @players[ client ][ message.actor ]

		nick = player.aliasNick ? player.aliasNick : player.mumbleNick

		muteValue = text.split(' ')[ 1 ]

		if muteValue.nil? 
			muteValue = player.muted.nil? ? "True" : "False" 
		end

		muteValue.capitalize!

		case muteValue
		when "On"
			muteValue = "True"
		when "Off"
			muteValue = "False"
		else
			if !muteValue.eql?( "True" ) && !muteValue.eql?( "False" )
				client.send_user_message message.actor, "Unknown setting, use On/Off."
				return
			end
		end

		if player.muted.nil?

			if muteValue.eql? "False"
				client.send_user_message message.actor, "No change, still not muted."
				return
			else
				player.muted = "True"
				client.send_user_message message.actor, "Muted."
			end

		else

			if muteValue.eql? "False"
				player.muted = nil
				client.send_user_message message.actor, "No longer muted."
			else
				client.send_user_message message.actor, "Still muted."
				return
			end

		end

		@players[ client ][ message.actor ] = player

		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )
			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )
		else
			ini = Kesh::IO::Storage::IniFile.new
		end

		sectionName = "Muted"

		if player.muted
			ini.setValue( sectionName, player.mumbleNick, player.muted )
		else
			ini.removeValue( sectionName, player.mumbleNick )
		end

		ini.writeToFile( 'players.ini' )

	end

	def help_msg_mute client, message
		client.send_user_message message.actor, "Syntax: !mute on/off"
		client.send_user_message message.actor, "Mute or unmutes the bot's spam messages"
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

	def get_player_data client, session

		mumbleNick = client.find_user_session( session ).name

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

	def message_all client, message, *exclude

		if @players[ client ]
			@players[ client ].each_pair do |session, player|
				next if player.muted.eql?( "True" )
				next if exclude && exclude.include?( player.session )
				client.send_user_message( player.session, message )
			end
		end

	end

end