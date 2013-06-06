#!/usr/bin/ruby

require 'rubygems'
require 'optparse'
require 'pp'
require 'fileutils'

require File.expand_path( File.dirname( __FILE__ ) + '/Loader.library.rb' )
require File.expand_path( File.dirname( __FILE__ ) + '/Bot.class.rb' )
require File.expand_path "../config", __FILE__

op = OptionParser.new do |opts|
	opts.banner = "Usage: run_bot.rb [OPTIONS] \n\n"
	opts.on("-d", "--debug", "Debugging.") do
		$options[:debug] = true
	end
	opts.on("-h", "--help", "This Help") do |h|
		puts opts.help();
		exit 0;
	end
	opts.separator("")
	opts.separator("Example:")
	opts.separator("  run_bot.rb")
	opts.separator("")
	opts.separator("Configure:")
	opts.separator("  edit your config.rb")
	opts.separator("")
end

op.parse!

if (ARGV.length < 0)
	puts "Parameter 'Server' Missing:"
	puts op.help
	exit 0
end


exitflag = true
while exitflag

	bot = Bot.new $options

	trap("INT") do
		bot.exit_by_user
		exit 0
	end

	#Thread.abort_on_exception = true

	begin
		exitflag = bot.run $servers
	rescue => e
		# TODO: Message all connected superusers when this occurs
		puts("An unhandled exception occurred '#{e}'!");
	end
	
	sleep 0.2
end



