require File.expand_path( File.dirname( __FILE__ ) + '/Loader.library.rb' )

unless ( defined? $ELOModule )
	puts ( "[Library] ELO" ) if ( $LoaderModule.getVar( "Verbose" ) >= Kesh::Loader::VERBOSE_LIBRARY )
	$ELOModule = Kesh::Loader::ModuleInfo.parse( File.dirname( __FILE__ ), "Kesh::ELO" )
	$ELOModule.load( false, true )
end
