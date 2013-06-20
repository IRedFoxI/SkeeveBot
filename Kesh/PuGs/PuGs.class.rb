# requireLibrary '../../PuGs'

module Kesh
	module TribesAPI

		class PuGs

			def initialize options
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
				@lastCleanUp = Time.now

				load_matches_ini
			end

		end

	end
end



