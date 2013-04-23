# require 'speech'
# require 'celt-ruby'

requireLibrary 'Mumble'
requireLibrary 'TribesAPI'

class Bot

	def initialize options
		@clientcount = 0
		@options = options
		@connections = {}
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
		client.switch_channel @connections[client][:channel]
	end

	def on_users_changed client, message
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
		index = vi1[:new_index]
		session = vi1[:result]

		vi2 = Kesh::Mumble::Tools.decode_varint packet, index
		index = vi2[:new_index]
		sequence = vi2[:result]

		data = packet[index..-1]

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
			client.register_handler :ServerSync, method( :on_connected )
			client.register_handler :UserState, method( :on_users_changed )
			client.register_handler :UserRemove, method( :on_users_changed )
			client.register_handler :UDPTunnel, method( :on_audio )
			client.register_text_handler "!find", method( :cmd_find )
			client.register_text_handler "!goto", method( :cmd_goto )
			client.register_text_handler "!test", method( :cmd_test )
			client.register_text_handler "!info", method( :cmd_info )

			client.connect
			@connections[client] = server
		end

		while connected? do
			sleep 0.2
		end
	end

	private
	def cmd_find client, message
		text = message.message

		nick = text.split(" ")[ 1 ]
		user = client.find_user nick
		if user
			client.send_user_message message.actor, "User '#{user.name}' is in Channel '#{user.channel.path}'"
		else
			client.send_user_message message.actor, "There is no user '#{nick}' on the Server"
		end
	end

	def cmd_goto client, message
		text = message.message

		nick = text.split(" ")[ 1 ]
		target = client.find_user nick
		source = client.find_user message.actor
		client.move_user source, target.channel
	end

	def cmd_test client, message
		client.channels.each do |id, ch|
			client.send_acl id
		end
	end

	def cmd_info client, message
		text = message.message
		own_nick = client.find_user( message.actor ).name

		nick = text.split(" ")[ 1 ]
		nick = ( nick.nil? ) ? own_nick : nick

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

	def get_player_stats nick, *stats
		query = Kesh::TribesAPI::TribesAPI.new( @options[ :base_url ], @options[ :devId ], @options[ :authKey ] )
		result = query.send_method( "getplayer", nick )

		stats = stats.first

		statsVals = Array.new
		stats.each do |stat|
			statsVals << result[ stat ]
		end
		return statsVals
	rescue
		return
	end


end