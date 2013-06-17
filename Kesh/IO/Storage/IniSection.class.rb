requireLibrary '../../../IO'
requireClass '../Serialisable'
requireClass 'IniValue'

module Kesh
	module IO
		module Storage
	
			class IniSection < Kesh::IO::Serialisable
			
				attr_reader :name
				attr_reader :values
				
				def initialize( name )
					@name = name
					@values = []
				end
				
				
				private
				def getNameIndex( name )
					@values.each_index do |i|
						return i if ( @values[ i ].name == name )
					end
					return -1
				end
				
				
				public
				def getValue( name )
					i = getNameIndex( name )
					return nil if ( i == -1 )
					return @values[ i ].value
				end
				
				
				def setValue( name, value )
					i = getNameIndex( name )
					
					if i == -1
						@values.push( IniValue.new( name, value ) )
						return true
					end
					
					@values[ i ].value = value
					return false
				end
				

				def hasValue?( name )
					return ( getNameIndex( name ) != -1 )
				end					
				
				
				def removeValue( name )
					i = getNameIndex( name )
					return false if ( i == -1 )
					@values.delete_at( i )
					return true
				end

				
				def serialise( stream )
					ArgTest::type( "stream", stream, Kesh::IO::Stream )
					
					stream.writeLine( "[" + name + "]" )
					
					@values.each do |value|
						value.serialise( stream )
					end
					
					stream.writeLine( "" )
				end
				
				
				def IniSection.deserialise( stream )
					ArgTest::type( "stream", stream, Kesh::IO::Stream )
					
					line = stream.readLine()		
					return nil if line.nil?
					line.strip!
					
					unless line[ /^\[([^\]]+)\]$/ ]
						puts line
						raise SyntaxError
					end
						
					section = IniSection.new( $1 )
					
					loop do
						value = IniValue.deserialise( stream )
						section.values.push( value ) unless value.nil?
						break if value.nil?
					end
					
					return section
				end
						
			end
			
		end
	end
end
