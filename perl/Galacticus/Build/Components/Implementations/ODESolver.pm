# Contains a Perl module which provides various ODE solver-related functions for component implementations.

package Galacticus::Build::Components::Implementations::ODESolver;
use strict;
use warnings;
use utf8;
use Cwd;
use lib exists($ENV{'GALACTICUS_ROOT_V094'}) ? $ENV{'GALACTICUS_ROOT_V094'}.'/perl' : cwd().'/perl';
use Text::Template 'fill_in_string';
use Data::Dumper;
use List::ExtraUtils;
use Galacticus::Build::Components::Utils qw(offsetName);
use Galacticus::Build::Components::DataTypes;
use Galacticus::Build::Components::Implementations::Utils;

# Insert hooks for our functions.
%Galacticus::Build::Component::Utils::componentUtils = 
    (
     %Galacticus::Build::Component::Utils::componentUtils,
     implementationODESolver =>
     {
	 implementationIteratedFunctions =>
	     [
	      \&Implementation_ODE_Serialize_Count   ,
	      \&Implementation_ODE_Serialize_Values  ,
	      \&Implementation_ODE_Deserialize_Values,
	      \&Implementation_ODE_Name_From_Index   ,
	      \&Implementation_ODE_Offsets           ,
	      \&Implementation_ODE_Offset_Variables
	     ],
	 functions =>
	     [
	      \&Implementation_ODE_Rate_Variables
	     ]
     }
    );

sub Implementation_ODE_Name_From_Index {
    # Generate a function to return the name of a property given the index of that property in the serialization of a component
    # implementation.
    my $build     = shift();
    $code::class  = shift();
    $code::member = shift();
    my $implementationTypeName = "nodeComponent".ucfirst($code::class->{'name'}).ucfirst($code::member->{'name'});
    my $function =
    {
	type        => "type(varying_string) => name",
	name        => $implementationTypeName."NameFromIndex",
	description => "Return the name of the property of given index for a {\\normalfont \\ttfamily ".$code::member->{'name'}."} implementation of the {\\normalfont \\ttfamily ".$code::class->{'name'}."} component class.",
	modules     =>
	    [
	     "ISO_Varying_String"
	    ],
	variables   =>
	    [
	     {
		 intrinsic  => "class",
		 type       => $implementationTypeName,
		 attributes => [ "intent(in   )" ],
		 variables  => [ "self" ]
	     },
	     {
		 intrinsic  => "integer",
		 attributes => [ "intent(inout)" ],
		 variables  => [ "count" ]
	     }
	    ]
    };
    # Determine if "self" will be used. It is used iff the implementation extends another implementation, or if any
    # property is evolveable and is not a rank-0 double.
    undef(@code::unused);
    push(@code::unused,"self")
	unless (
	    exists($code::member->{'extends'})
	    ||
	    &Galacticus::Build::Components::Implementations::Utils::hasRealNonTrivialEvolvers($code::member)
	);
    # Determine if "count" will be used. It is used iff the implementation extends another implementation, or if any
    # property is evolveable.
    push(@code::unused,"count")
	unless (
	    exists($code::member->{'extends'})
	    ||
	    &Galacticus::Build::Components::Implementations::Utils::hasRealEvolvers          ($code::member)
	);
    # Build the function.
    $function->{'content'}  = "";
    if ( scalar(@code::unused) > 0 ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
!GCC$ attributes unused :: {join(",",@unused)}
CODE
    }
    # If this component is an extension, first call on the extended type.
    if ( exists($code::member->{'extends'}) ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
name=self%nodeComponent{ucfirst($member->{'extends'}->{'class'}).ucfirst($member->{'extends'}->{'name'})}%nameFromIndex(count)
if (count <= 0) return
CODE
    }
    # Iterate over non-virtual, evolvable properties.
    foreach $code::property ( &Galacticus::Build::Components::Implementations::Utils::listRealEvolvers($code::member) ) {
	# Find condition for count update. For allocatable properties, condition is that the object be allocated. For
	# non-allocatable properties, always update the count.
	$code::condition = 
	    $code::property->{'data'}->{'rank'} > 0 
	    ? 
	    "if (allocated(self%".$code::property->{'name'}."Data)) "
	    :
	    "";
	# Find the size of the object. Rank-0 double properties always have a count of 1. For other rank-0 types, call
	# their serialization count method. Rank>0 must be double, so simply use the array length.
	$code::count     = 
	    $code::property->{'data'}->{'rank'} > 0 
	    ?
	    "size(self%".$code::property->{'name'}."Data)"
	    :
	    (
	     $code::property->{'data'}->{'type'} eq "double"
	     ?
	     "1" 
	     : 
	     "self%".$code::property->{'name'}."Data%serializeCount()"
	    );
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
{$condition}count=count-{$count}
CODE
	        $function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
if (count <= 0) then
  name='{$class->{'name'}}:{$member->{'name'}}:{$property->{'name'}}'
  return
end if
CODE
    }
    $function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
name='?'
CODE
    # Insert a type-binding for this function into the treeNode type.
    push(
	@{$build->{'types'}->{$implementationTypeName}->{'boundFunctions'}},
	{
	    type        => "procedure", 
	    descriptor  => $function,
	    name        => "nameFromIndex"
	}
	);	    
}

sub Implementation_ODE_Serialize_Count {
    # Generate a function to return a count of serializable, evolvable properties of each component implementation for the ODE solver.
    my $build     = shift();
    $code::class  = shift();
    $code::member = shift();
    $code::implementationTypeName = "nodeComponent".ucfirst($code::class->{'name'}).ucfirst($code::member->{'name'});
    my $function =
    {
	type        => "integer",
	name        => $code::implementationTypeName."SerializeCount",
	description => "Return a count of the serialization of a ".$code::member->{'name'}." implementation of the ".$code::class->{'name'}." component.",
	variables   =>
	    [
	     {
		 intrinsic  => "class",
		 type       => $code::implementationTypeName,
		 attributes => [ "intent(in   )" ],
		 variables  => [ "self" ]
	     }
	    ]
    };
    # Determine if "self" will be used. It is used iff the implementation extends another implementation, or if any
    # property is evolveable and is not a rank-0 double.
    undef(@code::unused);
    push(@code::unused,"self")
	unless (
	    exists($code::member->{'extends'})
	    ||
	    &Galacticus::Build::Components::Implementations::Utils::hasRealNonTrivialEvolvers($code::member)
	);
    # Build the function.
    $function->{'content'}  = "";
    if ( scalar(@code::unused) > 0 ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
!GCC$ attributes unused :: {join(",",@unused)}
CODE
    }
    # If this component is an extension, first call on the extended type.
    $function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
{$implementationTypeName}SerializeCount={exists($member->{'extends'}) ? "self%nodeComponent".ucfirst($member->{'extends'}->{'class'}).ucfirst($member->{'extends'}->{'name'})."%serializeCount()" : "0"}
CODE
    # Initialize count of fixed, scalar properties to zero.
    $code::scalarPropertyCount = 0;
    # Iterate over non-virtual, evolvable properties.
    foreach $code::property ( &Galacticus::Build::Components::Implementations::Utils::listRealEvolvers($code::member) ) {
	if ( $code::property->{'data'}->{'rank'} == 0 && $code::property->{'data'}->{'type'} eq "double" ) {
	    ++$code::scalarPropertyCount;
	} else {		
	    # Find condition for count update. For allocatable properties, condition is that the object be allocated. For
	    # non-allocatable properties, always update the count.
	    $code::condition = 
		$code::property->{'data'}->{'rank'} > 0 
		? 
		"if (allocated(self%".$code::property->{'name'}."Data)) "
		:
		"";
	    # Find the size of the object. Rank-0 double properties always have a count of 1. For other rank-0 types, call
	    # their serialization count method. Rank>0 must be double, so simply use the array length.
	    $code::count     = 
		$code::property->{'data'}->{'rank'} > 0 
		?
		"size(self%".$code::property->{'name'}."Data)"
		:
		"self%".$code::property->{'name'}."Data%serializeCount()";
	    $function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
{$condition}{$implementationTypeName}SerializeCount={$implementationTypeName}SerializeCount+{$count}
CODE
	}
    }
    # Add count of scalar properties.
    if ( $code::scalarPropertyCount > 0 ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
{$implementationTypeName}SerializeCount={$implementationTypeName}SerializeCount+{$scalarPropertyCount}
CODE
    }
    # Insert a type-binding for this function into the treeNode type.
    push(
	@{$build->{'types'}->{$code::implementationTypeName}->{'boundFunctions'}},
	{
	    type        => "procedure", 
	    descriptor  => $function,
	    name        => "serializeCount"
	}
	);	    
}

sub Implementation_ODE_Serialize_Values {
    # Generate a function to serialize values of evolvable properties of each component implementation to array for the ODE solver.
    my $build     = shift();
    $code::class  = shift();
    $code::member = shift();
    my $implementationTypeName = "nodeComponent".ucfirst($code::class->{'name'}).ucfirst($code::member->{'name'});
    my $function =
    {
	type        => "void",
	name        => $implementationTypeName."SerializeValues",
	description => "Serialize evolvable properties of a {\\normalfont \\ttfamily ".$code::member->{'name'}."} implementation of the {\\normalfont \\ttfamily ".$code::class->{'name'}."} component to array.",
	variables   =>
	    [
	     {
		 intrinsic  => "class",
		 type       => $implementationTypeName,
		 attributes => [ "intent(in   )" ],
		 variables  => [ "self" ]
	     },
	     {
		 intrinsic  => "double precision",
		 attributes => [ "intent(  out)", "dimension(:)" ],
		 variables  => [ "array" ]
	     }
	    ]
    };
    # Conditionally add "offset" and "count" variables if they will be needed.
    my @requiredVariables;
    push(@requiredVariables,"count")
	if
	(
	 exists($code::member->{'extends'})
	 ||
	 &Galacticus::Build::Components::Implementations::Utils::hasRealNonTrivialEvolvers($code::member)
	);
    push(@requiredVariables,"offset")
	if
	(
	 exists($code::member->{'extends'})
	 ||
	 &Galacticus::Build::Components::Implementations::Utils::hasRealEvolvers          ($code::member)
	);	   
    push(@{$function->{'variables'}},
	 {
	     intrinsic  => "integer",
	     variables  => \@requiredVariables
	 }
	)
	if ( scalar(@requiredVariables) > 0 );
    # Determine if the function arguments are unused.
    @code::unused = 
	(
	 exists($code::member->{'extends'})
	 ||
	 &Galacticus::Build::Components::Implementations::Utils::hasRealEvolvers          ($code::member)
	)
	?
	()
	:
	("self","array");
    # Build the function.
    $function->{'content'} = "";
    if ( scalar(@code::unused) > 0 ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
!GCC$ attributes unused :: {join(",",@unused)}
CODE
    }
    # Initialize offset if required.
    if ( grep {$_ eq "offset"} @requiredVariables ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
offset=1
CODE
    }    
    # If this component is an extension, call serialization on the extended type.
    if ( exists($code::member->{'extends'}) ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
count=self%nodeComponent{ucfirst($code::member->{'extends'}->{'class'}).ucfirst($code::member->{'extends'}->{'name'})}%serializeCount (     )
if (count > 0) then
 call self%nodeComponent{ucfirst($code::member->{'extends'}->{'class'}).ucfirst($code::member->{'extends'}->{'name'})}%serializeValues(array)
 offset=offset+count
end if
CODE
    }
    # Iterate over non-virtual, evolvable properties.
    foreach $code::property ( &Galacticus::Build::Components::Implementations::Utils::listRealEvolvers($code::member) ) {
	if ( $code::property->{'data'}->{'rank'} == 0 ) {
	    if ( $code::property->{'data'}->{'type'} eq "double" ) {
		$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
array(offset)=self%{$property->{'name'}}Data
offset=offset+1
CODE
	    } else {
		$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
count=self%{$property->{'name'}}Data%serializeCount()
if (count > 0) call  self%{$property->{'name'}}Data%serialize(array(offset:offset+count-1))
offset=offset+count
CODE
	    }
	} else {
	    $function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
if (allocated(self%{$property->{'name'}}Data)) then
   count=size(self%{$property->{'name'}}Data)
   array(offset:offset+count-1)=reshape(self%{$property->{'name'}}Data,[count])
   offset=offset+count
end if
CODE
	}
    }
    # Insert a type-binding for this function into the implementation type.
    push(
	@{$build->{'types'}->{$implementationTypeName}->{'boundFunctions'}},
	{
	    type        => "procedure",
	    descriptor  => $function,
	    name        => "serializeValues"
	}
	);	    
}

sub Implementation_ODE_Deserialize_Values {
    # Generate a function to deserialize values of evolvable properties of each component implementation from array for the ODE solver.
    my $build     = shift();
    $code::class  = shift();
    $code::member = shift();
    my $implementationTypeName = "nodeComponent".ucfirst($code::class->{'name'}).ucfirst($code::member->{'name'});
    my $function =
    {
	type        => "void",
	name        => $implementationTypeName."DeserializeValues",
	description => "Deserialize evolvable properties of a ".$code::member->{'name'}." implementation of the ".$code::class->{'name'}." component from array.",
	variables   =>
	    [
	     {
		 intrinsic  => "class",
		 type       => $implementationTypeName,
		 attributes => [ "intent(inout)" ],
		 variables  => [ "self" ]
	     },
	     {
		 intrinsic  => "double precision",
		 attributes => [ "intent(in   )", "dimension(:)" ],
		 variables  => [ "array" ]
	     }
	    ]
    };
    # Conditionally add "offset" and "count" variables if they will be needed.
    my @requiredVariables;
    push(@requiredVariables,"count")
	if
	(
	 exists($code::member->{'extends'})
	 ||
	 &Galacticus::Build::Components::Implementations::Utils::hasRealNonTrivialEvolvers($code::member)
	);
    push(@requiredVariables,"offset")
	if
	(
	 exists($code::member->{'extends'})
	 ||
	 &Galacticus::Build::Components::Implementations::Utils::hasRealEvolvers          ($code::member)
	);	   
    push(@{$function->{'variables'}},
	 {
	     intrinsic  => "integer",
	     variables  => \@requiredVariables
	 }
	)
	if ( scalar(@requiredVariables) > 0 );
    # Determine if the function arguments are unused.
    @code::unused = 
	(
	 exists($code::member->{'extends'})
	 ||
	 &Galacticus::Build::Components::Implementations::Utils::hasRealEvolvers          ($code::member)
	)
	?
	()
	:
	("self","array");
    # Build the function.
    $function->{'content'} = "";
    if ( scalar(@code::unused) > 0 ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
!GCC$ attributes unused :: {join(",",@unused)}
CODE
    }
    # Initialize offset if required.
    if ( grep {$_ eq "offset"} @requiredVariables ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
offset=1
CODE
    }    
    # If this component is an extension, call deserialization on the extended type.
    if ( exists($code::member->{'extends'}) ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
count=self%nodeComponent{ucfirst($code::member->{'extends'}->{'class'}).ucfirst($code::member->{'extends'}->{'name'})}%serializeCount   (     )
if (count > 0) then
 call self%nodeComponent{ucfirst($code::member->{'extends'}->{'class'}).ucfirst($code::member->{'extends'}->{'name'})}%deserializeValues(array)
 offset=offset+count
end if
CODE
    }
    # Iterate over non-virtual, evolvable properties.
    foreach $code::property ( &Galacticus::Build::Components::Implementations::Utils::listRealEvolvers($code::member) ) {
	if ( $code::property->{'data'}->{'rank'} == 0 ) {
	    if ( $code::property->{'data'}->{'type'} eq "double" ) {
		$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
self%{$property->{'name'}}Data=array(offset)
offset=offset+1
CODE
	    } else {
		$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
count=self%{$property->{'name'}}Data%serializeCount()
if (count > 0) call self%{$property->{'name'}}Data%deserialize(array(offset:offset+count-1))
offset=offset+count
CODE
	    }
	} else {
	    $function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
if (allocated(self%{$property->{'name'}}Data)) then
   count=size(self%{$property->{'name'}}Data)
   self%{$property->{'name'}}Data=reshape(array(offset:offset+count-1),shape(self%{$property->{'name'}}Data))
   offset=offset+count
end if
CODE
	}
    }
    # Insert a type-binding for this function into the treeNode type.
    push(
	@{$build->{'types'}->{$implementationTypeName}->{'boundFunctions'}},
	{
	    type        => "procedure", 
	    descriptor  => $function,
	    name        => "deserializeValues"
	}
	);	    
}

sub Implementation_ODE_Offsets {
    # Generate function to compute offsets into serialization arrays for component implementations.
    my $build     = shift();
    $code::class  = shift();
    $code::member = shift();
    my $implementationTypeName = "nodeComponent".ucfirst($code::class->{'name'}).ucfirst($code::member->{'name'});
    my $function =
    {
	type        => "void",
	name        => $implementationTypeName."SerializeOffsets",
	description => "Return a count of the serialization of a {\\normalfont \\ttfamily ".$code::member->{'name'}."} implementation of the {\\normalfont \\ttfamily ".$code::class->{'name'}."} component.",
	variables   =>
	    [
	     {
		 intrinsic  => "class",
		 type       => $implementationTypeName,
		 attributes => [ "intent(in   )" ],
		 variables  => [ "self" ]
	     },
	     {
		 intrinsic  => "integer",
		 attributes => [ "intent(inout)" ],
		 variables  => [ "count" ]
	     }
	    ]
    };
    # Determine if the function arguments are unused.
    @code::unused = ();
    push(@code::unused,"self")
	unless 
	(
	 exists($code::member->{'extends'})
	 ||
	 &Galacticus::Build::Components::Implementations::Utils::hasRealNonTrivialEvolvers($code::member)
	);
    push(@code::unused,"count")
	unless 
	(
	 exists($code::member->{'extends'})
	 ||
	 &Galacticus::Build::Components::Implementations::Utils::hasRealEvolvers           ($code::member)
	);
    # Build the function.
    $function->{'content'} = "";
    if ( scalar(@code::unused) > 0 ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
!GCC$ attributes unused :: {join(",",@unused)}
CODE
    }
    # If this component is an extension, compute offsets of the extended type.
    if ( exists($code::member->{'extends'}) ) {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');
call self%nodeComponent{ucfirst($code::member->{'extends'}->{'class'}).ucfirst($code::member->{'extends'}->{'name'})}%serializationOffsets(count)
CODE
    }
    # Iterate over non-virtual, evolvable properties.
    foreach $code::property ( &Galacticus::Build::Components::Implementations::Utils::listRealEvolvers($code::member) ) {
	# Set the offset for this property to the current count plus 1 (since we haven't yet updated the count. 
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
{&Galacticus::Build::Components::Utils::offsetName($class,$member,$property)}=count+1
CODE
	# Update the count by the size of this property.
	if ( $code::property->{'data'}->{'rank'} == 0 ) {
	    if ( $code::property->{'data'}->{'type'} eq "double" ) {
		$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
count=count+1
CODE
	    } else {
		$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
count=count+self%{$property->{'name'}}Data%serializeCount()
CODE
	    }
    } else {
	$function->{'content'} .= fill_in_string(<<'CODE', PACKAGE => 'code');	
if (allocated(self%{$property->{'name'}}Data)) count=count+size(self%{$property->{'name'}}Data)
CODE
    }
    }
    # Insert a type-binding for this function into the treeNode type.
    push(
	@{$build->{'types'}->{$implementationTypeName}->{'boundFunctions'}},
	{
	    type        => "procedure", 
	    descriptor  => $function,
	    name        => "serializationOffsets"
	}
	);
}

sub Implementation_ODE_Offset_Variables {
    # Generate variables which store offsets into the ODE solver arrays.
    my $build  = shift();
    my $class  = shift();
    my $member = shift();
    # Iterate over non-virtual, evolving properties.
    foreach my $property ( &Galacticus::Build::Components::Implementations::Utils::listRealEvolvers($member) ) {
	my $offsetName = &offsetName($class->{'name'}.$member->{'name'},$property->{'name'});
	push(
	    @{$build->{'variables'}},
	    {
		intrinsic  => "integer",
		ompPrivate => 1,
		variables  => [ $offsetName ]
	    }
	    );
    }
}

sub Implementation_ODE_Rate_Variables {
    # Generate variables which store ODE solver variable rates and scales.
    my $build = shift();
    push(
	@{$build->{'variables'}},
	{
	    intrinsic  => "integer",
	    ompPrivate => 1,
	    variables  => [ "nodeSerializationCount" ]
	},
	{
	    intrinsic  => "double precision",
	    attributes => [ "allocatable", "dimension(:)" ],
	    ompPrivate => 1,
	    variables  => [ "nodeScales", "nodeRates" ]
	}
	);
}

1;