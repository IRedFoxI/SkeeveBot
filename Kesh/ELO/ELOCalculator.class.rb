require 'date'
require 'fileutils'

requireLibrary '../../IO'

module Kesh
	module ELO

		class ELOCalculator

			def initialize
				@currentELOs = Hash.new
				@currentNoMatches = Hash.new
				@multiplier = 7
			end

			def add_player playerName, elo, noMatches
				@currentELOs[ playerName ] = elo
				@currentNoMatches[ playerName ] = noMatches
			end

			def has_player? playerName
				return @currentELOs.has_key?( playerName )
			end

			def get_elo playerName
				raise 'Player not initialized' unless @currentELOs.has_key?( playerName )
				return @currentELOs[ playerName ]
			end

			def get_noMatches playerName
				raise 'Player not initialized' unless @currentNoMatches.has_key?( playerName )
				return @currentNoMatches[ playerName ]
			end

			def add_match match
				match.players.each_key do |pN|
					raise 'Player not initialized' unless @currentELOs.has_key?( pN )
					@currentNoMatches[ pN ] += 1
				end
				
				scores = calculate_ELOs( match )

				return scores
			end

			private

			def calculate_ELOs match

				teamELOs = calc_team_ELOs( match )

				estimatedScores = calc_estimated_scores( teamELOs )
				actualScores = calc_actual_scores( match.results )

				match.teams.each do |team|
					match.players.select{ |pN, t| t.eql?( team ) }.each_key do |pN|
						k = calc_k_factor( pN )
						@currentELOs[ pN ] = ( @currentELOs[ pN ] + k * ( actualScores[ team ] - estimatedScores[ team ] ) ).round
					end
				end

				return [ estimatedScores, actualScores ]

			end			

			def calc_team_ELOs match

				teamELOs = Hash.new

				match.teams.each do |team|

					noPlayers = 0
					teamELOs[ team ] = 0

					match.players.select{ |pN, t| t.eql?( team ) }.each_key do |pN|
						noPlayers += 1
						teamELOs[ team ] += @currentELOs[ pN ]
					end

					teamELOs[ team ] = teamELOs[ team ] / noPlayers

				end

				return teamELOs

			end

			def calc_k_factor playerName

				if @currentELOs[ playerName ] < 2100
					k = 32
				elsif @currentELOs[ playerName ] > 2400
					k = 16
				else
					k = 24
				end

				k *= calc_init_factor( @currentNoMatches[ playerName ] )

				return k
			end

			def calc_init_factor matchNumber
				factor = 1
				# factor *= 1 + 1.1 ** ( -2 * matchNumber )
				# factor *= 1 + 1.2 ** ( 10 - 2 * matchNumber )
				# factor *= 1 + 1.2 ** ( 10 - matchNumber )
				# factor *= 1 + 1.258925412 ** ( 3.080105496E-21 - matchNumber ) # 2 to 1.01 between 0 to 20
				# factor *= 1 + 1.303321321 ** ( 2.616480413 - matchNumber ) # 3 to 1.01 between 0 to 20
				factor *= 1 + 1.330013541 ** ( 3.852223655 - matchNumber ) # 4 to 1.01 between 0 to 20
				# factor *= 1 + 1.349282848 ** ( 4.627564263 - matchNumber ) # 5 to 1.01 between 0 to 20
				# factor *= 1 + 1.36442133 ** ( 5.179531475 - matchNumber ) # 6 to 1.01 between 0 to 20
				factor *= @multiplier
				return factor
			end

			# @param results [Array<(Result)>]
			def calc_actual_scores results

				actualScores = Hash.new

				mapWins = [ 0, 0 ]

				teams = results[0].teams

				results.each do |result|
					if result.scores[0] > result.scores[1]
						mapWins[0] += 1
					elsif result.scores[0] < result.scores[1]
						mapWins[1] += 1
					else
						# Not a valid outcome
					end
				end

				if mapWins[0] == mapWins[1]
					score = 0.5
				else
					totalMaps = mapWins[0] + mapWins[1]
					if totalMaps == 1
						score = 1.0
					elsif totalMaps == 2
						score = 0.75
					elsif totalMaps == 3
						score = 0.6
					else
						score = 0.5
					end
				end

				if mapWins[0] > mapWins[1]
					actualScores[ teams[0] ] = score
					actualScores[ teams[1] ] = 1 - score
				elsif mapWins[0] < mapWins[1]
					actualScores[ teams[0] ] = 1 - score
					actualScores[ teams[1] ] = score
				else
					actualScores[ teams[0] ] = score
					actualScores[ teams[1] ] = 1 - score
				end

				return actualScores

			end

			def calc_estimated_scores teamELOs

				estimatedScores = Hash.new
				teams = teamELOs.keys

				rA = teamELOs[ teams[0] ]
				rB = teamELOs[ teams[1] ]

				estScrA = 1 / ( 1 + 10 **( (rB-rA)/400.0 ) )
				estScrB = 1 / ( 1 + 10 **( (rA-rB)/400.0 ) )

				estimatedScores[ teams[0] ] = estScrA
				estimatedScores[ teams[1] ] = estScrB

				return estimatedScores

			end

		end
	end
end
