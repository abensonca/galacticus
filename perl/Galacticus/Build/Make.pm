# Contains a Perl module which provides utilities for Galacticus' Make system.

package Galacticus::Build::Make;
use strict;
use warnings;

sub Module_Name {
    # Return the module name associated with a file.
    my $fileName = shift;
    (my %options) = @_
	if ( scalar(@_) > 1 );
    my $moduleName;
    if ( exists($options{'default'}) ) {
	if ( $options{'default'} eq 'self' ) {
	    $moduleName = $fileName;
	}
    }
    my $moduleFileName = $ENV{'BUILDPATH'}."/".$fileName.".m";
    if ( -e $moduleFileName ) {
	open(my $moduleHandle,$moduleFileName);
	($moduleName =<$moduleHandle>) =~ s/$ENV{'BUILDPATH'}\/(.*)\.mod\n$/$1/
	    unless ( eof($moduleHandle) );
	close($moduleHandle);
    }
    return $moduleName;
}

1;
