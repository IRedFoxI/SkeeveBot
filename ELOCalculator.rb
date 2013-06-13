#!/usr/bin/ruby

require 'rubygems'
require 'fileutils'
require 'date'
require 'gruff'

require File.expand_path( File.dirname( __FILE__ ) + '/Loader.library.rb' )

requireLibrary 'IO'

Match = Struct.new( :id, :status, :date, :teams, :players, :comment, :results )
Result = Struct.new( :map, :teams, :scores, :comment )

class ELOCalculator

	def initialize multiplier
		@matches = Array.new
		@currentELOs = Hash.new
		@players = Hash.new
		@dates = Array.new
		@estimated = Hash.new
		@actual = Hash.new
		@ratioNew = Hash.new
		@multiplier = multiplier
	end

	def load_matches
		load_matches_ini
	end

	def make_plots param
		plot_elo_history param * 10
		plot_elo_performance param * 10
		plot_number_of_matches param * 10
	end

	def calculate_elos *params

		if params.first.nil?
			monthOffset =  0
		else
			monthOffset = params.shift
		end

		if params.first.nil?
			weightedAverage = false
		elsif params.shift
			weightedAverage = true
		end

		@matches.each do |match|

			date = match.date >> monthOffset

			@dates << ( date )

			newPlayers = 0.0
			match.players.each_key do |pN|
				unless @currentELOs.has_key?( pN )
					newPlayers += 1.0
				end
			end

			@ratioNew[ date ] = newPlayers / match.players.keys.length

			teamELOs = calc_team_ELOs( match, weightedAverage )

			estimatedScores = calc_estimated_scores( teamELOs )
			@estimated[ date ] = estimatedScores[ match.teams[0] ]

			actualScores = calc_actual_scores( match.results )
			@actual[ date ] = actualScores[ match.teams[0] ]

			match.teams.each do |team|

				match.players.select{ |pN, t| t.eql?( team ) }.each_key do |pN|

					k = calc_k_factor( pN )

					@currentELOs[ pN ] = ( @currentELOs[ pN ] + k * ( actualScores[ team ] - estimatedScores[ team ] ) ).round

					unless @players.has_key?( pN )
						@players[ pN ] = Hash.new
					end

					@players[ pN ][ date ] = @currentELOs[ pN ]

				end

			end

		end

	end

	private

	def calc_team_ELOs match, weightedAverage

		teamELOs = Hash.new

		match.teams.each do |team|

			noPlayers = 0
			totalWeight = 0

			teamELOs[ team ] = 0

			match.players.select{ |pN, t| t.eql?( team ) }.each_key do |pN|
				playerELO = get_player_elo( pN )

				k = calc_k_factor( pN )
				totalWeight += 1.0 / k
				noPlayers += 1

				if weightedAverage
					teamELOs[ team ] += playerELO / k
				else
					teamELOs[ team ] += get_player_elo( pN )
				end

			end

			if weightedAverage
				teamELOs[ team ] = teamELOs[ team ] / totalWeight
			else
				teamELOs[ team ] = teamELOs[ team ] / noPlayers
			end

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

		matchNumber = 1

		if @players.has_key?( playerName )
			matchNumber += @players[ playerName ].keys.length
		end

		k *= calc_init_factor( matchNumber )

		return k
	end

	def plot_player_elo playerName

		g = Gruff::Line.new(1600)
		g.title = "ELO History #{playerName}"
		g.dot_radius = 2
		g.line_width = 1
		g.title_font_size = 25

		data = @players[ playerName ]
		dataset = Array.new
		@dates.each do |date|
			dataset << data[ date ]
		end

		g.data( "#{playerName}", dataset )

		labels = Hash.new
		@dates.each_index do |index|
			labels[ index ] = @dates[ index ].strftime("%d/%m\n%H:%m")
		end

		# g.labels = labels
		g.marker_font_size = 10

		g.hide_legend = true

		fileName = "Graphs/Players/elo_history_#{playerName}.png"

		g.write( fileName )

	end

	def calc_init_factor matchNumber
		# factor = 1 + 1.1 ** ( -2 * matchNumber )
		# factor = 1 + 1.2 ** ( 10 - 2 * matchNumber )
		factor = 1 + 1.2 ** ( 10 - matchNumber )
		factor = factor * @multiplier
		return factor
	end

	def plot_number_of_matches minMatches

		g = Gruff::Bar.new(1600)

		g.title = "Number of matches"

		@players.each_pair do |pN, data|
			g.data( pN, data.keys.length )
			plot_player_elo( pN ) if data.keys.length >= minMatches
		end

		g.marker_font_size = 10

		g.hide_legend = true

		g.write('Graphs/number_of_matches.png')

		g = Gruff::Bar.new(1600)

		g.title = "Number of matches - Reduced"

		@players.each_pair do |pN, data|
			g.data( pN, data.keys.length ) if data.keys.length >= minMatches
		end

		g.marker_font_size = 10

		g.hide_legend = false

		g.write('Graphs/number_of_matches_reduced.png')		

	end

	def plot_elo_performance param

		g = Gruff::Line.new(1600)
		g.title = "ELO Performance"
		g.dot_radius = 2
		g.line_width = 1
		g.title_font_size = 25

		datasetEst = Array.new
		datasetAct = Array.new
		datasetDiff = Array.new
		datasetNew = Array.new
		@dates.each do |date|
			datasetEst << @estimated[ date ]
			datasetAct << @actual[ date ]
			datasetDiff << ( @estimated[ date ] - @actual[ date ] ).abs
			datasetNew << @ratioNew[ date ]
		end

		g.data("Estimated", datasetEst )
		g.data("Actual", datasetAct )
		g.data("Difference", datasetDiff )
		g.data("New player ratio", datasetNew )

		labels = Hash.new
		@dates.each_index do |index|
			labels[ index ] = @dates[ index ].strftime("%d/%m\n%H:%m")
		end

		# g.labels = labels
		g.marker_font_size = 10

		# g.hide_legend = true

		g.write('Graphs/elo_performance.png')

	end

	def plot_elo_history param

		g = Gruff::Line.new(1600)
		g.title = "ELO History"
		g.dot_radius = 2
		g.line_width = 1
		g.title_font_size = 25

		@players.each_pair do |pN, data|
			next if data.keys.length < param
			dataset = Array.new
			@dates.each do |date|
				dataset << data[ date ]
			end
			g.data("#{pN}", dataset )
		end

		labels = Hash.new
		@dates.each_index do |index|
			labels[ index ] = @dates[ index ].strftime("%d/%m\n%H:%m")
		end

		# g.labels = labels
		g.marker_font_size = 10

		g.hide_legend = true

		g.write('Graphs/elo_history.png')

	end

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

	def get_player_elo playerName
		return @currentELOs[ playerName ] if @currentELOs.has_key?( playerName )
		return (@currentELOs[ playerName ] = 1000)
	end

	def load_matches_ini
		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/matches.ini' ) )

			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'matches.ini' )

			ini.sections.each do |section|

				id = section.name

				if id[ /^\d+$/ ].nil?
					puts "Invalid ID: " + id.to_s
					raise SyntaxError
				end

				idInt = id.to_i

				status = section.getValue( "Status" )
				next unless ( status.eql?( "Finished" ) )

				date = DateTime.parse( section.getValue( "Date" ) )

				players = Hash.new

				teams = section.getValue( "Teams" )

				if teams.nil?
					teams = Array.new
				else
					teams = teams.split( ' ' )

					teams.each do |team|

						playerNames = section.getValue( "#{team}" )

						unless playerNames.nil?
							playerNames = playerNames.split( ' ' )
							playerNames.each do |pN|
								players[ pN ] = team
							end
						end

					end

				end

				comment = section.getValue( "Comment" )
				resultCount = section.getValue( "ResultCount" )

				if resultCount[ /^\d+$/ ].nil?
					puts "Invalid Result Count: " + resultCount.to_s
					raise SyntaxError
				end

				results = Array.new

				rCount = resultCount.to_i

				next if rCount == 0

				rIndex = 0

				while rIndex < rCount

					rMap = section.getValue( "Result#{rIndex}Map")
					rTeams = teams
					rScores = Array.new

					teams.each do |team|
						rScores << section.getValue( "Result#{rIndex}#{team}" ).to_i
					end

					rComment = section.getValue( "Result#{rIndex}Comment")

					results << Result.new( rMap, rTeams, rScores, rComment )

					rIndex = rIndex + 1

				end

				next if (rCount == 1) && results[ 0 ].scores == [ 0, 0 ]

				@matches << Match.new( idInt, status, date, teams, players, comment, results )

			end

		end

	end

end

multiplier = 7
calc = ELOCalculator.new( multiplier )

calc.load_matches

weightedAverage = true

repeat = 0
while repeat < 1
	calc.calculate_elos( repeat, weightedAverage )
	repeat += 1
end

calc.make_plots repeat

