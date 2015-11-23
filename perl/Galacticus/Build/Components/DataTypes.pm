# Contains a Perl module which handles data types for the component build system.

package DataTypes;
my $galacticusPath;
if ( exists($ENV{"GALACTICUS_ROOT_V094"}) ) {
    $galacticusPath = $ENV{"GALACTICUS_ROOT_V094"};
    $galacticusPath .= "/" unless ( $galacticusPath =~ m/\/$/ );
} else {
    $galacticusPath = "./";
}
unshift(@INC, $galacticusPath."perl"); 
use strict;
use warnings;
use utf8;
use LaTeX::Encode;

sub dataObjectPrimitiveName {
    # Construct and return the name and attributes of the primitive data class to use for data of given type and rank.
    my $dataObject = shift();
    my %options;
    (%options) = @_
	if ( $#_ >= 1 );
    # Validate input.
    foreach ( "rank", "type" ) {
	die "DataTypes::dataObjectPrimitveName: no '".$_."' specifier present"
	    unless ( exists($dataObject->{$_}) );
    }
    # Construct name, type, and attributes.
    my $name = 
	exists($Utils::intrinsicTypes{$dataObject->{'type'}}) 
	?
	       $Utils::intrinsicTypes{$dataObject->{'type'}} 
        :
	"type(".                      $dataObject->{'type'}.")";    
    my $type = join("",map {ucfirst($_)} split(" ",$dataObject->{'type'}));
    my @attributes;
    if ( $dataObject->{'rank'} > 0 ) {
	push(@attributes,"dimension(".join(",",(":") x $dataObject->{'rank'}).")");
	push(@attributes,"allocatable" )
	    unless ( exists($options{'matchOnly'}) && $options{'matchOnly'} );
    }
    my $attributeList = scalar(@attributes) > 0 ? ", ".join(", ",@attributes) : "";
    return ($name,$type,$attributeList);
}

sub dataObjectDocName {
    # Construct and return the name of the object to use in documentation for data of given type and rank.
    my $dataObject = shift();
    # Validate input.
    foreach ( "type" ) {
	die "DataTypes::dataObjectPrimitveName: no '".$_."' specifier present"
	    unless ( exists($dataObject->{$_}) );
    }
    # Determine the data object's rank.
    my $rank = exists($dataObject->{'rank'}) ? $dataObject->{'rank'} : 0;
    # Construct the documentation.
    return
	"\\textcolor{red}{\\textless ".
	(
	 exists              ($Utils::intrinsicTypes{$dataObject->{'type'}})
	 ?
	         latex_encode($Utils::intrinsicTypes{$dataObject->{'type'}})
	 :
	 "type(".latex_encode(                       $dataObject->{'type'} ).")"
	).
	(
	 $rank > 0
	 ?
	 "[".join(",",(":") x $rank)."]"
	 :
	 ""
	).
	"\\textgreater}";
}

1;
