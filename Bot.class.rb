requireLibrary 'Mumble'

class Bot

	def initialize options
		@clientcount = 0
		@options = options
		@clients = {}
	end

	def exit_by_user
		puts ""
		puts "user exited bot."
		@clients.keys.first.debug
	end

	def connected?
		return true
	end

	def on_connected client, message
		client.switch_channel @clients[client][:channel]
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
		# packet = message.packet

		# index = 0
		# tt = Kesh::Mumble::Tools.decode_type_target(packet[index])
		# index = 1

		# vi1 = Kesh::Mumble::Tools.decode_varint packet, index
		# index = vi1[:new_index]
		# session = vi1[:result]

		# vi2 = Kesh::Mumble::Tools.decode_varint packet, index
		# index = vi2[:new_index]
		# sequence = vi2[:result]

		# data = packet[index..-1]

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
			client = Kesh::Mumble::MumbleClient.new(server[:host], server[:port], server[:nick], @options)
			client.register_handler :ServerSync, method(:on_connected)
			client.register_handler :UserState, method(:on_users_changed)
			client.register_handler :UserRemove, method(:on_users_changed)
			client.register_handler :UDPTunnel, method(:on_audio)
			client.register_text_handler "!find", method(:cmd_find)
			client.register_text_handler "!goto", method(:cmd_goto)
			client.register_text_handler "!test", method(:cmd_test)

			client.connect
			@clients[client] = server
		end

		while connected? do
			sleep 0.2
		end
	end

	private
	def cmd_find client, message
		text = message.message

		nick = text[6..-1]
		user = client.find_user nick
		if user
			client.send_user_message message.actor, "User '#{user.name}' is in Channel '#{user.channel.path}'"
		else
			client.send_user_message message.actor, "There is no user '#{nick}' on the Server"
		end
	end

	def cmd_goto client, message
		text = message.message

		nick = text[6..-1]
		target = client.find_user nick
		source = client.find_user message.actor
		client.move_user source, target.channel
	end

	def cmd_test client, message
		client.channels.each do |id, ch|
			client.send_acl id
		end
	end

end