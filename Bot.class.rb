# require 'speech'
# require 'celt-ruby'

requireLibrary 'IO'
requireLibrary 'Mumble'
requireLibrary 'TribesAPI'

class Bot

	def initialize options
		@clientcount = 0
		@options = options
		@connections = {}
		@admins = {}
		@roles = {}
		@aliases = {}
		@signedUp = {}
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

	def on_users_changed client, message
		chanPath = client.channels[ message.channel_id ].path
		nick = message.name

		if @roles[ client ].has_key? chanPath
			# In a monitored channel

			chanRole = @roles[ client ][ chanPath ]

			if @signedUp.has_key? nick
				# Already signed up

				if @signedUp[ nick ].eql? chanRole
					# No change in role
				else
					# Role changed
					@signedUp[ nick ] = chanRole
					client.send_user_message message.session, "Your role changed to '#{chanRole.join(' ')}'."
				end

			else
				# New Signup
				@signedUp.merge! nick => chanRole
				client.send_user_message message.session, "You signed up with role '#{chanRole.join(' ')}'."
			end

		else
			# Not in a monitored channel

			if @signedUp.has_key? nick
				@signedUp.delete nick
				client.send_user_message message.session, "You were removed."
			end

		end

		# return if !client.channel

		# client.channel.localusers.each do |u|
		# 	if u.session == client.user.session
		# 		next # this is the master
		# 	end

		# 	if !@slave_by_host[client] or @slave_by_host[client][u.session]
		# 		next # this is a slave from another server
		# 	end

		# 	if !@slave_by_user[client] or @slave_by_user[client][u.session]
		# 		update_slaves(client, u)
		# 		next # we have already slaves for this one
		# 	end

		# 	# new user
		# 	@masters.each do |master, config|
		# 		next if master == client # thats the current server
		# 		host = @masters[client][:host]
		# 		slave = make_slave Kesh::Mumble::MumbleClient.new(config[:host], config[:port], "#{u.name}@#{host}", @options)
		# 		@slave_by_user[client][u.session] = [] if  !@slave_by_user[client][u.session]
		# 		@slave_by_user[client][u.session] << slave
		# 		@server_by_client[slave] = master
		# 	end
		# end

		# #is a user missing? -> disconnect all slaves
		# @slave_by_user[client].each do |session, slaves|
		# 	is_in_channel = false
		# 	client.channel.localusers.each do |u|
		# 		is_in_channel = true if (session == u.session)
		# 	end
		# 	if !is_in_channel
		# 		slaves.each do |slave|
		# 			slave.disconnect
		# 			remove_slave(slave, client)
		# 		end
		# 	end
		# end
	end

	def on_audio client, message
		packet = message.packet.bytes.to_a

		index = 0
		tt = Kesh::Mumble::Tools.decode_type_target( packet[ index ] )

		index = 1
		vi1 = Kesh::Mumble::Tools.decode_varint packet, index
		index = vi1[ :new_index ]
		session = vi1[ :result ]

		vi2 = Kesh::Mumble::Tools.decode_varint packet, index
		index = vi2[ :new_index ]
		sequence = vi2[ :result ]

		data = packet[ index..-1 ]

		# slaves = @slave_by_user[client][session]

		# #is from real user?
		# return if !slaves

		# codec_type = tt[:type]

		# slaves.each do |slave|
		# 	if (codec_type == 0) or (codec_type == 3)
		# 		tt[:type] = (client.alpha == slave.alpha) ? codec_type : 3 - codec_type
		# 	end
		# 	repackaged = Kesh::Mumble::Tools.encode_type_target(tt) + Kesh::Mumble::Tools.encode_varint(sequence) + data
		# 	slave.send_udp_tunnel repackaged
		# end
	end

	def run servers
		servers.each do |server|

			@clientcount += 1

			client = Kesh::Mumble::MumbleClient.new( server[:host], server[:port], server[:nick], @options )
			@connections[ client ] = server

			client.register_handler :ServerSync, method( :on_connected )
			client.register_handler :UserState, method( :on_users_changed )
			client.register_handler :UserRemove, method( :on_users_changed )
			client.register_handler :UDPTunnel, method( :on_audio )
			client.register_text_handler "!help", method( :cmd_help )
			client.register_text_handler "!find", method( :cmd_find )
			client.register_text_handler "!goto", method( :cmd_goto )
			client.register_text_handler "!test", method( :cmd_test )
			client.register_text_handler "!info", method( :cmd_info )
			client.register_text_handler "!admin", method( :cmd_admin )
			client.register_text_handler "!alias", method( :cmd_alias )

			load_admins_ini client
			load_roles_ini client
			load_aliases_ini client

			client.connect

		end

		while connected? do
			sleep 0.2
		end
	end

	private

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
		when "admin"
			help_msg_admin( client, message )
		else
			client.send_user_message message.actor, "The following commands are available:"
			client.send_user_message message.actor, "!help \"command\" - detailed help on the command"
			client.send_user_message message.actor, "!find \"mumble_nick\" - find which channel someone is in"
			client.send_user_message message.actor, "!goto \"mumble_command\" - move yourself to someone's channel"
			client.send_user_message message.actor, "!info \"tribes_nick\" \"stat\" - detailed stats on player"
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
		text = message.message
		own_nick = client.find_user( message.actor ).name
		own_nick = @aliases[ client ].has_key?( own_nick ) ? @aliases[ client ][ own_nick ] : own_nick

		nick = text.split(' ')[ 1 ]
		nick = ( nick.nil? ) ? own_nick : nick
		nick = @aliases[ client ].has_key?( nick ) ? @aliases[ client ][ nick ] : nick

		stats = Array.new
		stats << "Name"
		stats << "Level"
		stats << "Last_Login_Datetime"
		stats.push( *text.split(" ")[ 2..-1 ] )
		stats.map! do |stat|
			stat.split('_').map!( &:capitalize ).join('_')
		end

		statsVals = get_player_stats( nick, stats )

		if ( statsVals.nil? && nick != own_nick )

			stats.insert( 3, nick.split('_').map!( &:capitalize ).join('_') )
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

		if ( stats[ 3 ] == nick && statsVals[ 3 ].nil? )
			client.send_user_message message.actor, "Player #{nick} not found."
		else
			name = statsVals.shift
			level = statsVals.shift
			last_login = statsVals.shift
			stats.shift( 3 )
			client.send_user_message message.actor, "Player #{name} has level #{level}."
			client.send_user_message message.actor, "He/she has last logged in on #{last_login}."
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
			client.send_user_message message.actor, "Returns your level and last login time based on your mumble nick"
			client.send_user_message message.actor, "Syntax !info \"stat\""
			client.send_user_message message.actor, "As above but also shows your \"stat\""
			client.send_user_message message.actor, "Syntax !info \"tribes_nick\""
			client.send_user_message message.actor, "Returns \"tribes_nick\"'s level and last login time"
			client.send_user_message message.actor, "Syntax !info \"tribes_nick\" \"stat\""
			client.send_user_message message.actor, "As above but also shows \"tribes_nick\"'s \"stat\""
			client.send_user_message message.actor, "\"stat\" can be a space delimited list of these stats:"
			stats = get_player_stats "SomeFakePlayerName"
			stats.each do |stat|
				client.send_user_message message.actor, stat unless stat.eql? "ret_msg"
			end
	end

	def cmd_admin client, message

		if @admins[ client ].has_key? client.find_user( message.actor ).name

			text = message.message

			command = text.split(' ')[ 1 ]

			case command
			when "login"
				cmd_admin_login( client, message )
			when "setchan"
				cmd_admin_setchan( client, message )
			when "come"
				cmd_admin_come( client, message )
			else
				client.send_user_message message.actor, "Please specify an admin command."
			end

		else
			client.send_user_message message.actor, "No admin priviliges."
		end
	end

	def help_msg_admin client, message
	end

	def cmd_admin_login client, message
		text = message.message
		nick = client.find_user( message.actor ).name
		password = text.split(' ')[ 2 ]

		if password.eql? @connections[ client ][ :pass ]

			client.send_user_message message.actor, "Login accepted."

			if @admins[ client ]

				if @admins[ client ].has_key? nick

					if @admins[ client ][ nick ].eql? "SuperUser"
						client.send_user_message message.actor, "Already a SuperUser."
					else
						@admins[ client ][ nick ] = "SuperUser"
					end

				else
					@admins[ client ].merge! nick => "SuperUser"
				end
			else
				@admins[ client ] = { nick => "SuperUser" }
			end

			write_admins_ini client

		else
			client.send_user_message message.actor, "Wrong password."
		end

	end

	def help_msg_admin_login client, message
	end

	def cmd_admin_setchan client, message 
		if @admins[ client ].has_key? client.find_user( message.actor ).name

			text = message.message
			chanPath = client.find_user( message.actor ).channel.path
			chanRole = text.split(' ')[ 2..-1 ]

			if @roles[ client ]

				if @roles[ client ].has_key? chanPath
					prevValue = @roles[ client ][ chanPath ]
					@roles[ client ][ chanPath ] = chanRole
				else
					@roles[ client ].merge! chanPath => chanRole
				end

			else
				@roles[ client ] = { chanPath => chanRole }
			end

			write_roles_ini client

			if prevValue
				client.send_user_message message.actor, "Channel #{chanPath} changed from '#{prevValue.join(' ')}' to '#{chanRole.join(' ')}'."
			else
				client.send_user_message message.actor, "Channel #{chanPath} set to '#{chanRole.join(' ')}'."
			end

		else
			client.send_user_message message.actor, "No admin privileges."
		end

	end

	def help_msg_admin_setchan client, message
	end

	def cmd_admin_come client, message 
		if @admins[ client ].has_key? client.find_user( message.actor ).name

			chanPath = client.find_user( message.actor ).channel.path
			client.switch_channel chanPath

		else
			client.send_user_message message.actor, "No admin privileges."
		end

	end

	def help_msg_admin_come client, message
	end

	def cmd_alias client, message 
		text = message.message
		nick = client.find_user( message.actor ).name
		aliasValue = text.split(' ')[ 1 ]

		if @aliases[ client ]

			if @aliases[ client ].has_key? nick

				prevValue = @aliases[ client ][ nick ]

				if aliasValue.eql? nick
					@aliases[ client ].delete( nick )
				else
					@aliases[ client ][ nick ] = aliasValue
				end

			else
				@aliases[ client ].merge! nick => aliasValue
			end

		else
			@aliases[ client ] = { nick => aliasValue }
		end

		write_aliases_ini client

		if prevValue
			if aliasValue.eql? nick
				client.send_user_message message.actor, "Previous alias (#{prevValue}) of #{nick} removed."
			else
				client.send_user_message message.actor, "Alias of #{nick} changed from #{prevValue} to #{aliasValue}."
			end
		else
			client.send_user_message message.actor, "Alias of #{nick} set to #{aliasValue}."
		end

	end

	def help_msg_alias client, message
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

	def write_admins_ini  client
		sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}"

		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/admins.ini' ) )
			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'admins.ini' )
			ini.removeSection( sectionName )
		else
			ini = Kesh::IO::Storage::IniFile.new
		end

		ini.addSection( sectionName )

		@admins[ client ].each_pair do |nick, value|
			ini.setValue( sectionName, nick, value )
		end

		ini.writeToFile( 'admins.ini' )
	end

	def load_admins_ini client
		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/admins.ini' ) )

			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'admins.ini' )
			sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}"
			adminsSection = ini.getSection( sectionName )

			if adminsSection
				adminsHash = Hash.new

				adminsSection.values.each do |value|
					adminsHash[ value.name ] = value.value
				end

				@admins[ client ] = adminsHash
			end

		end
	end

	def write_roles_ini client
		sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}"

		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/roles.ini' ) )
			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'roles.ini' )
			ini.removeSection( sectionName )
		else
			ini = Kesh::IO::Storage::IniFile.new
		end

		ini.addSection( sectionName )

		@roles[ client ].each_pair do |channel, value|
			ini.setValue( sectionName, channel, value.join(',') )
		end

		ini.writeToFile( 'roles.ini' )
	end

	def load_roles_ini client
		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/roles.ini' ) )

			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'roles.ini' )
			sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}"
			channelsSection = ini.getSection( sectionName )

			if channelsSection
				channelsHash = Hash.new

				channelsSection.values.each do |value|
					channelsHash[ value.name ] = value.value.split(',')
				end

				@roles[ client ] = channelsHash
			end

		end
	end

	def write_aliases_ini client
		sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}"

		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/aliases.ini' ) )
			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'aliases.ini' )
			ini.removeSection( sectionName )
		else
			ini = Kesh::IO::Storage::IniFile.new
		end

		ini.addSection( sectionName )

		@aliases[ client ].each_pair do |nick, value|
			ini.setValue( sectionName, nick, value )
		end

		ini.writeToFile( 'aliases.ini' )
	end

	def load_aliases_ini client
		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/aliases.ini' ) )

			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'aliases.ini' )
			sectionName = "#{@connections[ client ][ :host ]}:#{@connections[ client ][ :port ]}"
			aliasesSection = ini.getSection( sectionName )

			if aliasesSection
				aliasesHash = Hash.new

				aliasesSection.values.each do |value|
					aliasesHash[ value.name ] = value.value
				end

				@aliases[ client ] = aliasesHash
			end

		end
	end

end