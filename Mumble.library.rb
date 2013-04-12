require File.expand_path( File.dirname( __FILE__ ) + '/Loader.library.rb' )

unless ( defined? $MumbleModule )
	puts ( "[Library] Mumble" ) if ( $LoaderModule.getVar( "Verbose" ) >= Kesh::Loader::VERBOSE_LIBRARY )
	$MumbleModule = Kesh::Loader::ModuleInfo.parse( File.dirname( __FILE__ ), "Kesh::Mumble" )
	$MumbleModule.load( false, true )
end
