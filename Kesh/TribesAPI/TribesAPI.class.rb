requireLibrary '../../TribesAPI'

require 'digest/md5'
require 'json'
require 'net/http'

module Kesh
	module TribesAPI

		class TribesAPI

			def initialize base_url, devId, authKey
				@base_url = base_url
				@devId = devId
				@authKey = authKey

				create_session
			end

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

				resp = Net::HTTP.get_response( URI.parse( url ) )
				data = resp.body
				result = JSON.parse( data )

				result = result.kind_of?( Array ) ? result.first : result

				raise QueryError unless result[ "ret_msg" ].nil?

				return result

			rescue JSON::ParserError
				raise ParseError

			end

			def create_session
				signature = create_signature "createsession"
				timestamp = Time.now.utc.strftime( "%Y%m%d%H%M%S" ).to_i

				url = "#{@base_url}createsessionJson/#{@devId}/#{signature}/#{@sessionId}/#{timestamp}"

				resp = Net::HTTP.get_response( URI.parse( url ) )
				data = resp.body
				result = JSON.parse( data )

				raise SessionError unless result[ "ret_msg" ].eql?( "Approved" )

				@sessionId = result[ "session_id" ]
			end

			def get_player nick
				result = send_method( "getplayer", nick )
				return result

			rescue TribesAPI::QueryError
				create_session
				result = send_method( "getplayer", nick )
				return result

			rescue TribesAPI::ParseError
				return nil

			rescue TribesAPI::SessionError
				return nil

			end



		end
	end
end
