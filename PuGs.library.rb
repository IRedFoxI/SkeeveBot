require File.expand_path( File.dirname( __FILE__ ) + '/Loader.library.rb' )

unless ( defined? $PuGsModule )
	puts ( "[Library] PuGs" ) if ( $LoaderModule.getVar( "Verbose" ) >= Kesh::Loader::VERBOSE_LIBRARY )
	$PuGsModule = Kesh::Loader::ModuleInfo.parse( File.dirname( __FILE__ ), "Kesh::PuGs" )
	$PuGsModule.load( false, true )
end
