# requireLibrary '../../TribesAPI'

require 'digest/md5'
require 'json'
require 'net/http'

module Kesh
	module TribesAPI

		class SessionError < Exception
		end

		class QueryError < Exception
		end

		class ParseError < Exception
		end

		class TribesAPI

			attr_reader :sessionId

			def initialize base_url, devId, authKey
				@base_url = base_url
				@devId = devId
				@authKey = authKey
				@sessionId = nil

				create_session
			end

			def get_player nick

				create_session if @sessionId.nil?
				
				result = send_method( "getplayer", nick )
				return nil if result.nil?
				return result.first

			rescue Kesh::TribesAPI::SessionError
				@sessionId = nil
				create_session
				if @sessionId.nil?
					return nil
				end

				result = send_method( "getplayer", nick )
				return nil if result.nil?
				return result.first

			rescue Kesh::TribesAPI::QueryError
				return nil

			rescue Kesh::TribesAPI::ParseError
				return nil

			end

			def get_match_history nick

				create_session if @sessionId.nil?
				
				result = send_method( "getmatchhistory", nick )
				return result

			rescue Kesh::TribesAPI::SessionError
				@sessionId = nil
				create_session
				if @sessionId.nil?
					return nil
				end

				result = send_method( "getmatchhistory", nick )
				return result

			rescue Kesh::TribesAPI::QueryError
				return nil

			rescue Kesh::TribesAPI::ParseError
				return nil

			end

			def get_time_played nick

				create_session if @sessionId.nil?
				
				result = send_method( "gettimeplayed", nick )
				return result

			rescue Kesh::TribesAPI::SessionError
				@sessionId = nil
				create_session
				if @sessionId.nil?
					return nil
				end

				result = send_method( "gettimeplayed", nick )
				return result

			rescue Kesh::TribesAPI::QueryError
				return nil

			rescue Kesh::TribesAPI::ParseError
				return nil

			end

			def get_match_stats matchId

				create_session if @sessionId.nil?
				
				result = send_method( "getmatchstats", matchId )
				return result

			rescue Kesh::TribesAPI::SessionError
				@sessionId = nil
				create_session
				if @sessionId.nil?
					return nil
				end

				result = send_method( "getmatchstats", matchId )
				return result

			rescue Kesh::TribesAPI::QueryError
				return nil

			rescue Kesh::TribesAPI::ParseError
				return nil

			end		

			def get_data_used

				create_session if @sessionId.nil?

				result = send_method( "getdataused" )
				return nil if result.nil?
				return result.first

			rescue Kesh::TribesAPI::SessionError
				@sessionId = nil
				create_session
				if @sessionId.nil?
					return nil
				end

				result = send_method( "getdataused" )
				return nil if result.nil?
				return result.first

			rescue Kesh::TribesAPI::QueryError
				return nil

			rescue Kesh::TribesAPI::ParseError
				return nil

			end	

			private			

			def create_signature method
				timestamp = Time.now.utc.strftime( "%Y%m%d%H%M%S" ).to_i
				signature = Digest::MD5.hexdigest( "#{@devId}#{method}#{@authKey}#{timestamp}" )
				return signature
			end

			def send_method method, *params
				signature = create_signature method
				timestamp = Time.now.utc.strftime( "%Y%m%d%H%M%S" ).to_i

				param = params.first

				if param
					url = "#{@base_url}#{method}Json/#{@devId}/#{signature}/#{@sessionId}/#{timestamp}/#{param}"
				else
					url = "#{@base_url}#{method}Json/#{@devId}/#{signature}/#{@sessionId}/#{timestamp}"
				end

				url << "/" if method.eql?( "getdataused" )

				resp = Net::HTTP.get_response( URI.parse( url ) )
				data = resp.body

				result = JSON.parse( data )

				case method
				when "createsession"
					raise SessionError unless result[ "ret_msg" ].eql?( "Approved" )
				else
					result.each do |r|
						raise SessionError if r[ "ret_msg" ].eql?( "Failed to validate SessionId." )
						raise QueryError unless r[ "ret_msg" ].nil?
					end
				end

				return result

			rescue JSON::ParserError
				raise ParseError

			rescue Errno::ENOENT
				return nil

			end

			def create_session
				result = send_method( "createsession" )
				@sessionId = result[ "session_id" ]
			rescue
				@sessionId = nil
			end

		end
	end
end
