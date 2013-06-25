require File.expand_path( File.dirname( __FILE__ ) + '/Loader.library.rb' )

unless ( defined? $TribesAPIModule )
	puts ( "[Library] TribesAPI" ) if ( $LoaderModule.getVar( "Verbose" ) >= Kesh::Loader::VERBOSE_LIBRARY )
	$TribesAPIModule = Kesh::Loader::ModuleInfo.parse( File.dirname( __FILE__ ), "Kesh::TribesAPI" )
	$TribesAPIModule.load( false, true )
end
