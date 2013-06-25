
class Enum

	# Declare a new enum with the given values.
	# @param enumValues [Array<(Symbol)>] The values of the enum.
	def self.new *enumValues
		klass = Class.new

		klass.class_eval <<-EOT.gsub(/^\s+\|/, ''), __FILE__, __LINE__ + 1
		|	private
		|		def initialize innerVal
		|			@innerValue = innerVal
		|		end
		EOT

		klass.class_eval <<-EOT.gsub(/^\s+\|/, ''), __FILE__, __LINE__ + 1
		|	def innerValue
		|		return @innerValue
		|	end
		EOT

		i = 0
		enumValues.each do |val|
			klass.class_eval "#{val.to_s} = self.new(#{i})", __FILE__, __LINE__
			i += 1
		end

		klass.class_eval <<-EOT.gsub(/^\s+\|/, ''), __FILE__, __LINE__ + 1
		|	def self.parse val
		|		if val.nil? || !val.is_a?(String)
		|			return nil
		|		else
		|			case val.downcase
		#{
			a = Array.new
			i = 0
			enumValues.each do |val|
				a.push("when '#{val.to_s.downcase}'")
				a.push("return self.new(#{i})")
				i += 1
			end
			a.join("\n")
		}
		|			else
		|				return nil
		|			end
		|		end
		|	end
		EOT

		klass.class_eval <<-EOT.gsub(/^\s+\|/, ''), __FILE__, __LINE__ + 1
		| def to_s
		|   case @innerValue
		#{
			a = Array.new
			i = 0
			enumValues.each do |val|
				a.push("when #{i}")
				a.push("return '#{val.to_s}'")
				i += 1
			end
			a.join("\n")
		}
		|		else
		|			fail "Invalid innerValue!"
		|		end
		|	end
		EOT

		klass.class_eval <<-EOT.gsub(/^\s+\|/, ''), __FILE__, __LINE__ + 1
		|	def inspect
		|		return "\#{self.to_s} (\#{@innerValue})"
		|	end
		EOT

		klass.class_eval <<-EOT.gsub(/^\s+\|/, ''), __FILE__, __LINE__ + 1
		|	def != other
		|		return !(self == other)
		|	end
		EOT

		klass.class_eval <<-EOT.gsub(/^\s+\|/, ''), __FILE__, __LINE__ + 1
		|	def == other
		|		if other.nil?
		|			return false
		|		else
		|			if other.is_a? self.class
		|				return @innerValue == other.innerValue
		|			elsif other.is_a? String
		|				return @innerValue == self.class.parse(other).innerValue
		|			elsif other.is_a? Numeric
		|				return @innerValue == other
		|			else
		|				fail 'Unknown type to compare to!'
		|			end
		|		end
		|	end
		EOT

		klass.class_eval <<-EOT.gsub(/^\s+\|/, ''), __FILE__, __LINE__ + 1
		|	def eql? other
		|		return self == other
		|	end
		EOT


		klass.class_eval <<-EOT.gsub(/^\s+\|/, ''), __FILE__, __LINE__ + 1
		|	def === other
		|		return self == other
		|	end
		EOT

		klass.class_eval <<-EOT.gsub(/^\s+\|/, ''), __FILE__, __LINE__ + 1
		|	def hash
		|		return @innerValue.hash
		|	end
		EOT

		return klass
	end
end


