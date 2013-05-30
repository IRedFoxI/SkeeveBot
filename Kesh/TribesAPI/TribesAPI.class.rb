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
				result = send_method( "createsession" )
				raise SessionError, 'Session not approved' unless result[ "ret_msg" ].eql?( "Approved" )
				@sessionId = result[ "session_id" ]
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

				return result.kind_of?( Array ) ? result[ 0 ] : result

			rescue JSON::ParserError
				raise ParseError, 'Error parsing response'
			end

		end
	end
end
