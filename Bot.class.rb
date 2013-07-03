require 'time'
require 'cgi'
# require 'speech'
# require 'celt-ruby'

requireLibrary 'IO'
requireLibrary 'Mumble'
requireLibrary 'TribesAPI'
requireLibrary 'ELO'


Player = Struct.new( :session, :mumbleNick, :admin, :aliasNick, :muted, :elo, :noMatches, :playerName, :level, :tag, :noCaps, :noMaps, :match, :roles, :team )
Match = Struct.new( :id, :label, :status, :date, :teams, :players, :comment, :results, :perfELO, :idsAPI )
Result = Struct.new( :map, :teams, :scores, :comment )

class Bot

	def initialize options
		@shutdown = false
		@restart = false
		@clientCount = 0
		@options = options
		@connections = Hash.new
		@chanRoles = Hash.new
		@rolesRequired = Hash.new
		@defaultTeamNum = 2
		@teamNum = Hash.new
		@defaultPlayerNum = 7
		@playerNum = Hash.new
		# [Hash<(MumbleClient, Hash<(String, Player)>)>]
		@players = Hash.new
		@currentMatch = Hash.new
		@nextMatchId = 0
		# [Array<(Match)>]
		@matches = Array.new
		@defaultMute = 1
		@moveQueue = Hash.new
		@query = Kesh::TribesAPI::TribesAPI.new( @options[ :base_url ], @options[ :devId ], @options[ :authKey ] )
		@eloCalculator = Kesh::ELO::ELOCalculator.new
		@lastCleanUp = Time.now
		@lastTrack = Time.now

		load_matches_ini
	end

	def exit_by_user
		puts ''
		puts 'user exited bot.'
		if @connections.keys.first
			@connections.keys.first.debug
		end
	end

	def all_connected?
		connected = true
		@connections.each_key do |client|
			connected = connected && client.connected?
		end
		return connected
	end

	def on_connected client, message
		client.switch_channel @connections[ client ][ :channel ]
	end
	

	def on_user_state client, message
		# Check whether it is the bot itself
		if client.find_user( message.session ).name.eql? @connections[ client ][ :nick ]
			if message.instance_variable_get( '@values' ).has_key?( :channel_id )
				client.switch_channel @connections[ client ][ :channel ]
				return
			end
		end

		# Check if there is a channel change
		return unless message.instance_variable_get( '@values' ).has_key?( :channel_id )

		session = message.session
		chanPath = client.channels[ message.channel_id ].path

		change_user( client, session, chanPath )
	end

	def on_user_remove client, message
		# Check whether it is the bot itself
		user = client.find_user( message.session )
		return if user.nil?
		return if user.name.eql? @connections[ client ][ :nick ]

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

			@clientCount += 1

			client = Kesh::Mumble::MumbleClient.new( server[:host], server[:port], server[:nick], @options )
			@connections[ client ] = server

			client.register_handler :ServerSync, method( :on_connected )
			client.register_handler :UserState, method( :on_user_state )
			client.register_handler :UserRemove, method( :on_user_remove )
			# client.register_handler :UDPTunnel, method( :on_audio )

			client.register_text_handler '!help', method( :cmd_help )
			client.register_text_handler '!find', method( :cmd_find )
			client.register_text_handler '!goto', method( :cmd_goto )
			client.register_text_handler '!test', method( :cmd_test )
			client.register_text_handler '!info', method( :cmd_info )
			client.register_text_handler '!admin', method( :cmd_admin )
			client.register_text_handler '!mute', method( :cmd_mute )
			client.register_text_handler '!result', method( :cmd_result )
			client.register_text_handler '!list', method( :cmd_list )

			client.register_exception_handler method( :on_exception )

			load_roles_ini client

			create_new_match( client )

			client.connect

			create_comment( client )

		end

		# Main loop
		until @shutdown do

			if ( Time.now - @lastCleanUp ) > 60 * 60
				remove_old_matches
				@lastCleanUp = Time.now
			end


			if ( Time.now - @lastTrack ) > 60
				track_matches
				@lastTrack = Time.now
			end

			return true unless all_connected? # TODO: This is a very ugly way to reset all connections

			sleep 0.2

		end

		return @restart

	end

	private

	def create_comment client
		comment = String.new
		comment << '<center>-=[ SkeeveBot ]=-</center><HR>'
		comment << '<code>!mute 0/1/2/3</code> [ from 0 (no mute) to 3 (all muted) ]<BR>'
		comment << '<code>!result map1 map2 map3</code> [ use BE-DS for each map ]<BR>'
		comment << '<code>!list</code> [ shows all matches in the last 24h ]'

		match = @matches.select{ |m| m.id.eql?( @currentMatch[ client ] ) }.first
		comment << "<HR>Current status: #{match.status}<BR>"

		rolesNeeded = check_requirements( client )
		playersNeeded = rolesNeeded.shift

		if playersNeeded > 0
			comment << "Not enough players to start a match. Missing #{playersNeeded} player(s)."
		elsif rolesNeeded.empty?
			comment << 'Enough players and all required roles are most likely covered. Start picking!'
		else
			comment << "Enough players but missing #{rolesNeeded.join(' and ')}."
		end

		unless @players[ client ].nil? || @players[ client ].select{ |mN, pl| pl.match.eql?( @currentMatch[ client ] ) }.empty?
			comment << '<HR><TABLE BORDER="0"><TR><TD>Signups</TD><TD>Team</TD></TR>'
			signups = @players[ client ].select{ |mN, pl| pl.match.eql?( @currentMatch[ client ] ) }
			signups.each_value do |pl|
				comment << '<TR>'
				name = String.new
				name << "[#{pl.tag}]" if ( pl.tag  && !pl.tag.eql?( '' ) )
				name << convert_symbols_to_html( pl.playerName )
				roles = convert_symbols_to_html( pl.roles.join('/') )
				comment << "<TD>#{name}(level: #{pl.level}): #{roles}</TD>"
				if pl.team.nil?
					comment << '<TD>&nbsp;</TD></TR>'
				else
					comment << "<TD>#{pl.team}</TD></TR>"
				end
			end
			comment << '</TABLE>'
		end

		selection = Array.new
		selection = selection | @matches.select{ |m| m.label.eql?( @connections[ client ][ :label ] ) && !m.status.eql?( 'Deleted' ) && !m.id.eql?( @currentMatch[ client ] ) }
		unless selection.empty?
			
			comment << '<HR>Recent matches (percentage is prediction accuracy):<TABLE BORDER="0"><TR><TD>Id</TD><TD>Date</TD><TD>Time</TD><TD>Status</TD>'
			comment << "<TD>#{selection.first.teams.join('</TD><TD>')}</TD><TD>Result</TD></TR>"

			selection.each do |recentMatch|
				comment << "<TR><TD>#{recentMatch.id}</TD><TD>#{recentMatch.date.strftime('%d/%m')}</TD><TD>#{recentMatch.date.strftime('%H:%M')}</TD>"
				comment << "<TD>#{recentMatch.status}</TD>"

				recentMatch.teams.each do |team|
					players = recentMatch.players.select{ |pN, t| t.eql?( team ) }.keys
					playersStr = convert_symbols_to_html( players.join(', ') )
					comment << "<TD>#{playersStr}</TD>"
				end

				
				if recentMatch.results.empty?
					if recentMatch.idsAPI.empty?
						if recentMatch.status.eql?( 'Started')
							comment << '<TD>started</TD>'
						else
							comment << '<TD>pending</TD>'
						end
					else
						idStrs = Array.new
						recentMatch.idsAPI.each_index do |i|
							idStrs << "<A HREF=\"https://account.hirezstudios.com/tribesascend/match-details.aspx?match=#{recentMatch.idsAPI[i]}\">#{i+1}</A>"
						end
						comment << "<TD>map #{idStrs.join(',')}</TD>"
					end
				else
					results = Array.new
					recentMatch.results.each_index do |i|
						res = recentMatch.results[i]
						id = recentMatch.idsAPI[i]
						unless id.nil?
							results << "<A HREF=\"https://account.hirezstudios.com/tribesascend/match-details.aspx?match=#{recentMatch.idsAPI[i]}\">#{res.scores.join('-')}</A>"
						else
							results << "#{res.scores.join('-')}"
						end
					end
					comment << "<TD>#{results.join(' ')}"
					unless recentMatch.perfELO.nil?
						percent = ( recentMatch.perfELO * 100 ).round
						comment << " (#{percent}%)"
					end
					comment << '</TD>'
				end
				comment << '</TR>'
			end
			comment << '</TABLE>'
		end
		comment << '<HR>Documentation: <A HREF="http://iredfoxi.github.io/SkeeveBot/"><CODE>http://iredfoxi.github.io/SkeeveBot/</CODE></A>'

		client.set_comment( comment )
	end		

	def on_exception client, message
		server = @connections[ client ]
		serverStr = "#{server[ :host ]}:#{server[ :port ]}"

		@connections.keys.each do |cl|

			admins = @players[ cl ].select{ |mN, pl| pl.admin.eql?( 'SuperUser' ) }

			unless admins.empty?
				admins.each_value do |pl|
					cl.send_user_message( pl.session, "(#{serverStr}) #{message}" )
				end
			end

		end

	end

	def remove_old_matches
		@matches.each do|match|
			if !match.date.nil? &&  ( Time.now - match.date ) > 24 * 60 * 60
				@matches.delete( match )
			end
		end
	end

	def track_matches

		changed = Array.new

		@matches.each do |match|

			next unless match.status.eql?( "Started" )

			client = @connections.select{ |cl, svr| match.label.eql?( svr[ :label] ) }.keys.first

			next unless track_match( client, match )

			changed << client unless changed.include?( client )

		end

		changed.each do |client|
			create_comment( client )
		end

	end

	def track_match client, match

		players = Array.new
		match.players.each_key do |pN|
			players << @players[ client ].select{ |m, p| p.playerName.downcase.eql?( pN.downcase ) }.values.first
		end

		matchIdsMatrix = Array.new
		players.each do |player|
			ids = get_player_matches( player.playerName, match.date )
			next if ids.nil?
			matchIdsMatrix << ids
		end

		return false if matchIdsMatrix.empty?

		noPlayersAPI = matchIdsMatrix.length

		combIdsAPI = Array.new
		matchIdsMatrix.each do |ids|
			combIdsAPI += ids
		end

		idsAPI = combIdsAPI.uniq

		idsAPI.each do |id|
			idsAPI.delete( id ) if ( combIdsAPI.count( id ) / noPlayersAPI ) < 0.5
		end

		idsAPI.sort!

		return false if idsAPI.eql?( match.idsAPI )

		match.idsAPI = idsAPI

		return true

	end

	def change_user client, session, *chanPath

		return unless @chanRoles[ client ]

		mumbleNick = client.find_user( session ).name

		prevRolesNeeded = check_requirements( client )
		prevPlayersNeeded = prevRolesNeeded.shift

		noTeams = @teamNum[ client ] ? @teamNum[ client ] : @defaultTeamNum

		match = @matches.select{ |m| m.id.eql?( @currentMatch[ client ] ) }.first

		monitoredChannel = false
		unless chanPath.empty?
			chanPath = chanPath.first
			if @chanRoles[ client ].has_key?( chanPath )
				monitoredChannel = true
			else
				baseChannel = ''
				@chanRoles[ client ].each_key do |channel|
					if chanPath.include?( channel )
						if channel.length > baseChannel.length
							baseChannel = channel
							monitoredChannel = true
						end
					end
				end
				chanPath = baseChannel if monitoredChannel
			end				
		end

		if monitoredChannel
			# In a monitored channel

			roles = @chanRoles[ client ][ chanPath ]

			if @players[ client ] && @players[ client ].has_key?( mumbleNick )
				# Already signed up

				player = @players[ client ][ mumbleNick ]
				oldMatchId = player.match

				if player.roles.eql?( roles ) && player.team.nil?
					# No change in role

					return

				else
					# Role changed

					firstRoleReq = @rolesRequired[ client ][ roles.first ]

					name = String.new
					name << "[#{player.tag}]" if ( player.tag  && !player.tag.eql?( '' ) )
					name << convert_symbols_to_html( player.playerName )					

					if  firstRoleReq.to_i < 0
						# Became spectator

						player.roles = roles
						player.team = nil
						player.match = nil
						messagePlayer = 'You became a spectator.'
						messageAll = "Player #{name} (level: #{player.level}) became a spectator."

					elsif firstRoleReq.eql? 'T'
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
							next unless match.status.eql?( 'Started' )
							if match.players.select{ |pN, t| pN.downcase.eql?( player.playerName.downcase ) }.length > 0
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
								if !id.nil? && id != @currentMatch[ client ]
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
							messageAll = "Player #{name} (level: #{player.level}) joined team '#{player.team}'."

						else

							match.teams << player.team
							match.teams = match.teams.sort
							match.players[ player.playerName ] = player.team
							messagePlayer = "You became captain of team '#{player.team}'."
							messageAll = "Player #{name} (level: #{player.level}) became captain of team '#{player.team}'."
							if match.teams.length >= noTeams
								match.status = 'Picking'
								messageAll << ' Picking has started!'
							end

						end

						if !@moveQueue[ client ] && match.status.eql?( 'Picking' )
							if @players[ client ].select{ |mN, pl| pl.match.eql?( match.id ) && pl.team.nil? }.length == 0
								@moveQueue[ client ] = true
							end
						end

					elsif firstRoleReq.eql? 'Q'
						# Joined a queue channel

						player.roles = roles
						player.team = nil
						player.match = @currentMatch[ client ]
						messagePlayer = 'You joined the queue.'
						messageAll = "Player #{name} (level: #{player.level}) joined the queue."

					else
						# Joined one of the roles channels
						
						jumpingQueue = !player.match.eql?( @currentMatch[ client ] )
						player.roles = roles
						player.team = nil
						player.match = @currentMatch[ client ]

						if match.status.eql?( 'Picking' ) && !@moveQueue[ client ] && jumpingQueue
							messagePlayer = 'Picking has already started. Please join the queue.'
							messageAll = "Player #{name} (level: #{player.level}) jumped the queue."
						else
							messagePlayer = "Your role(s) changed to '#{roles.join(' ')}'."
							messageAll = "Player #{name} (level: #{player.level}) changed role(s) to '#{roles.join(' ')}'."
						end

					end

					# Clean up players
					match.players.each_key do |plName|
						muNick = @players[ client ].select{ |m, p| p.playerName.downcase.eql?( plName.downcase ) }.keys.first
						if muNick && @players[ client ][ muNick ].team.nil?
							match.players.delete( plName )
						end
					end

					# Clean up emtpy teams
					match.teams.each do |team|
						unless match.players.has_value?( team )
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
				admin = playerData[ :admin ]
				aliasNick = playerData[ :aliasNick ]
				muted = playerData[ :muted ]
				elo = playerData[ :elo ]
				noMatches = playerData[ :noMatches ]
				playerName = playerData[ :playerName ]
				level = playerData[ :level ]
				tag = playerData[ :tag ]
				player = Player.new( session, mumbleNick, admin, aliasNick, muted, elo, noMatches, playerName, level, tag, nil, nil, nil, roles, nil )

				firstRoleReq = @rolesRequired[ client ][ roles.first ]

				name = String.new
				name << "[#{player.tag}]" if ( player.tag  && !player.tag.eql?( '' ) )
				name << convert_symbols_to_html( player.playerName )

				if  firstRoleReq.to_i < 0
					# Became spectator

					messagePlayer = 'You became a spectator.'
					messageAll = "Player #{name} (level: #{player.level}) became a spectator."

				elsif firstRoleReq.eql? 'T'

					# Player returning to a running game
					@matches.each do |match|
						next unless match.status.eql?( 'Started' )
						if match.players.select{ |pN, t| pN.downcase.eql?( player.playerName.downcase ) }.length > 0
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
							if !id.nil? && id != @currentMatch[ client ]
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
						messagePlayer = "You joined team '#{player.team}'. You should probably join one of the roles channels first."
						messageAll = "Player #{name} (level: #{player.level}) joined team '#{player.team}'."

					else

						match.teams << player.team
						match.teams = match.teams.sort
						match.players[ player.playerName ] = player.team
						messagePlayer = "You became captain of team '#{player.team}'. You should probably join one of the roles channels first."
						messageAll = "Player #{name} (level: #{player.level}) became captain of team '#{player.team}'."
						noTeams = @teamNum[ client ] ? @teamNum[ client ] : @defaultTeamNum
						if match.teams.length >= noTeams
							match.status = 'Picking'
							messagePlayer << ' Picking has started!'
							messageAll << ' Picking has started!'
						end

					end

				elsif firstRoleReq.eql? 'Q'
					# Joined a queue channel

					player.roles = roles
					player.team = nil
					player.match = @currentMatch[ client ]
					messagePlayer = 'You joined the queue.'
					messageAll = "Player #{name} (level: #{player.level}) joined the queue."

				else
					#Joined one of the roles channels

					player.roles = roles
					player.team = nil
					player.match = @currentMatch[ client ]

					if match.status.eql?( 'Picking' ) && !@moveQueue[ client ]
						messagePlayer = 'Picking has already started. Please join the queue.'
						messageAll = "Player #{name} (level: #{player.level}) jumped the queue."
					else
						messagePlayer = "You signed up with role(s) '#{roles.join(' ')}'."
						messageAll = "Player #{name} (level: #{player.level}) signed up with role(s) '#{roles.join(' ')}'."
					end

				end
				
				if @players[ client ].nil?
					@players[ client ] = Hash.new
				end

				if player.muted < 2
					client.send_user_message( player.session, 'Welcome to the PUG channels. Message me "!help" for an overview of commands. Mute me with "!mute"' )
				end

				if player.muted < 3
					# Important announcements here and reset players mute level from 3 to 2
					# client.send_user_message( player.session, "!!!IMPORTANT ANNOUNCEMENT!!!" )
				end
			end

			@players[ client ][ mumbleNick ] = player
			index = @matches.index{ |m| m.id.eql?( @currentMatch[ client ] ) }
			@matches[ index ] = match

		else
			# Not in a monitored channel

			return unless @players[ client ] && @players[ client ].has_key?( mumbleNick )

			player = @players[ client ][ mumbleNick ]
			id = player.match

			match.players.delete( player.playerName )
			@players[ client ].delete( mumbleNick )

			# Clean up emtpy teams
			match.teams.each do |team|
				unless match.players.has_value?( team )
					match.teams.delete( team )
				end
			end

			# If leaving a match, check if it is over
			unless id.nil?
				check_match_over( client, id )
			end

			name = String.new
			name << "[#{player.tag}]" if ( player.tag  && !player.tag.eql?( '' ) )
			name << convert_symbols_to_html( player.playerName )
			messagePlayer = 'You left the PuG/mixed channels.'
			messageAll = "Player #{name} (level: #{player.level}) left."

		end

		if defined?( chanPath ) && player.muted < 1
			client.send_user_message( player.session, messagePlayer )
		end

		message_all( client, messageAll, [ nil, @currentMatch[ client ] ], 1, player.session )

		if match.status.eql?( 'Picking' )

			if match.players.length < noTeams
				@matches.select{ |m| m.id.eql?( match.id ) }.first.status = 'Signup'
			end

			teamsPicked = 0
			playerNum = @playerNum[ client ] ? @playerNum[ client ] : @defaultPlayerNum

			match.teams.each do |team|
				if match.players.select{ |pN, t| t.eql?( team ) }.length >= playerNum
					teamsPicked += 1
				end
			end

			if teamsPicked >= noTeams

				index = @matches.index{ |m| m.id.eql?( @currentMatch[ client ] ) }
				@matches[ index ].status = 'Started'
				@matches[ index ].date = Time.now
				message_all( client, "The teams are picked, match (id: #{match.id}) started.", [ nil, @currentMatch[ client ] ], 2 )

				# # Record number of maps played by each player
				# match.players.each_key do |pN|
				# 	player = @players[ client ].select{ |m, p| p.playerName.downcase.eql?( pN.downcase ) }.values.first
				# 	statsVals = get_player_stats( player.playerName, [ 'Matches_Completed' ] )
				# 	player.noMaps = statsVals.shift unless statsVals.nil?
				# end

				# Create new match
				create_new_match( client )
				match = @matches.select{ |m| m.id.eql?( @currentMatch[ client ] ) }.first

				# Move everyone over to the new match apart from picked players
				@players[ client ].each_pair do |mumbleNick, player|
					if player.team.nil? && !player.match.nil?
						@players[ client ][ mumbleNick ].match = @currentMatch[ client ]
					end
				end

				write_matches_ini

			end

		end

		if match.status.eql?( 'Signup' )

			rolesNeeded = check_requirements( client )
			playersNeeded = rolesNeeded.shift

			if prevPlayersNeeded >0 && playersNeeded > 0
				# Still needing more players

			elsif prevPlayersNeeded <= 0 && playersNeeded > 0
				message_all( client, 'No longer enough players to start a match.', [ nil, @currentMatch[ client ] ], 2 )

			elsif ( prevPlayersNeeded > 0 && playersNeeded <= 0 ) || !rolesNeeded.eql?( prevRolesNeeded ) 

				if rolesNeeded.empty?
					message_all( client, 'Enough players and all required roles are most likely covered. Start picking!', [ nil, @currentMatch[ client ] ], 2 )
				else
					message_all( client, "Enough players but missing #{rolesNeeded.join(' and ')}", [ nil, @currentMatch[ client ] ], 2 )
				end
				
			end

		end

		create_comment( client )

	end

	def check_match_over client, matchId

		return if matchId.nil?

		index = @matches.index{ |m| m.id.eql?( matchId ) }
		match = @matches[ index ]

		return unless match.status.eql?( 'Started' )

		stillPlaying = 0

		match.players.each_key do |plName|
			player = @players[ client ].select{ |m, p| p.playerName.downcase.eql?( plName.downcase ) }.values.first
			if player && player.match.eql?( matchId )
				stillPlaying += 1
			end
		end

		return if stillPlaying > match.players.keys.length / 2

		@matches[ index ].status = 'Pending'

		message_all( client, "Your match (id: #{match.id}) seems to be over. Please report the result (check my comment for help).", [ matchId ], 2 )

		track_match( client, match )

		write_matches_ini

		create_comment( client )

	end

	def create_new_match client
		id = @nextMatchId
		@nextMatchId += 1
		label = @connections[ client ][ :label ]
		status = 'Signup'
		date = nil
		teams = Array.new
		players = Hash.new
		comment= ''
		result = Array.new
		perfELO = nil
		idsAPI = Array.new
		match = Match.new( id, label, status, date, teams, players, comment, result, perfELO, idsAPI )
		@matches << match
		@currentMatch[ client ] = id
		@moveQueue[ client ] = false
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
		text = convert_symbols_from_html( message.message )
		command = text.split(' ')[ 1 ]

		unless command.nil?

			case command.downcase
			when 'find'
				help_msg_find( client, message )
				return
			when 'goto'
				help_msg_goto( client, message )
				return
			when 'info'
				help_msg_info( client, message )
				return
			when 'mute'
				help_msg_mute( client, message )
				return
			when 'result'
				help_msg_result( client, message )
				return
			when 'list'
				help_msg_list( client, message )
				return
			when 'admin'
				help_msg_admin( client, message )
				return
			else
				client.send_user_message message.actor, "Unknown command '#{command}'"
			end

		end

		client.send_user_message message.actor, 'The following commands are available:'
		client.send_user_message message.actor, '!help "command" - detailed help on the command'
		client.send_user_message message.actor, '!find "mumble_nick" - find which channel someone is in'
		client.send_user_message message.actor, "!goto \"mumble_nick\" - move yourself to someone's channel"
		client.send_user_message message.actor, '!info "tribes_nick" "stat" - detailed stats on player'
		client.send_user_message message.actor, '!mute - 0/1/2/3 - mute the bots spam messages from 0 (no mute) to 3 (all muted)'
		client.send_user_message message.actor, '!result "map1" "map2" "map3"- sets the result of your last match'
		client.send_user_message message.actor, '!list - shows the latest matches'
		client.send_user_message message.actor, '!admin "command" - admin commands'
	end

	def cmd_find client, message
		text = convert_symbols_from_html( message.message )
		nick = text.split(' ')[ 1 ]

		playerName = nil

		user = client.find_user( nick )

		if user.nil?

			player = nil

			if @players[ client ]
				player = @players[ client ].select{ |mN, pl| pl.playerName.downcase.eql?( nick.downcase ) }.values.first
			end

			if player.nil?

				if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )
					ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )

					sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}:aliases"
					section = ini.getSection( sectionName )

					found = false
					client.users.values.each do |u|
						break if found
						if section.hasValue?( CGI::escape(u.name) )
							playerName = section.getValue( CGI::escape(u.name) )
							if playerName.downcase.eql?( nick.downcase )
								user = u
								found = true
							end
						end
					end
				end

			else

				user = client.find_user( player.mumbleNick )
				playerName = player.playerName

			end

		end
		
		if user
			if playerName.nil?
				client.send_user_message message.actor, "Player '#{user.name}' is in channel '#{user.channel.path}'"
			else
				client.send_user_message message.actor, "Player '#{playerName}' found using name '#{user.name}' in channel '#{user.channel.path}'"
			end
		else
			client.send_user_message message.actor, "There is no user '#{nick}' on the Server"
		end
	end

	def help_msg_find client, message
		client.send_user_message message.actor, 'Syntax: !find "nick"'
		client.send_user_message message.actor, "Returns \"nick\"'s channel. \"nick\" can be a mumble nick or a player name."
	end

	def cmd_goto client, message
		text = convert_symbols_from_html( message.message )
		nick = text.split(' ')[ 1 ]
		target = client.find_user nick
		source = client.find_user message.actor
		client.move_user source, target.channel
	end

	def help_msg_goto client, message
		client.send_user_message message.actor, 'Syntax: !goto "mumble_nick"'
		client.send_user_message message.actor, "The bot tries to move you to \"mumble_nick\"'s. Fails if the bot doesn't have sufficient rights"
	end

	def cmd_test client, message
		client.channels.each do |id, ch|
			client.send_acl id
		end
	end

	# @param client [MumbleClient] The mumble client.
	def cmd_info client, message

		mumbleNick = client.find_user( message.actor ).name
		ownNick = mumbleNick

		if @players[ client ] && @players[ client ].has_key?( mumbleNick ) && @players[ client ][ mumbleNick ].aliasNick
			ownNick = @players[ client ][ mumbleNick ].aliasNick
		end

		text = convert_symbols_from_html( message.message )

		nick = text.split(' ')[ 1 ]
		nick = nick.nil? ? ownNick : nick

		if @players[ client ]
			playersNick = @players[ client ].values.select{ |v| v.mumbleNick.downcase.eql?( nick.downcase ) }
			if playersNick.length > 0 && playersNick.first.aliasNick
				nick = playersNick.first.aliasNick
			end
		end

		stats = Array.new
		stats << 'Name'
		stats << 'Level'
		stats << 'Tag'
		noDefaultStats = stats.length
		stats.push( *text.split(' ')[ 2..-1 ] )
		stats.map! do |stat|
			stat.split('_').map!( &:capitalize ).join('_')
		end

		statsVals = get_player_stats( nick, stats )

		if statsVals.nil? && nick != ownNick

			stats.insert( noDefaultStats, nick.split('_').map!( &:capitalize ).join('_') )
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

		if stats[ noDefaultStats ] == nick && statsVals[ noDefaultStats ].nil?
			client.send_user_message message.actor, "Player #{nick} not found."
		else
			name = statsVals.shift
			level = statsVals.shift
			tag = statsVals.shift
			stats.shift( noDefaultStats )

			name = "[#{tag}]#{name}" unless tag.empty?
			client.send_user_message message.actor, "Player #{name} has level #{level}."
			
			while (stat = stats.shift)
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
		client.send_user_message message.actor, 'Syntax !info'
		client.send_user_message message.actor, 'Returns your tag, playername and level based on your mumble nick'
		client.send_user_message message.actor, 'Syntax !info "stat"'
		client.send_user_message message.actor, 'As above, but also shows your additional statistic "stat"'
		client.send_user_message message.actor, 'Syntax !info "tribes_nick"'
		client.send_user_message message.actor, "Returns \"nick\"'s tag, playername and level, searching for his alias if set"
		client.send_user_message message.actor, 'Syntax !info "tribes_nick" "stat"'
		client.send_user_message message.actor, "As above but also shows \"tribes_nick\"'s \"stat\""
		client.send_user_message message.actor, '"stat" can be a space delimited list of these stats:'
		stats = get_player_stats( 'SomeFakePlayerName' )
		stats.each do |stat|
			client.send_user_message message.actor, stat unless stat.eql? 'ret_msg'
		end
	end

	def cmd_admin client, message

		text = convert_symbols_from_html( message.message )
		command = text.split(' ')[ 1 ]

		unless @players[ client ]
			@players[ client ] = Hash.new
		end

		mumbleNick = client.find_user( message.actor ).name

		unless @players[ client ].has_key?( mumbleNick )
			playerData = get_player_data( client, mumbleNick )
			admin = playerData[ :admin ]
			aliasNick = playerData[ :aliasNick ]
			muted = playerData[ :muted ]
			elo = playerData[ :elo ]
			noMatches = playerData[ :noMatches ]
			playerName = playerData[ :playerName ]
			level = playerData[ :level ]
			tag = playerData[ :tag ]
			player = Player.new( message.actor, mumbleNick, admin, aliasNick, muted, elo, noMatches, playerName, level, tag, nil, nil, nil, nil, nil )
			@players[ client ][ mumbleNick ] = player
		end

		if command.nil?

			client.send_user_message message.actor, 'Please specify an admin command.'

		else

			case command.downcase
			when 'login'
				cmd_admin_login( client, message )
			when 'setchan'
				cmd_admin_setchan( client, message )
			when 'setrole'
				cmd_admin_setrole( client, message )
			when 'delrole'
				cmd_admin_delrole( client, message )
			when 'playernum'
				cmd_admin_playernum( client, message )
			when 'alias'
				cmd_admin_alias( client, message )
			when 'come'
				cmd_admin_come( client, message )
			when 'op'
				cmd_admin_op( client, message )
			when 'result'
				cmd_admin_result( client, message )
			when 'delete'
				cmd_admin_delete( client, message )
			when 'shutdown'
				cmd_admin_shutdown( client, message )
			when 'restart'
				cmd_admin_restart( client, message )
			when 'eval'
				cmd_admin_eval( client, message )
			when 'debug'
				cmd_admin_debug( client, message )
			else
				client.send_user_message message.actor, "Unknown admin command '#{command}'."
			end

		end

	end

	def help_msg_admin client, message
		text = convert_symbols_from_html( message.message )
		command = text.split(' ')[ 2 ]

		unless command.nil?

			case command.downcase
			when 'login'
				help_msg_admin_login( client, message )
				return
			when 'setchan'
				help_msg_admin_setchan( client, message )
				return
			when 'setrole'
				help_msg_admin_setrole( client, message )
				return
			when 'delrole'
				help_msg_admin_delrole( client, message )
				return
			when 'playernum'
				help_msg_admin_playernum( client, message )
				return
			when 'alias'
				help_msg_admin_alias( client, message )
				return
			when 'come'
				help_msg_admin_come( client, message )
				return
			when 'op'
				help_msg_admin_op( client, message )
				return
			when 'result'
				help_msg_admin_result( client, message )
				return
			when 'delete'
				help_msg_admin_delete( client, message )
				return
			else
				client.send_user_message message.actor, "Unknown admin command '#{command}':"
			end

		end

		client.send_user_message message.actor, 'The following admin commands are available:'
		client.send_user_message message.actor, '!help admin "command" - detailed help on the admin command'
		client.send_user_message message.actor, '!admin login "password" - login as SuperUser'
		client.send_user_message message.actor, "!admin setchan \"role\" - set a channel's role"
		client.send_user_message message.actor, '!admin setrole "role" "parameter" - set a role'
		client.send_user_message message.actor, '!admin delrole "role" - delete a role'
		client.send_user_message message.actor, '!admin playernum "number" - set the required number of players per team'
		client.send_user_message message.actor, "!admin alias \"player\" \"alias\" - set a player's alias"
		client.send_user_message message.actor, '!admin come - make the bot move to your channel'
		client.send_user_message message.actor, '!admin op "player" - make "player" an admin'
		client.send_user_message message.actor, '!admin result "match_id" "scores"- set the result of a match'
		client.send_user_message message.actor, '!admin delete "match_id" - delete a match'

	end

	def cmd_admin_shutdown client, message
		mumbleNick = client.find_user( message.actor ).name 

		if @players[ client ][ mumbleNick ].admin.eql?('SuperUser')
			client.send_user_message message.actor, 'Shutting down...'
			@shutdown = true
		else
			client.send_user_message message.actor, 'Not enough admin privileges.'
		end
	end

	def cmd_admin_restart client, message
		mumbleNick = client.find_user( message.actor ).name 

		if @players[ client ][ mumbleNick ].admin.eql?('SuperUser')
			client.send_user_message message.actor, 'Restarting...'
			@restart = true
			@shutdown = true
		else
			client.send_user_message message.actor, 'Not enough admin privileges.'
		end
	end

	def cmd_admin_raise client, message
		text = convert_symbols_from_html( message.message )
		exception = text.split(' ')[ 2..-1 ].join(' ')

		mumbleNick = client.find_user( message.actor ).name

		if @players[ client ][ mumbleNick ].admin.eql?('SuperUser')
			client.send_user_message message.actor, "Raising an exception: #{exception}"
			raise exception
		end
	end

	def cmd_admin_login client, message
		text = convert_symbols_from_html( message.message )
		password = text.split(' ')[ 2 ]

		mumbleNick = client.find_user( message.actor ).name

		player = @players[ client ][ mumbleNick ]

		if password.eql? @connections[ client ][ :pass ]

			client.send_user_message message.actor, 'Login accepted.'

			if player.admin.eql? 'SuperUser'

				client.send_user_message message.actor, 'Already a SuperUser.'
				return

			else

				player.admin = 'SuperUser'

				@players[ client ][ mumbleNick ] = player

				if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )
					ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )
				else
					ini = Kesh::IO::Storage::IniFile.new
				end

				sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}:admin"
				ini.setValue( sectionName, CGI::escape(player.mumbleNick), player.admin )

				ini.writeToFile( 'players.ini' )

			end

		else

			client.send_user_message message.actor, 'Wrong password.'

		end

	end

	def help_msg_admin_login client, message
		client.send_user_message message.actor, 'Syntax: !admin login "password"'
		client.send_user_message message.actor, 'Logs you in to the bot as a SuperUser'
	end

	def cmd_admin_setchan client, message 

		mumbleNick = client.find_user( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			text = convert_symbols_from_html( message.message )
			chanPath = client.find_user( message.actor ).channel.path
			roles = text.split(' ')[ 2..-1 ]

			unless @rolesRequired[ client ]
				client.send_user_message message.actor, 'No roles defined.'
				return
			end

			unless roles.empty?
				roles.each do |role|
					unless @rolesRequired[ client ].has_key? role
						client.send_user_message message.actor, "Unknown role: '#{role}'."
						return
					end
				end
			end

			prevValue = nil

			if @chanRoles[ client ]

				if @chanRoles[ client ].has_key? chanPath
					prevValue = @chanRoles[ client ][ chanPath ]
					if roles.empty?
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
				if roles.empty?
					client.send_user_message message.actor, "Channel #{chanPath} removed (was '#{prevValue.join(' ')}')."
				else
					client.send_user_message message.actor, "Channel #{chanPath} changed from '#{prevValue.join(' ')}' to '#{roles.join(' ')}'."
				end
			else
				client.send_user_message message.actor, "Channel #{chanPath} set to '#{roles.join(' ')}'."
			end

		else
			client.send_user_message message.actor, 'No admin privileges.'
		end

	end

	def help_msg_admin_setchan client, message
		client.send_user_message message.actor, 'Syntax: !admin setchan "role"'
		client.send_user_message message.actor, 'Sets the channel you are in to "role"'
		client.send_user_message message.actor, 'You can set multiple roles by separating them with a space'
	end

	def cmd_admin_setrole client, message

		mumbleNick = client.find_user( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			text = convert_symbols_from_html( message.message )
			chanPath = client.find_user( message.actor ).channel.path
			role = text.split(' ')[ 2 ]
			required = text.split(' ')[ 3 ]

			if required.nil? && @chanRoles[ client ] && @chanRoles[ client ][ chanPath ] && @chanRoles[ client ][ chanPath ].length == 1
				role = @chanRoles[ client ][ chanPath ].first
				required = text.split(' ')[ 2 ]
			end

			if required.nil?
				client.send_user_message message.actor, 'Missing argument.'
				return
			end

			required.upcase!

			if required.to_i.to_s != required && required != 'T' && required != 'Q'
				client.send_user_message message.actor, "Argument must be numeric, 'T' or 'Q'."
				return
			end

			prevValue = nil

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
			client.send_user_message message.actor, 'No admin privileges.'
		end

	end

	def help_msg_admin_setrole client, message
		client.send_user_message message.actor, 'Syntax: !admin setrole "role" "requirement"'
		client.send_user_message message.actor, 'Create a new role with or sets an existing role to "requirement"'
		client.send_user_message message.actor, 'Where "requirement" is one of:'
		client.send_user_message message.actor, '- the number of players with that role required per team'
		client.send_user_message message.actor, "- '-1' if the channel holds spectators"
		client.send_user_message message.actor, "- 'T' if the channel is a team channel"
		client.send_user_message message.actor, "- 'Q' if the channel is a queuing channel"
	end

	def cmd_admin_delrole client, message

		mumbleNick = client.find_user( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			text = convert_symbols_from_html( message.message )
			chanPath = client.find_user( message.actor ).channel.path
			role = text.split(' ')[ 2 ]

			if role.nil? && @chanRoles[ client ][ chanPath ] && @chanRoles[ client ][ chanPath ].length == 1
				role = @chanRoles[ client ][ chanPath ] 
			end

			if role.nil?
				client.send_user_message message.actor, 'Missing argument.'
				return
			end

			unless @rolesRequired[ client ].has_key? role
					client.send_user_message message.actor, "Unknown role: '#{role}'."
				return
			end

			@rolesRequired[ client ].delete( role )

			write_roles_ini client

			client.send_user_message message.actor, "Role deleted ('#{role}')."

		end

	end

	def help_msg_admin_delrole client, message
		client.send_user_message message.actor, 'Syntax: !admin delrole "role"'
		client.send_user_message message.actor, 'Removes an existing role'
	end

	def cmd_admin_come client, message

		mumbleNick = client.find_user( message.actor ).name

		if @players[ client ][ mumbleNick ].admin
			@connections[ client ][ :channel ] = client.find_user( message.actor ).channel.path
			client.switch_channel @connections[ client ][ :channel ]
		else
			client.send_user_message message.actor, 'No admin privileges.'
		end

	end

	def help_msg_admin_come client, message
		client.send_user_message message.actor, 'Syntax: !admin come'
		client.send_user_message message.actor, 'Makes the bot join the channel you are in'
	end

	def cmd_admin_playernum client, message 

		mumbleNick = client.find_user( message.actor ).name
		
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
			client.send_user_message message.actor, 'No admin privileges.'
		end

	end

	def help_msg_admin_playernum client, message
		client.send_user_message message.actor, 'Syntax: !admin playernum "number"'
		client.send_user_message message.actor, 'Sets the required number of players per team'
	end

	def cmd_admin_alias client, message

		mumbleNick = client.find_user( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			text = convert_symbols_from_html( message.message )

			parameterStr = text.split(' ')[ 2..-1 ].join(' ')
			parameters = parameterStr.scan(/(?:"(?:\\.|[^"])*"|[^" ])+/)

			unless parameters.length.eql?( 2 )
				client.send_user_message message.actor, 'This command needs two parameters: the mumble nick and the alias you want to set.'
				return
			end

			target = parameters[0].gsub( "\"", '' )

			player = @players[ client ].values.select{ |v| v.mumbleNick.downcase.eql?( target.downcase ) }.first

			if player.nil?
				client.send_user_message message.actor, "Player #{target} has to be in one of the PUG channels."
				return
			end

			aliasValue = parameters[1].gsub( "\"", '' )
			aliasValue = aliasValue ? aliasValue : player.mumbleNick

			statsVals = get_player_stats( aliasValue, [ 'Name', 'Level', 'Tag' ] )

			if statsVals.nil?
				client.send_user_message message.actor, "Player #{aliasValue} not found or unable to connect to TribesAPI, alias not set."
				return
			end

			aliasValue = statsVals.shift
			level = statsVals.shift
			tag = statsVals.shift

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
					client.send_user_message message.actor, 'Alias not set: equal to mumble username.'
					return
				else
					player.aliasNick = aliasValue
					client.send_user_message message.actor, "Alias of #{player.mumbleNick} set to #{aliasValue}."
					client.send_user_message player.session, "Your alias has been set to #{aliasValue} by #{mumbleNick}."
				end

			end

			player.playerName = aliasValue
			player.level = level
			player.tag = tag

			@players[ client ][ player.mumbleNick ] = player

			@matches.each_index do |i|
				pName = @matches[ i ].players.select{ |pN, t| pN.downcase.eql?( oldPlayerName.downcase ) }.keys.first
				next if pName.nil?
				@matches[ i ].players[ player.playerName ] = @matches[ i ].players[ pName ]
				@matches[ i ].players.delete( pName )
			end

			write_matches_ini

			if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/matches.ini' ) )
				ini = Kesh::IO::Storage::IniFile.loadFromFile( 'matches.ini' )

				updated = false

				ini.sections.each do |section|

					id = section.name

					if id[ /^\d+$/ ].nil?
						puts 'Invalid ID: ' + id.to_s
						raise SyntaxError
					end

					next unless section.getValue( 'Label' ).eql?( @connections[ client ][ :label ] )

					teams = section.getValue( 'Teams' )
					next if teams.nil?

					players = Hash.new

					teams = teams.split( ' ' )
					teams.each do |team|

						playerNamesStr = section.getValue( "#{team}" )

						if playerNamesStr && playerNamesStr.include?( CGI::escape( oldPlayerName ) )
							playerNamesStr.gsub!( CGI::escape( oldPlayerName ), CGI::escape(player.aliasNick ? player.aliasNick : player.mumbleNick) )
							section.removeValue( "#{team}" )
							section.setValue( "#{team}", playerNamesStr )
							updated = true
						end

					end

				end

				ini.writeToFile( 'matches.ini' ) if updated

			end

			if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )
				ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )
			else
				ini = Kesh::IO::Storage::IniFile.new
			end

			sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}:aliases"

			if player.aliasNick
				ini.setValue( sectionName, CGI::escape(player.mumbleNick), CGI::escape(player.aliasNick) )
			else
				ini.removeValue( sectionName, CGI::escape(player.mumbleNick) )
			end

			sectionName = 'Muted'

			unless player.muted.eql?( @defaultMute )
				ini.removeValue( sectionName, CGI::escape(oldPlayerName) )
				ini.setValue( sectionName, CGI::escape(player.aliasNick ? player.aliasNick : player.mumbleNick), player.muted.to_s )
			end

			sectionName = 'ELO'

			ini.removeValue( sectionName, CGI::escape(oldPlayerName) )
			unless ( player.elo.eql?( 1000 ) && player.noMatches.eql?( 0 ) )
				eloStr = "#{player.elo} #{player.noMatches}"
				ini.setValue( sectionName, CGI::escape(player.aliasNick ? player.aliasNick : player.mumbleNick), eloStr )
			end

			ini.writeToFile( 'players.ini' )

			create_comment( client )

		else
			client.send_user_message message.actor, 'No admin privileges.'
		end

	end

	def help_msg_admin_alias client, message
		client.send_user_message message.actor, 'Syntax: !admin alias "mumble_nick" "alias"'
		client.send_user_message message.actor, "Sets \"mumble_nick\"'s alias to \"alias\""
	end

	def cmd_admin_op client, message

		mumbleNick = client.find_user( message.actor ).name

		if @players[ client ][ mumbleNick ].admin.eql?('SuperUser')
	
			text = convert_symbols_from_html( message.message )
			param = text.split(' ')[ 2..-1 ]
			unless param.length.eql?( 1 )
				client.send_user_message message.actor, 'Please specify exactly one mumble nick to make admin.'
				return
			end
			param = param.first

			player = @players[ client ].values.select{ |v| v.mumbleNick.downcase.eql?( param.downcase ) }.first

			if player.nil?
				client.send_user_message message.actor, "Player #{text.split(' ')[ 2 ]} has to be in one of the PUG channels."
				return
			end

			if player.admin.eql?( 'SuperUser' ) || player.admin.eql?( 'Admin' )

				client.send_user_message message.actor, "Already a #{player.admin}."
				return

			else

				player.admin = 'Admin'

				@players[ client ][ mumbleNick ] = player

				if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )
					ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )
				else
					ini = Kesh::IO::Storage::IniFile.new
				end

				sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}:admin"
				ini.setValue( sectionName, CGI::escape(player.mumbleNick), player.admin )

				ini.writeToFile( 'players.ini' )

				client.send_user_message message.actor, "Player #{player.mumbleNick} made an admin."
				client.send_user_message player.session, "You have been made an admin by #{mumbleNick}."

			end


		else
			client.send_user_message message.actor, 'No admin privileges.'
		end

	end

	def help_msg_admin_op client, message
		client.send_user_message message.actor, 'Syntax: !admin op "mumble_nick"'
		client.send_user_message message.actor, 'Makes "mumble_nick" an admin if you are a SuperUser'
	end

	def cmd_admin_debug client, message

		mumbleNick = client.find_user( message.actor ).name

		if @players[ client ][ mumbleNick ].admin.eql?('SuperUser')

			displayAPI = false
			displayPlayers = false
			displayMatches = false

			text = convert_symbols_from_html( message.message )
			command = text.split(' ')[2]

			if command.nil?
				displayAPI = true
				displayPlayers = true
				displayMatches = true
			else
				case command.downcase
				when 'api'
					displayAPI = true
				when 'players'
					displayPlayers = true
				when 'matches'
					displayMatches = true
				else
					client.send_user_message message.actor, "Unknown argument '#{command}'!"
				end
			end

			if displayAPI
				result = @query.get_data_used
				unless result.nil?
					actSessions = result[ 'Active_Sessions' ]
					concSessions = result[ 'Concurrent_Sessions' ]
					todaySessions = result[ 'Total_Sessions_Today' ]
					capSessions = result[ 'Session_Cap' ]
					todayRequests = result[ 'Total_Requests_Today' ]
					capRequests = result[ 'Request_Limit_Daily' ]
					client.send_user_message message.actor, "TribesAPI: #{actSessions}/#{concSessions}(Cur. Sessions), #{todaySessions}/#{capSessions} (Tot. Sessions), #{todayRequests}/#{capRequests} (Tot. Requests)"
				end
			end

			if displayPlayers
				if @players[ client ]
					@players[ client ].each_pair do |session, player|
						client.send_user_message message.actor, "Player: #{convert_symbols_to_html( player.playerName )}, level: #{player.level}, elo: #{player.elo}, number of matches: #{player.noMatches}, roles: #{player.roles}, match: #{player.match}, team: #{player.team}"
					end
				else
					client.send_user_message message.actor, 'No players registered'
				end
			end

			if displayMatches
				if @matches

					@matches.each do |match|

						playerStr = []
						match.teams.each do |team|
							players = match.players.select{ |pN, t| t.eql?( team ) }.keys
							playerStr << convert_symbols_to_html( "#{players.join(', ')} (#{team})" )
						end
						teamStr = ''
						if playerStr.length > 0
							teamStr << ", teams: #{playerStr.join( ' ')}"
						end

						resultStr = ''
						if match.results.length > 0
							resultStr << ', results:'
							match.results.each do |res|
								resultStr << " #{res.scores.join('-')}"
							end
						end

						client.send_user_message message.actor, "Id: #{match.id}, label: #{match.label}, status: #{match.status}#{teamStr}#{resultStr}"

					end

				else

					client.send_user_message message.actor, 'No matches registered - this is not good!'

				end
			end

		else
			client.send_user_message message.actor, 'No admin privileges.'
		end

	end

	def cmd_mute client, message 

		text = convert_symbols_from_html( message.message )
		mumbleNick = client.find_user( message.actor ).name

		if !@players[ client ] || !@players[ client ].has_key?( mumbleNick )
			client.send_user_message message.actor, 'You need to join one of the PUG channels set the mute level.'
			return
		end

		player = @players[ client ][ mumbleNick ]

		nick = player.aliasNick ? player.aliasNick : player.mumbleNick

		muteValue = text.split(' ')[ 1 ]

		if muteValue 
			if muteValue.to_i.to_s != muteValue
				client.send_user_message message.actor, 'The mute level has to be numeric: 0(off), 1(default) or 2(all muted).'
				return
			else
				muteValue = muteValue.to_i
			end
		else
			muteValue = player.muted + 1
			if muteValue > 3
				muteValue = 0
			end
		end

		if muteValue.eql?( player.muted )
			client.send_user_message message.actor, 'No change in mute level.'
			return
		end

		player.muted = muteValue

		@players[ client ][ mumbleNick ] = player

		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )
			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )
		else
			ini = Kesh::IO::Storage::IniFile.new
		end

		sectionName = 'Muted'

		if player.muted.eql?( @defaultMute )
			ini.removeValue( sectionName, CGI::escape(nick) )
		else
			ini.setValue( sectionName, CGI::escape(nick), player.muted.to_s )
		end

		ini.writeToFile( 'players.ini' )

		client.send_user_message message.actor, "Mute level set to #{player.muted.to_s}."

	end

	def help_msg_mute client, message
		client.send_user_message message.actor, 'Syntax: !mute 0/1/2/3'
		client.send_user_message message.actor, "Mute the bot's spam messages from 0 (no mute) to 3 (all muted)"
	end

	def cmd_result client, message
		text = convert_symbols_from_html( message.message )
		scores = text.split(' ')[ 1..-1 ]

		if scores.empty?
			client.send_user_message message.actor, 'You need to enter at least one score.'
			return
		end

		mumbleNick = client.find_user( message.actor ).name

		if !@players[ client ] || !@players[ client ].has_key?( mumbleNick )
			client.send_user_message message.actor, 'You need to join one of the PUG channels to set a result.'
			return
		end

		player = @players[ client ][ mumbleNick ]

		match = @matches.select{ |m| m.status.eql?( 'Pending' ) && m.players.select{ |pN, t| pN.downcase.eql?( player.playerName.downcase ) }.length > 0 }.first

		if match.nil?
			match = @matches.select{ |m| m.status.eql?( 'Started' ) && m.players.select{ |pN, t| pN.downcase.eql?( player.playerName.downcase ) }.length > 0 }.first
		end

		if match
			resultStr = set_result( client, match, scores )
			client.send_user_message message.actor, "The results of match (id: #{match.id}) set to: #{resultStr}."
			message_all( client, "#{mumbleNick} reported the results of the match (id: #{match.id}): #{resultStr}.", [ match.id ], 2, message.actor )
		else
			client.send_user_message message.actor, 'No match found with results pending. Maybe the match has already been reported.'
		end

	end

	def help_msg_result client, message
		client.send_user_message message.actor, 'Syntax: !result "map1" "map2" "map3"'
		client.send_user_message message.actor, 'Report the results of a match with the scores for each maps in the form "BE"-"DS".'
	end

	def cmd_admin_result client, message
		text = convert_symbols_from_html( message.message )
		matchId = text.split(' ')[ 2 ]
		scores = text.split(' ')[ 3..-1 ]

		if matchId.nil?
			client.send_user_message message.actor, 'You need to enter a match id and at least one score.'
			return
		end

		if matchId.to_i.to_s != matchId
			client.send_user_message message.actor, 'The match id has to be numerical.'
			return
		end
		matchId = matchId.to_i

		if scores.empty?
			client.send_user_message message.actor, 'You need to enter at least one score.'
			return
		end

		mumbleNick = client.find_user( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			match = @matches.select{ |m| m.id.eql?( matchId ) }.first

			if match
				resultStr = set_result( client, match, scores )
				client.send_user_message message.actor, "The results of match (id: #{match.id}) set to: #{resultStr}."
				message_all( client, "Admin #{mumbleNick} reported the results of the match (id: #{match.id}): #{resultStr}.", [ match.id ], 2, message.actor )
			else
				client.send_user_message message.actor, "No match with id \"#{matchId}\" found."
			end

		else
			client.send_user_message message.actor, 'No admin privileges.'
		end

	end

	def help_msg_admin_result client, message
		client.send_user_message message.actor, 'Syntax: !admin result "match_id" "scores"'
		client.send_user_message message.actor, 'Sets the "scores" of "match_id" for all maps in form "ourcaps"-"theircaps" separated by a space.'
	end

	def set_result client, match, scores

		results = Array.new

		scores.each do |score|

			if score.split('-').length != match.teams.length
				client.send_user_message message.actor, 'Malformed result: please use "BE"-"DS" for each map.'
				return
			end

			result = Result.new
			result.teams = match.teams
			result.scores = score.split('-')
			results << result
			
		end

		match.results.clear
		match.results = results

		match.status = 'Finished'
		index = @matches.index{ |m| m.id.eql?( match.id ) }
		@matches[ index ] = match

		ratioNew = 0.0
		match.players.each_key do |pN|
			unless @eloCalculator.has_player?( pN )
				player = @players[ client ].select{ |m, p| p.playerName.downcase.eql?( pN.downcase ) }.values.first
				@eloCalculator.add_player( pN, player.elo, player.noMatches )
				ratioNew += 1.0 if player.noMatches.eql?( 0 )
			end
		end
		ratioNew = ratioNew / match.players.length

		scores = @eloCalculator.add_match( match )
		estimated = scores[0][ match.teams[0] ]
		actual = scores[1][ match.teams[0] ]
		match.perfELO = 1 - ( estimated - actual ).abs

		if File.exists?( 'players.ini' )
			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )
			FileUtils.cp( 'players.ini', 'players.bak' )
		else
			ini = Kesh::IO::Storage::IniFile.new
		end

		sectionName = "ELO"

		match.players.each_key do |pN|
			if @eloCalculator.has_player?( pN )

				player = @players[ client ].select{ |m, p| p.playerName.downcase.eql?( pN.downcase ) }.values.first
				player.elo = @eloCalculator.get_elo( pN )
				player.noMatches = @eloCalculator.get_noMatches( pN )

				ini.removeValue( sectionName, CGI::escape( pN ) )
				unless ( player.elo.eql?( 1000 ) && player.noMatches.eql?( 0 ) )
					eloStr = "#{player.elo} #{player.noMatches}"
					ini.setValue( sectionName, CGI::escape( pN ), eloStr )
				end

			end
		end

		ini.writeToFile( 'players.ini' )

		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/elo_history.ini' ) )
			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'elo_history.ini' )
			FileUtils.cp( 'elo_history.ini', 'elo_history.bak' )
		else
			ini = Kesh::IO::Storage::IniFile.new
		end		

		sectionName = 'ELOPerformance'
		i = 0
		count = 1
		if ini.hasSection?( sectionName )
			i = ini.getValue( sectionName, 'Count' ).to_i
			count += i
			ini.removeValue( sectionName, 'Count' )
		else
			ini.addSection( sectionName )
		end
		ini.setValue( sectionName, 'Count', count.to_s )
		ini.setValue( sectionName, "Date#{i}", match.date.to_time.utc.to_s )
		ini.setValue( sectionName, "Estimated#{i}", estimated.to_s )
		ini.setValue( sectionName, "Actual#{i}", actual.to_s )
		ini.setValue( sectionName, "Performance#{i}", match.perfELO.to_s )
		ini.setValue( sectionName, "RatioNew#{i}", ratioNew.to_s )

		match.players.each_key do |pN|
			if @eloCalculator.has_player?( pN )

				player = @players[ client ].select{ |m, p| p.playerName.downcase.eql?( pN.downcase ) }.values.first

				sectionName = CGI::escape( pN )

				i = 0
				count = 1
				if ini.hasSection?( sectionName )
					i = ini.getValue( sectionName, 'Count' ).to_i
					count += i
					ini.removeValue( sectionName, 'Count' )
				else
					ini.addSection( sectionName )
				end

				ini.setValue( sectionName, 'Count', count.to_s )
				ini.setValue( sectionName, "Date#{i}", match.date.to_time.utc.to_s )
				ini.setValue( sectionName, "ELO#{i}", player.elo )

			end
		end

		ini.writeToFile( 'elo_history.ini' )

		write_matches_ini
		create_comment( client )

		resultStr = ''
		if match.results.length > 0
			match.results.each do |res|
				resultStr << " #{res.scores.join('-')}"
			end
		end

		return resultStr
	end

	def cmd_admin_delete client, message
		text = convert_symbols_from_html( message.message )
		matchId = text.split(' ')[ 2 ]

		if matchId.nil?
			client.send_user_message message.actor, 'You need to enter a match id.'
			return
		end

		if matchId.to_i.to_s != matchId
			client.send_user_message message.actor, 'The match id has to be numerical.'
			return
		end
		matchId = matchId.to_i

		mumbleNick = client.find_user( message.actor ).name

		if @players[ client ][ mumbleNick ].admin

			index = @matches.index{ |m| m.id.eql?( matchId ) }
			match = @matches[ index ]

			if match

				if match.status.eql?( 'Signup' )
					client.send_user_message message.actor, "Can't delete the current signup match."
					return
				end

				@players[ client ].select{ |mN, pl| pl.match.eql?( matchId ) }.each_key do |mN|
					@players[ client ][ mN ].match = @currentMatch[ client ]
				end
				
				match.status = 'Deleted'
				@matches[ index ] = match

				if match.id.eql?( @currentMatch[ client ] )

					create_new_match( client )

					# Move everyone over to the new match apart from picked players
					@players[ client ].each_pair do |mN, pl|
						if pl.team.nil? && !pl.match.nil?
							@players[ client ][ mN ].match = @currentMatch[ client ]
						end
					end

				end

				write_matches_ini

				client.send_user_message message.actor, "The match (id: #{match.id}) has been deleted."
				create_comment( client )

			else

				client.send_user_message message.actor, "No match with id \"#{matchId}\" found."

			end

		else
			client.send_user_message message.actor, 'No admin privileges.'
		end

	end

	def help_msg_admin_delete client, message
		client.send_user_message message.actor, 'Syntax: !admin delete "match_id"'
		client.send_user_message message.actor, 'Delete match with id "match_id".'
	end

	def cmd_list client, message
		text = convert_symbols_from_html( message.message )
		params = text.split(' ')[ 1..-1 ]


		selection = Array.new
		if params.empty?
			selection = selection | @matches.select{ |m| !m.status.eql?( 'Deleted' ) && m.label.eql?( @connections[ client ][ :label ] ) }
		else
			params.each do |param|
				if param.downcase.eql?( 'all' )
					selection = selection | @matches.select{ |m| true }
				else
					selection = selection |  @matches.select{ |m| m.status.downcase.eql?( param.downcase ) && m.label.eql?( @connections[ client ][ :label ] ) }
				end
			end
		end

		if selection.empty?
			client.send_user_message message.actor, 'No matches found.'
		else
			selection.each do |match|

				statusStr = ", Status: #{match.status}"

				dateStr = ''
				if match.status.eql?( 'Started' ) || match.status.eql?( 'Pending' ) || match.status.eql?( 'Finished' ) || match.status.eql?( 'Deleted' )
					dateStr << ", Date: #{match.date.strftime('%d/%m %H:%M')}"
				end

				playerStr = []
				match.teams.each do |team|
					players = match.players.select{ |pN, t| t.eql?( team ) }.keys
					playerStr << convert_symbols_to_html( "#{players.join(', ')} (#{team})" )
				end
				teamStr = ''
				if playerStr.length > 0
					teamStr << ", Teams: #{playerStr.join( ' ')}"
				end

				resultStr = ''
				if match.results.length > 0
					resultStr << ', Results:'
					match.results.each do |res|
						resultStr << " #{res.scores.join('-')}"
					end
				end

				client.send_user_message message.actor, "Id: #{match.id}#{dateStr}#{statusStr}#{teamStr}#{resultStr}"
			end
		end
	end

	def help_msg_list client, message
		client.send_user_message message.actor, 'Syntax: !list'
		client.send_user_message message.actor, 'Shows the latest matches that have been registered on the bot.'
	end

	# @param message [TextMessage]
	def cmd_admin_eval client, message

		mumbleNick = client.find_user( message.actor ).name

		if @players[ client ].has_key?( mumbleNick ) && @players[ client ][ mumbleNick ].admin.eql?( 'SuperUser' )
			cmd = convert_symbols_from_html(message.message).split[ 2..-1 ].join(' ')
			unless cmd.empty?
				if cmd[ 'system' ] || cmd[ '`' ] || cmd[ '%x' ]
					client.send_user_message message.actor, 'System calls not allowed.'
					return
				else
					Thread.new { eval_cmd( client, message.actor, cmd ) }
				end
			end
		else
			client.send_user_message message.actor, 'No SuperUser privileges.'
		end

	end

	def eval_cmd client, session, command
		puts "Eval called with command: #{command}"
		output = eval(command)
		puts "Eval call returned: #{output}"
		client.send_user_message session, "Output: #{output}"
	rescue => e
		client.send_user_message session, "The eval threw an exception '#{e}'\nTRACE:\n#{e.backtrace.join('\n')}"
	end

	def get_player_stats nick, *stats
		if nick != 'SomeFakePlayerName'

			result = @query.get_player( nick )

			stats = stats.first

			statsVals = Array.new
			stats.each do |stat|
				statsVals << result[ stat ]
			end
			return statsVals

		else

			result = @query.get_player( 'Player' )

			stats = result.keys
			return stats

		end

	rescue
		return nil

	end

	def get_player_matches nick, date

		matchesData = @query.get_match_history( nick )
		matchIds = Array.new
		matchesData.each do |matchData|
			matchDate = DateTime.strptime( matchData[ 'Entry_Datetime' ], '%m/%d/%Y %I:%M:%S %p' ).to_time.utc
			break if matchDate < date
			matchIds << matchData[ 'MatchId']
		end

		return matchIds

	rescue => e
		return nil

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
			ini.setValue( sectionName, 'PlayerNum', @playerNum[ client ].to_s )
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
					if value.name.eql? 'PlayerNum'
						@playerNum[ client ] = value.value.to_i
					elsif !value.value.nil?
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
					next if value.value.nil?
					roles = value.value.split(',')
					roles.each do |role|
						roles.delete( role ) unless @rolesRequired[ client ].has_key?( role )
					end
					channelsHash[ value.name ] = roles unless roles.empty?
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

			next if ( match.status.eql?( 'Signup' ) || match.status.eql?( 'Picking' ) )

			sectionName = "#{match.id}"
			ini.removeSection( sectionName )

			ini.setValue( sectionName, 'Label', match.label )
			ini.setValue( sectionName, 'Status', match.status )
			if match.date
				ini.setValue( sectionName, 'Date', match.date.utc.to_s )
			end
			ini.setValue( sectionName, 'Teams', match.teams.join( ' ' ) )

			match.teams.each do |team|
				playerNames = match.players.select{ |pN, t| t.eql?( team ) }.keys
				playerNames.each_index do |i|
					playerNames[ i ] = CGI::escape(playerNames[ i ])
				end
				ini.setValue( sectionName, "#{team}", playerNames.join( ' ' ) )
			end

			ini.setValue( sectionName, 'Comment', match.comment )
			ini.setValue( sectionName, 'ResultCount', match.results.length.to_s )

			match.results.each_index do |r|
				result = match.results[ r ]
				ini.setValue( sectionName, "Result#{r.to_s}Map", "#{result.map}")
				result.teams.each_index do |t|
					ini.setValue( sectionName, "Result#{r.to_s}#{result.teams[ t ]}", "#{result.scores[ t ]}")
				end
				ini.setValue( sectionName, "Result#{r.to_s}Comment", "#{result.comment}")
			end

			ini.setValue( sectionName, 'PerformanceELO', match.perfELO.to_s )

			ini.setValue( sectionName, 'MatchIdsAPI', match.idsAPI.join(' ') ) unless match.idsAPI.empty?

		end

		ini.writeToFile( 'matches.ini' )
	end

	def load_matches_ini
		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/matches.ini' ) )

			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'matches.ini' )

			ini.sections.each do |section|

				id = section.name

				if id[ /^\d+$/ ].nil?
					puts 'Invalid ID: ' + id.to_s
					raise SyntaxError
				end

				idInt = id.to_i
				@nextMatchId = ( idInt + 1 ) if ( idInt >= @nextMatchId )

				label = section.getValue( 'Label' )

				status = section.getValue( 'Status' )
				next unless ( status.eql?( 'Started' ) || status.eql?( 'Pending' ) || status.eql?( 'Finished' ) )

				date = Time.parse( section.getValue( 'Date' ) )
				next unless ( Time.now - date ) < 24 * 60 * 60

				# if ( date == nil )
				# 	puts "Invalid Date: " + section.getValue( 'Date' ).to_s
				# 	raise SyntaxError
				# end

				players = Hash.new

				teams = section.getValue( 'Teams' )

				if teams.nil?
					teams = Array.new
				else
					teams = teams.split( ' ' )

					teams.each do |team|

						playerNamesStr = section.getValue( "#{team}" )

						unless playerNamesStr.nil?
							playerNames = playerNamesStr.split( ' ' )
							playerNames.each do |pN|
								players[ CGI::unescape( pN ) ] = team
							end
						end

					end

				end

				comment = section.getValue( 'Comment' )
				resultCount = section.getValue( 'ResultCount' )

				if resultCount[ /^\d+$/ ].nil?
					puts "Invalid Result Count: #{resultCount.to_s}"
					raise SyntaxError
				end

				results = Array.new

				rCount = resultCount.to_i
				rIndex = 0

				while rIndex < rCount

					rMap = section.getValue( "Result#{rIndex}Map" )
					rTeams = teams
					rScores = Array.new

					teams.each do |team|
						rScores << section.getValue( "Result#{rIndex}#{team}" ).to_i
					end

					rComment = section.getValue( "Result#{rIndex}Comment" )

					results << Result.new( rMap, rTeams, rScores, rComment )

					rIndex = rIndex + 1

				end

				perfELO = section.getValue( 'PerformanceELO' )
				perfELO = Float( perfELO ) unless perfELO.nil?

				idsAPI = Array.new
				idsAPIStr = section.getValue( 'MatchIdsAPI' )
				idsAPI = idsAPIStr.split(' ') unless idsAPIStr.nil?

				@matches << Match.new( idInt, label, status, date, teams, players, comment, results, perfELO, idsAPI )

			end

		end

	end

	def get_player_data client, mumbleNick

		session = client.find_user( mumbleNick ).session

		nick = mumbleNick
		admin = nil
		aliasNick = nil
		muted = nil
		elo = nil
		noMatches = nil

		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )

			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )

			sectionNameBase = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}"

			sectionName = "#{sectionNameBase}:admin"
			admin = ini.getValue( sectionName, CGI::escape(mumbleNick) )

			sectionName = "#{sectionNameBase}:aliases"
			aliasNick = ini.getValue( sectionName, CGI::escape(mumbleNick) )

			nick = aliasNick ? CGI::unescape(aliasNick) : mumbleNick

			sectionName = 'Muted'
			muted = ini.getValue( sectionName, CGI::escape(nick) )
			if muted
				muted = muted.to_i
			else
				muted = @defaultMute
			end

			sectionName = 'ELO'
			eloStr = ini.getValue( sectionName, CGI::escape(nick) )
			unless eloStr.nil?
				elo = eloStr.split(' ')[0].to_i
				noMatches = eloStr.split(' ')[1].to_i
			end

		end

		elo = 1000 if elo.nil?
		noMatches = 0 if noMatches.nil?

		stats = Array.new
		stats << 'Name'
		stats << 'Level'
		stats << 'Tag'

		statsVals = get_player_stats( nick, stats )

		if statsVals.nil?
			playerName = nick
			level = 'unknown'
			tag = nil
		else
			playerName = statsVals.shift
			level = statsVals.shift
			tag = statsVals.shift
		end

		return {
				session: session,
				mumbleNick: mumbleNick,
				admin: admin,
				aliasNick: aliasNick,
				muted: muted,
				elo: elo,
				noMatches: noMatches,
				playerName: playerName,
				level: level,
				tag: tag
		}

	end

	def message_all client, message, matchIds, importance, *exclude

		return unless @players[ client ]

		targets = Array.new

		raise "In method 'message_all': matchIds has to be an Array." unless matchIds.is_a?( Array )

		matchIds.each do |id|

			if id.nil?

				@players[ client ].each_value do |pl|
					next unless pl.match.nil?
					next if pl.muted >= importance
					next if targets.include?( pl.session )
					next if exclude && exclude.include?( pl.session )
					targets << pl.session 
				end

			else

				match = @matches.select{ |m| m.id.eql?( id ) }.first
				match.players.keys.each do |playerName|
					pl = @players[ client ].select{ |mN, pl| pl.playerName.downcase.eql?( playerName.downcase ) }.values.first
					next if pl.nil?
					next if pl.muted >= importance
					next if targets.include?( pl.session )
					next if exclude && exclude.include?( pl.session )
					targets << pl.session 
				end
				@players[ client ].each_value do |pl|
					next unless pl.match.eql?( id )
					next if pl.muted >= importance
					next if targets.include?( pl.session )
					next if exclude && exclude.include?( pl.session )
					targets << pl.session 
				end

			end

		end

		targets.each do |t|
			client.send_user_message( t, message )
		end

	end

	def cleanup_players client
		disappeared = [] 
		@players[ client ].each_key do |mumbleNick|
			if client.find_user( mumbleNick ).nil?
				disappeared << mumbleNick
			end
		end
		disappeared.each do |mumbleNick|
			@players[ client ].delete( mumbleNick )
		end
	end

	def convert_symbols_from_html param
		text = param.clone
		raise 'Not a String' unless text.class.eql?( String )
		text.gsub!( /<br[\/\\]?>/, "\n" )
		text.gsub!( '&quot;', "\"" )
		text.gsub!( '&lt;', '<' )
		text.gsub!( '&gt;', '>' )
		text.gsub!( '&nbsp;', ' ' )
		text.gsub!( '&thinsp;', ' ' )
		# text.gsub!( '&iexcl;', '¡' )
		# text.gsub!( '&cent;', '¢' )
		# text.gsub!( '&pound;', '£' )
		# text.gsub!( '&curren;', '¤' )
		# text.gsub!( '&yen;', '¥' )
		# text.gsub!( '&brvbar;', '¦' )
		# text.gsub!( '&sect;', '§' )
		# text.gsub!( '&uml;', '¨' )
		# text.gsub!( '&copy;', '©' )
		# text.gsub!( '&ordf;', 'ª' )
		# text.gsub!( '&laquo;', '«' )
		# text.gsub!( '&not;', '¬' )
		text.gsub!( '&shy;', '-' )
		# text.gsub!( '&reg;', '®' )
		# text.gsub!( '&macr;', '¯' )
		# text.gsub!( '&deg;', '°' )
		# text.gsub!( '&plusmn;', '±' )
		# text.gsub!( '&sup2;', '²' )
		# text.gsub!( '&sup3;', '³' )
		# text.gsub!( '&acute;', '´' )
		# text.gsub!( '&micro;', 'µ' )
		# text.gsub!( '&para;', '¶' )
		# text.gsub!( '&middot;', '·' )
		# text.gsub!( '&cedil;', '¸' )
		# text.gsub!( '&sup1;', '¹' )
		# text.gsub!( '&ordm;', 'º' )
		# text.gsub!( '&raquo;', '»' )
		# text.gsub!( '&frac14;', '¼' )
		# text.gsub!( '&frac12;', '½' )
		# text.gsub!( '&frac34;', '¾' )
		# text.gsub!( '&iquest;', '¿' )
		# text.gsub!( '&times;', '×' )
		# text.gsub!( '&divide;', '÷' )
		# text.gsub!( '&ETH;', 'Ð' )
		# text.gsub!( '&eth;', 'ð' )
		# text.gsub!( '&THORN;', 'Þ' )
		# text.gsub!( '&thorn;', 'þ' )
		# text.gsub!( '&AElig;', 'Æ' )
		# text.gsub!( '&aelig;', 'æ' )
		# text.gsub!( '&OElig;', 'Œ' )
		# text.gsub!( '&oelig;', 'œ' )
		# text.gsub!( '&Aring;', 'Å' )
		# text.gsub!( '&Oslash;', 'Ø' )
		# text.gsub!( '&Ccedil;', 'Ç' )
		# text.gsub!( '&ccedil;', 'ç' )
		# text.gsub!( '&szlig;', 'ß' )
		# text.gsub!( '&Ntilde;', 'Ñ' )
		# text.gsub!( '&ntilde;', 'ñ' )
		text.gsub!( '&amp;', '&' )
		return text
	end

	def convert_symbols_to_html param
		text = param.clone
		raise 'Not a String' unless text.class.eql?( String )
		text.gsub!( '&', '&amp;' )
		text.gsub!( '"', '&quot;' )
		text.gsub!( '<', '&lt;' )
		text.gsub!( '>', '&gt;' )
		text.gsub!( ' ', '&thinsp;' )
		text.gsub!( /(?:\r\n|\r|\n)/, '<br/>' )
		# text.gsub!( '-', '&shy;' )
		return text
	end
end