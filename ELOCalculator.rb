#!/usr/bin/ruby

require 'rubygems'
require 'fileutils'
require 'date'
require 'gruff'
require 'cgi'

require File.expand_path( File.dirname( __FILE__ ) + '/Loader.library.rb' )

requireLibrary 'IO'
requireLibrary 'ELO'

Match = Struct.new( :id, :status, :date, :teams, :players, :comment, :results )
Result = Struct.new( :map, :teams, :scores, :comment )

class ELOCalculator

	def initialize multiplier
		@matches = Array.new
		@players = Hash.new
		@dates = Array.new
		@estimated = Hash.new
		@actual = Hash.new
		@ratioNew = Hash.new
		@eloCalculator = Kesh::ELO::ELOCalculator.new
	end

	def load_matches
		load_matches_ini
	end

	def make_plots minMatches
		plot_elo_history minMatches
		plot_elo_performance minMatches
		plot_number_of_matches minMatches
	end

	def calculate_elos *params

		if params.first.nil?
			monthOffset =  0
		else
			monthOffset = params.shift
		end

		@matches.each do |match|

			date = match.date >> monthOffset

			@dates << ( date )

			newPlayers = 0.0
			match.players.each_key do |pN|
				unless @eloCalculator.has_player?( pN )
					@eloCalculator.add_player( pN, 1000, 0 )
					@players[ pN ] = Hash.new
					newPlayers += 1.0
				end
			end

			@ratioNew[ date ] = newPlayers / match.players.keys.length

			scores = @eloCalculator.add_match( match )

			estimatedScores = scores[0]
			@estimated[ date ] = estimatedScores[ match.teams[0] ]

			actualScores = scores[1]
			@actual[ date ] = actualScores[ match.teams[0] ]

			match.players.each_key do |pN|
				if @eloCalculator.has_player?( pN )
					@players[ pN ][ date ] = @eloCalculator.get_elo( pN )
				end
			end

		end

	end

	def write_elo
		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/players.ini' ) )
			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'players.ini' )
			FileUtils.cp( 'players.ini', 'players.bak' )
		else
			ini = Kesh::IO::Storage::IniFile.new
		end

		sectionName = 'ELO'

		@players.each_pair  do |pN, data|

			elo = @eloCalculator.get_elo( pN )
			noMatches = @eloCalculator.get_noMatches( pN )

			unless ( elo.eql?( 1000 ) && noMatches.eql?( 0 ) )
				ini.removeValue( sectionName, CGI::escape( pN ) )
				eloStr = "#{elo} #{noMatches}"
				ini.setValue( sectionName, CGI::escape( pN ), eloStr )
			end

		end

		ini.writeToFile( 'players.ini' )

	end

	private

	def plot_player_elo playerName, minMatches

		unless File.exists?( 'Graphs' )
			FileUtils.mkdir 'Graphs'
		end
		unless File.exists?( File.join( 'Graphs', 'Players' ) )
			FileUtils.mkdir File.join( 'Graphs', 'Players' )
		end

		g = Gruff::Line.new(1600)
		g.title = "ELO History #{playerName}"
		g.dot_radius = 2
		g.line_width = 1
		g.title_font_size = 25

		data = @players[ playerName ]
		dataset = Array.new
		matchNo = 0
		@dates.each do |date|
			matchNo += 1 unless data[ date ].nil?
			dataset << ( matchNo < minMatches ? nil : data[ date ] )
		end

		g.data( "#{playerName}", dataset )

		labels = Hash.new
		@dates.each_index do |index|
			labels[ index ] = @dates[ index ].strftime('%d/%m\n%H:%m')
		end

		# g.labels = labels
		g.marker_font_size = 10

		g.hide_legend = true

		fileName = "Graphs/Players/elo_history_#{playerName}.png"

		g.write( fileName )

	end

	def plot_number_of_matches minMatches

		unless File.exists?( 'Graphs' )
			FileUtils.mkdir 'Graphs'
		end

		g = Gruff::Bar.new(1600)

		g.title = 'Number of matches'

		@players.each_pair do |pN, data|
			g.data( pN, data.keys.length )
			plot_player_elo( pN, minMatches ) if data.keys.length >= minMatches
		end

		g.marker_font_size = 10

		g.hide_legend = true

		g.write('Graphs/number_of_matches.png')

		g = Gruff::Bar.new(1600)

		g.title = 'Number of matches - Reduced'

		@players.each_pair do |pN, data|
			g.data( pN, data.keys.length ) if data.keys.length >= minMatches
		end

		g.marker_font_size = 10

		g.hide_legend = false

		g.write('Graphs/number_of_matches_reduced.png')		

	end

	def plot_elo_performance minMatches

		unless File.exists?( 'Graphs' )
			FileUtils.mkdir 'Graphs'
		end

		g = Gruff::Line.new(1600)
		g.title = "ELO Performance (#{@dates.length} matches, #{@players.keys.length} players)"
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

		g.data('Estimated', datasetEst )
		g.data('Actual', datasetAct )
		g.data('Difference', datasetDiff )
		g.data('New player ratio', datasetNew )

		labels = Hash.new
		@dates.each_index do |index|
			labels[ index ] = @dates[ index ].strftime('%d/%m\n%H:%m')
		end

		# g.labels = labels
		g.marker_font_size = 10

		# g.hide_legend = true

		g.write('Graphs/elo_performance.png')

	end

	def plot_elo_history minMatches

		unless File.exists?( 'Graphs' )
			FileUtils.mkdir 'Graphs'
		end

		g = Gruff::Line.new(1600)
		g.title = 'ELO History'
		g.dot_radius = 2
		g.line_width = 1
		g.title_font_size = 25

		@players.each_pair do |pN, data|
			next if data.keys.length < minMatches
			dataset = Array.new
			@dates.each do |date|
				dataset << data[ date ]
			end
			g.data("#{pN}", dataset )
		end

		labels = Hash.new
		@dates.each_index do |index|
			labels[ index ] = @dates[ index ].strftime('%d/%m\n%H:%m')
		end

		# g.labels = labels
		g.marker_font_size = 10

		g.hide_legend = true

		g.write('Graphs/elo_history.png')

	end

	def load_matches_ini
		if File.exists?( File.expand_path( File.dirname( __FILE__ ) + '/matches.ini' ) )

			ini = Kesh::IO::Storage::IniFile.loadFromFile( 'matches.ini' )

			ini.sections.each do |section|

				id = section.name

				if id[ /^\d+$/ ].nil?
					puts 'Invalid ID: ' + id.to_s
					raise SyntaxError
				end

				idInt = id.to_i

				status = section.getValue( 'Status' )
				next unless ( status.eql?( 'Finished' ) )

				date = DateTime.parse( section.getValue( 'Date' ) )

				players = Hash.new

				teams = section.getValue( 'Teams' )

				if teams.nil?
					teams = Array.new
				else
					teams = teams.split( ' ' )

					teams.each do |team|

						playerNamesStr = section.getValue( "#{team}" )

						unless playerNamesStr.nil?
							playerNames = playerNamesStr.split( ' ' )
							playerNames.each do |pN|
								players[ CGI::unescape( pN ) ] = team
							end
						end

					end

				end

				comment = section.getValue( 'Comment' )
				resultCount = section.getValue( 'ResultCount' )

				if resultCount[ /^\d+$/ ].nil?
					puts 'Invalid Result Count: ' + resultCount.to_s
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

calc = ELOCalculator.new( multiplier )

minMatches = 20

calc.load_matches

repeat = 0
while repeat < 1
	calc.calculate_elos( repeat )
	repeat += 1
end

calc.make_plots repeat * minMatches

calc.write_elo

