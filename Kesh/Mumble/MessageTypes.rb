# from https://github.com/mumble-voip/mumble.git/src/Message.h

require File.expand_path "../Protocol/Mumble.pb", __FILE__

module Kesh
	module Mumble

		MP_TYPES = {
			0 => MumbleProto::Version,
			1 => MumbleProto::UDPTunnel,
			2 => MumbleProto::Authenticate,
			3 => MumbleProto::Ping,
			4 => MumbleProto::Reject,
			5 => MumbleProto::ServerSync,
			6 => MumbleProto::ChannelRemove,
			7 => MumbleProto::ChannelState,
			8 => MumbleProto::UserRemove,
			9 => MumbleProto::UserState,
			10 => MumbleProto::BanList,
			11 => MumbleProto::TextMessage,
			12 => MumbleProto::PermissionDenied,
			13 => MumbleProto::ACL,
			14 => MumbleProto::QueryUsers,
			15 => MumbleProto::CryptSetup,
			16 => MumbleProto::ContextActionModify,
			17 => MumbleProto::ContextAction,
			18 => MumbleProto::UserList,
			19 => MumbleProto::VoiceTarget,
			20 => MumbleProto::PermissionQuery,
			21 => MumbleProto::CodecVersion,
			22 => MumbleProto::UserStats,
			23 => MumbleProto::RequestBlob,
			24 => MumbleProto::ServerConfig,
			25 => MumbleProto::SuggestConfig
		}

		# reverse lookup class => type ID
		MP_RTYPES = MP_TYPES.invert

	end
end

