# Contains a Perl module which implements processing of "function" directives in the Galacticus build system.

package Galacticus::Build::Function;
use strict;
use warnings;
use utf8;
use Cwd;
use lib exists($ENV{'GALACTICUS_ROOT_V094'}) ? $ENV{'GALACTICUS_ROOT_V094'}.'/perl' : cwd().'/perl';
use DateTime;
use Data::Dumper;
use Scalar::Util 'reftype';
use Sort::Topological qw(toposort);
use Galacticus::Build::Hooks;
use Galacticus::Build::Dependencies;
use Fortran::Utils;
use List::ExtraUtils;

# Insert hooks for our functions.
%Galacticus::Build::Hooks::moduleHooks = 
    (
     %Galacticus::Build::Hooks::moduleHooks,
     function        => {parse => \&Functions_Parse_Directive        , generate => \&Functions_Generate_Output        },
     functionModules => {parse => \&Functions_Modules_Parse_Directive, generate => \&Functions_Modules_Generate_Output}
    );

sub Functions_Parse_Directive {
    # Parse content for a "function" directive.
    my $buildData = shift;

    # Assert that we have a prefix, currentDocument and directive.
    die("Galacticus::Build::Function::Functions_Parse_Directive: no currentDocument present" )
	unless ( exists($buildData->{'currentDocument'}           ) );
    die("Galacticus::Build::Function::Functions_Parse_Directive: no name present"            )
	unless ( exists($buildData->{'currentDocument'}->{'name'} ) );

    # Store the name and associated file name
    my $directive = $buildData->{'directive'};
    my $className = $buildData->{'currentDocument'}->{'name'};
    my $fileName  = $buildData->{'currentFileName'};
    my $abstract  = "no";
    $abstract     = $buildData->{'currentDocument'}->{'abstract'}
        if ( exists($buildData->{'currentDocument'}->{'abstract'}) );
    my $defaultThreadPrivate = "default";
    $defaultThreadPrivate = $buildData->{'currentDocument'}->{'defaultThreadPrivate'}
        if ( exists($buildData->{'currentDocument'}->{'defaultThreadPrivate'}) );
    push(@{$buildData->{$directive}->{'classes'}},{name => $className, file => $fileName, description => $buildData->{'currentDocument'}->{'description'}, abstract => $abstract, defaultThreadPrivate => $defaultThreadPrivate});

}

sub Functions_Modules_Parse_Directive {
    # Parse content for a "functionModules" directive.
    my $buildData = shift;

    # Assert that we have a prefix, currentDocument and directive.
    die("Galacticus::Build::Function::Functions_Parse_Directive: no currentDocument present" )
	unless ( exists($buildData->{'currentDocument'}           ) );
    die("Galacticus::Build::Function::Functions_Parse_Directive: no name present"            )
	unless ( exists($buildData->{'currentDocument'}->{'name'} ) );

    # Store the name and associated file name
    my $directive = $buildData->{'directive'};
    my $className = $buildData->{'currentDocument'}->{'name'};
    my $fileName  = $buildData->{'currentFileName'};
    push(@{$buildData->{$directive}->{'functionModules'}},{name => $className, file => $fileName});
}

sub Functions_Generate_Output {
    # Generate output for a "function" directive.
    my $buildData = shift;

    # Assert that we have a file name and directive present.
    die("Galacticus::Build::Function::Functions_Parse_Directive: no fileName present"      )
	unless ( exists($buildData->{'fileName'}) );
    die("Galacticus::Build::Function::Functions_Parse_Directive: no directive present")
	unless ( exists($buildData->{'directive'}) );

    # Generate a timestamp.
    my $dt = DateTime->now->set_time_zone('local');
    (my $tz = $dt->format_cldr("ZZZ")) =~ s/(\d{2})(\d{2})/$1:$2/;
    my $now = $dt->ymd."T".$dt->hms.".".$dt->format_cldr("SSS").$tz;

    # Specify unit opening regexs.
    my %unitOpeners = (
	# Find module openings, avoiding module procedures.
	module             => { unitName => 1, regEx => "^\\s*module\\s+(?!procedure\\s)([a-z0-9_]+)" },
	# Find program openings.
	program            => { unitName => 1, regEx => "^\\s*program\\s+([a-z0-9_]+)" },
	# Find subroutine openings, allowing for pure, elemental and recursive subroutines.
	subroutine         => { unitName => 2, regEx => "^\\s*(pure\\s+|elemental\\s+|recursive\\s+)*\\s*subroutine\\s+([a-z0-9_]+)"},
	# Find function openings, allowing for pure, elemental and recursive functions, and different function types.
	function           => { unitName => 5, regEx => "^\\s*(pure\\s+|elemental\\s+|recursive\\s+)*\\s*(real|integer|double\\s+precision|character|logical)*\\s*(\\((kind|len)=[\\w\\d]*\\))*\\s*function\\s+([a-z0-9_]+)"},
	# Find interfaces.
	interface          => { unitName => 2, regEx => "^\\s*(abstract\\s+)??interface\\s+([a-z0-9_\\(\\)\\/\\+\\-\\*\\.=]*)"},
	# Find types.
	type               => { unitName => 3, regEx => "^\\s*type\\s*(,\\s*abstract\\s*|,\\s*public\\s*|,\\s*private\\s*|,\\s*extends\\s*\\([a-zA-Z0-9_]+\\)\\s*)*(::)??\\s*([a-z0-9_]+)\\s*\$"}
	);

    # Specify unit closing regexs.
    my %unitClosers = (
	module             => { unitName => 1, regEx => "^\\s*end\\s+module\\s+([a-z0-9_]+)" },
	program            => { unitName => 1, regEx => "^\\s*end\\s+program\\s+([a-z0-9_]+)" },
	subroutine         => { unitName => 1, regEx => "^\\s*end\\s+subroutine\\s+([a-z0-9_]+)"},
	function           => { unitName => 1, regEx => "^\\s*end\\s+function\\s+([a-z0-9_]+)"},
	interface          => { unitName => 1, regEx => "^\\s*end\\s+interface"},
	type               => { unitName => 1, regEx => "^\\s*end\\s+type\\s+([a-z0-9_]+)"}
	);

    # Specify regexs for intrinsic variable declarations.
    my %intrinsicDeclarations = (
	integer   => { intrinsic => "integer", type => 1, attributes => 2, variables => 3, regEx => "^\\s*(?i)integer(?-i)\\s*(\\(\\s*kind\\s*=\\s*[a-zA-Z0-9_]+\\s*\\))*([\\sa-zA-Z0-9_,:\\+\\-\\*\\/\\(\\)]*)??::\\s*([\\sa-zA-Z0-9_,:=>\\+\\-\\*\\/\\(\\)\\[\\]]+)\\s*\$" },
	real      => { intrinsic => "real", type => 1, attributes => 2, variables => 3, regEx => "^\\s*(?i)real(?-i)\\s*(\\(\\s*kind\\s*=\\s*[a-zA-Z0-9_]+\\s*\\))*([\\sa-zA-Z0-9_,:\\+\\-\\*\\/\\(\\)]*)??::\\s*([\\sa-zA-Z0-9\\._,:=>\\+\\-\\*\\/\\(\\)\\[\\]]+)\\s*\$" },
	double    => { intrinsic => "double precision", type => 1, attributes => 2, variables => 3, regEx => "^\\s*(?i)double\\s+precision(?-i)\\s*(\\(\\s*kind\\s*=\\s*[a-zA-Z0-9_]+\\s*\\))*([\\sa-zA-Z0-9_,:=\\+\\-\\*\\/\\(\\)]*)??::\\s*([\\sa-zA-Z0-9\\._,:=>\\+\\-\\*\\/\\(\\)\\[\\]]+)\\s*\$" },
	logical   => { intrinsic => "logical", type => 1, attributes => 2, variables => 3, regEx => "^\\s*(?i)logical(?-i)\\s*(\\(\\s*kind\\s*=\\s*[a-zA-Z0-9_]+\\s*\\))*([\\sa-zA-Z0-9_,:\\+\\-\\*\\/\\(\\)]*)??::\\s*([\\sa-zA-Z0-9_,:=>\\+\\-\\*\\/\\(\\)\\[\\]]+)\\s*\$" },
	character => { intrinsic => "character", type => 1, attributes => 4, variables => 5, regEx => "^\\s*(?i)character(?-i)\\s*(\\((\\s*(len|kind)\\s*=\\s*[a-zA-Z0-9_,\\+\\-\\*\\(\\)]+\\s*)+\\))*([\\sa-zA-Z0-9_,:\\+\\-\\*\\/\\(\\)]*)??::\\s*([\\sa-zA-Z0-9_,:=>\\+\\-\\*\\/\\(\\)\\[\\]]+)\\s*\$" },
	procedure => { intrinsic => "procedure", type => 1, attributes => 2, variables => 3, regEx => "^\\s*(?i)procedure(?-i)\\s*(\\(\\s*[a-zA-Z0-9_]*\\s*\\))*([\\sa-zA-Z0-9_,:\\+\\-\\*\\/\\(\\)]*)??::\\s*([\\sa-zA-Z0-9_,:=>\\+\\-\\*\\/\\(\\)]+)\\s*\$" },
	);

    # Extract the directive.
    my $directive = $buildData->{'directive'};

    # Find methods.
    my @methods;
    if ( exists($buildData->{'method'}) ) {
	if ( UNIVERSAL::isa($buildData->{'method'},"ARRAY") ) {
	    push(@methods,@{$buildData->{'method'}});
	} elsif ( UNIVERSAL::isa($buildData->{'method'},"HASH") ) {
	    push(@methods,$buildData->{'method'});
	} else {
	    push(@methods,  $buildData->{'method'} );
	}
    }

    # If the function is stateful, add methods to store and retrieve state.
    if ( exists($buildData->{'stateful'}) && $buildData->{'stateful'} eq "yes" ) {
	push(
	    @methods,
	    {
		name        => "stateStore",
		description => "Store the state of the object to file.",
		type        => "void",
		pass        => "yes",
		modules     => "FGSL",
		argument    => [ "integer, intent(in   ) :: stateFile", "type(fgsl_file), intent(in   ) :: fgslStateFile" ],
		code        => "!GCC\$ attributes unused :: self, stateFile, fgslStateFile\n"
	    },
	    {
		name        => "stateRestore",
		description => "Restore the state of the object to file.",
		type        => "void",
		pass        => "yes",
		modules     => "FGSL",
		argument    => [ "integer, intent(in   ) :: stateFile", "type(fgsl_file), intent(in   ) :: fgslStateFile" ],
		code        => "!GCC\$ attributes unused :: self, stateFile, fgslStateFile\n"
	    },
	    {
		name        => "stateSnapshot",
		description => "Snapshot the state of the object.",
		type        => "void",
		pass        => "yes",
		argument    => [ ],
		code        => "!GCC\$ attributes unused :: self\n"
	    }
	    );
    }

    # If the function requires calculation reset, add method to do so.
    if ( exists($buildData->{'calculationReset'}) && $buildData->{'calculationReset'} eq "yes" ) {
	push(
	    @methods,
	    {
		name        => "calculationReset",
		description => "Reset the calculation state of the object.",
		type        => "void",
		pass        => "yes",
		argument    => [ "type(treeNode), intent(inout), pointer :: thisNode" ],
		code        => "!GCC\$ attributes unused :: self, thisNode\n"
	    },
	    )
    }

    # Add "isFinalizable" and "makeIndestrucible" methods.
    push(
	@methods,
	{
	    name        => "isFinalizable",
	    description => "Return true if this object can be finalized.",
	    type        => "logical",
	    pass        => "yes",
	    code        => $directive."isFinalizable=.not.self%isIndestructible\n"
	},
	{
	    name        => "makeIndestructible",
	    description => "Make this object non-finalizable.",
	    type        => "void",
	    pass        => "yes",
	    code        => "self%isIndestructible=.true.\n"
	}
	);

    # Add "isDefault" method.
    push(
	@methods,
	{
	    name        => "isDefault",
	    description => "Return true if this object is the default for its class.",
	    type        => "logical",
	    pass        => "yes",
	    code        => $directive."isDefault=self%isDefaultValue\n"
	}
	);


    # Determine if any methods request that C-bindings be produced.
    my @methodsCBound;
    foreach ( @methods ) {
	push(@methodsCBound,$_)
	    if ( exists($_->{'bindC'}) && $_->{'bindC'} eq "true" );
    }

    # Create a list of non-abstract classes.
    my @nonAbstractClasses;
    foreach ( @{$buildData->{$directive}->{'classes'}}) {
	push(
	    @nonAbstractClasses,
	    $_
	    )
	    unless ( $_->{'abstract'} eq "yes" );
    }

    # Add a header.
    $buildData->{'content'}  = "! Generated automatically by Galacticus::Build::Function\n";
    $buildData->{'content'} .= "!  From: ".$buildData->{'fileName'}."\n";
    $buildData->{'content'} .= "!  Time: ".$now."\n\n";

    # Add public functions.
    $buildData->{'content'} .= "   public :: ".$directive.",".$directive."Class";
    $buildData->{'content'} .= ", ".$_->{'name'}
	foreach ( @nonAbstractClasses );
    $buildData->{'content'} .= ", ".$directive."DoStateStore, ".$directive."DoStateRetrieve, ".$directive."DoStateSnapshot"
	if ( exists($buildData->{'stateful'}) && $buildData->{'stateful'} eq "yes" );
   $buildData->{'content'} .= ", ".$directive."DoCalculationReset"
	if ( exists($buildData->{'calculationReset'}) && $buildData->{'calculationReset'} eq "yes" );
    $buildData->{'content'} .= "\n\n";

    # Add variable tracking module initialization status.
    $buildData->{'content'} .= "   logical, private :: moduleInitialized=.false.\n\n";

    # Generate the function object.
    $buildData->{'content'} .= "   type :: ".$directive."Class\n";
    $buildData->{'content'} .= "    private\n";
    $buildData->{'content'} .= "    logical :: isIndestructible=.false.\n";
    $buildData->{'content'} .= "    logical :: isDefaultValue  =.false.\n";
    foreach ( &List::ExtraUtils::as_array($buildData->{'data'}) ) {
	if ( reftype($_) ) {
	    $_->{'scope'} = "self"
		unless ( exists($_->{'scope'}) );
	    $buildData->{'content'} .= $_->{'content'}."\n"
	        if (  $_->{'scope'} eq "self" );
	} else {
	    $buildData->{'content'} .= $_."\n";
	}
    }
    $buildData->{'content'} .= "    contains\n";
    $buildData->{'content'} .= "    !@ <objectMethods>\n";
    $buildData->{'content'} .= "    !@   <object>".$directive."Class</object>\n";
    foreach my $method ( @methods ) {
	my $argumentList = "";
	my @arguments;
	if ( exists($method->{'argument'}) ) {
	    if ( UNIVERSAL::isa($method->{'argument'},"ARRAY") ) {
		push(@arguments,@{$method->{'argument'}});
	    } else {
		push(@arguments,  $method->{'argument'} );
	    }
	}
	my $separator = "";
	foreach my $argument ( @arguments ) {
	    foreach my $intrinsic ( keys(%intrinsicDeclarations) ) {
		my $declarator = $intrinsicDeclarations{$intrinsic};
		if ( my @matches = $argument =~ m/$declarator->{'regEx'}/ ) {
		    my $intrinsicName =                          $declarator->{'intrinsic' }    ;
		    my $type          =                 $matches[$declarator->{'type'      }-1] ;
		    my $attributeList =                 $matches[$declarator->{'attributes'}-1] ;
		    $attributeList =~ s/^\s*,?\s*//;
		    $attributeList =~ s/\s*$//;
		    my @attributes = &Fortran::Utils::Extract_Variables($attributeList, keepQualifiers => 1, removeSpaces => 1);
		    my @variables     = split(/\s*,\s*/,$matches[$declarator->{'variables' }-1]);
		    foreach my $variable ( @variables ) {
			$argumentList .= $separator."\\textcolor{red}{\\textless ".$intrinsicName;
			$argumentList .= "(".$type.")"
			    if ( defined($type) );
			$argumentList .= "\\textgreater} ".$variable;
			foreach my $attribute ( @attributes ) {
			    $argumentList .= "\\argin"
				if ( $attribute eq "intent(in)" );
			    $argumentList .= "\\argout"
				if ( $attribute eq "intent(out)" );
			    $argumentList .= "\\arginout"
				if ( $attribute eq "intent(inout)" );
			}
			$separator     = ",";
		    }
		}
	    }
	}
	$buildData->{'content'} .= "    !@   <objectMethod>\n";
	$buildData->{'content'} .= "    !@     <method>".$method->{'name'}."</method>\n";
	$buildData->{'content'} .= "    !@     <type>".$method->{'type'}."</type>\n";
	$buildData->{'content'} .= "    !@     <arguments>".$argumentList."</arguments>\n";
	$buildData->{'content'} .= "    !@     <description>".$method->{'description'}."</description>\n";
	$buildData->{'content'} .= "    !@   </objectMethod>\n";
    }
    $buildData->{'content'} .= "    !@ </objectMethods>\n";
    $buildData->{'content'} .= "    final :: ".$directive."Destructor\n";
    my $methodTable = Text::Table->new(
	{
	    is_sep => 1,
	    body   => "    procedure"
	},
	{
	    align  => "left"
	},
	{
	    is_sep => 1,
	    body   => " :: "
	},
	{
	    align  => "left"
	},
	{
	    is_sep => 1,
	    body   => " => ",
	},
	{
	    align  => "left"
	}
	);    

    foreach ( @methods ) {
	my $extension = "Null";
	$extension = ""
	    if ( exists($_->{'code'}) );
	$methodTable->add("",$_->{'name'},$directive.ucfirst($_->{'name'}).$extension);
    }
    $buildData->{'content'} .= $methodTable->table();
    $buildData->{'content'} .= "   end type ".$directive."Class\n\n";

    # Insert interface to class constructors.
    $buildData->{'content'} .= "   interface ".$directive."\n";
    $buildData->{'content'} .= "    module procedure ".$directive."ConstructorDefault\n";
    $buildData->{'content'} .= "    module procedure ".$directive."ConstructorNamed\n";
    $buildData->{'content'} .= "   end interface ".$directive."\n";

    # Scan implementation code to determine dependencies.
    my %dependencies;
    my %classes;
    foreach my $class ( @{$buildData->{$directive}->{'classes'}} ) {
	open(my $classFile,$class->{'file'});
	until ( eof($classFile) ) {
	    &Fortran::Utils::Get_Fortran_Line($classFile,my $rawLine, my $processedLine, my $bufferedComments);
	    if ( $processedLine =~ m/^\s*type\s*(,\s*abstract\s*|,\s*public\s*|,\s*private\s*|,\s*extends\s*\(([a-zA-Z0-9_]+)\)\s*)*(::)??\s*$directive([a-z0-9_]+)\s*$/i ) {
		my $extends = $2;
		my $type    = $directive.$4;
		$class  ->{'type'   } = $type;
		$class  ->{'extends'} = $extends;
		$classes  {$type    } = $class;
		push(@{$dependencies{$extends}},$type);
	    }
	}
    }
    my @unsortedClasses = keys(%classes);
    my @sortedClasses = toposort(sub { @{$dependencies{$_[0]} || []}; }, \@unsortedClasses );
    @{$buildData->{$directive}->{'classes'}} = map($classes{$_},@sortedClasses);

    # Insert pre-contains implementation code.
    foreach my $class ( @{$buildData->{$directive}->{'classes'}} ) {
	my $unitDepth = 0;
	open(my $classFile,$class->{'file'});
	until ( eof($classFile) ) {
	    &Fortran::Utils::Get_Fortran_Line($classFile,my $rawLine, my $processedLine, my $bufferedComments);
	    foreach my $unitType ( keys(%unitOpeners) ) {
		++$unitDepth
		    if ( $processedLine =~ m/$unitOpeners{$unitType}->{"regEx"}/i );
		--$unitDepth
		    if ( $processedLine =~ m/$unitClosers{$unitType}->{"regEx"}/i );
	    }
	    next
		if ( $processedLine =~ m/^\s*use\s+[a-zA-Z0-9_\s:\,]+/ );
	    last
		if ( $processedLine =~ m/^\s*contains\s*$/i && $unitDepth == 0 );
	    # Strip directive lines.
	    $rawLine =~ s/^(\s*)!#/$1!/;
	    $buildData->{'content'} .= $rawLine;
	}
	close($classFile);
    }

    # Add method name parameter.
    $buildData->{'content'} .= "   ! Method name parameter.\n";
    $buildData->{'content'} .= "   type(varying_string) :: ".$directive."Method\n\n";

    # Add default implementation.
    $buildData->{'defaultThreadPrivate'} = "no"
	unless ( exists($buildData->{'defaultThreadPrivate'}) );
    my $requireThreadPublicDefault  = 0;    
    foreach my $class ( @{$buildData->{$directive}->{'classes'}} ) {
	$class->{'defaultThreadPrivate'} = $buildData->{'defaultThreadPrivate'}
	    if ( $class->{'defaultThreadPrivate'} eq "default" );
	$requireThreadPublicDefault  = 1
	    if ( $class->{'defaultThreadPrivate'} eq "no"      );
    }
    $buildData->{'content'} .= "   ! Default ".$directive." object.\n";
    $buildData->{'content'} .= "   class(".$directive."Class), private , pointer :: ".$directive."Default       => null()\n";
    $buildData->{'content'} .= "   !\$omp threadprivate(".$directive."Default)\n";
    $buildData->{'content'} .= "   class(".$directive."Class), private , pointer :: ".$directive."PublicDefault => null()\n"
	if ( $requireThreadPublicDefault  == 1 );
    $buildData->{'content'} .= "\n";

    # If we need to generate C-bindings, insert a wrapper class to permit passing of polymorphic pointers between Fortran and C++.
    if ( @methodsCBound ) {
	$buildData->{'content'} .= "   type :: ".$directive."Wrapper\n";
	$buildData->{'content'} .= "     class(".$directive."Class), pointer :: wrappedObject\n";
	$buildData->{'content'} .= "   end type ".$directive."Wrapper\n\n";
    }

    # Insert any module-scope class content.
    foreach ( &List::ExtraUtils::as_array($buildData->{'data'}) ) {
	if ( reftype($_) ) {
	    if ( exists($_->{'scope'}) && $_->{'scope'} eq "module" ) {
		$buildData->{'content'} .= $_->{'content'}."\n";
		if ( exists($_->{'threadprivate'}) && $_->{'threadprivate'} eq "yes" && $_->{'content'} =~ m/::\s*(.*)$/ ) {
		    $buildData->{'content'} .= "   !\$omp threadprivate(".$1.")\n";
		}
	    }
	}
    }

    # Insert "contains" separator.
    $buildData->{'content'} .= "contains\n\n";

    # Create default constructor.
    $buildData->{'content'} .= "   function ".$directive."ConstructorDefault()\n";
    $buildData->{'content'} .= "      !% Return a pointer to the default {\\normalfont \\ttfamily ".$directive."} object.\n";
    $buildData->{'content'} .= "      implicit none\n";
    $buildData->{'content'} .= "      class(".$directive."Class), pointer :: ".$directive."ConstructorDefault\n\n";
    $buildData->{'content'} .= "      if (.not.associated(".$directive."Default)) call ".$directive."Initialize()\n";
    $buildData->{'content'} .= "      ".$directive."ConstructorDefault => ".$directive."Default\n";
    $buildData->{'content'} .= "      return\n";
    $buildData->{'content'} .= "   end function ".$directive."ConstructorDefault\n\n";

    # Create named constructor.
    $buildData->{'content'} .= "   function ".$directive."ConstructorNamed(typeName)\n";
    $buildData->{'content'} .= "      !% Return a pointer to a newly created {\\normalfont \\ttfamily ".$directive."} object of the specified type.\n";
    $buildData->{'content'} .= "      use ISO_Varying_String\n";
    $buildData->{'content'} .= "      use Galacticus_Error\n";
    $buildData->{'content'} .= "      implicit none\n";
    $buildData->{'content'} .= "      class(".$directive."Class), pointer :: ".$directive."ConstructorNamed\n\n";
    $buildData->{'content'} .= "      character(len=*), intent(in   ) :: typeName\n";
    $buildData->{'content'} .= "      type(varying_string) :: message\n\n";
    $buildData->{'content'} .= "      select case (trim(typeName))\n";
    foreach my $class ( @nonAbstractClasses ) {
	(my $name = $class->{'name'}) =~ s/^$directive//;
	$name = lcfirst($name)
	    unless ( $name =~ m/^[A-Z]{2,}/ );
	$buildData->{'content'} .= "     case ('".$name."')\n";
	$buildData->{'content'} .= "        allocate(".$class->{'name'}." :: ".$directive."ConstructorNamed)\n";
	$buildData->{'content'} .= "        select type (".$directive."ConstructorNamed)\n";
	$buildData->{'content'} .= "          type is (".$class->{'name'}.")\n";
	$buildData->{'content'} .= "            ".$directive."ConstructorNamed=".$class->{'name'}."()\n";
	$buildData->{'content'} .= "         end select\n";
    }
    $buildData->{'content'} .= "      case default\n";
    $buildData->{'content'} .= "         message='Unrecognized type \"'//trim(typeName)//'\" Available options are:'\n";
    my @classNames;
    push(@classNames,$_->{'name'})
	foreach ( @nonAbstractClasses );
    foreach ( sort(@classNames) ) {
	(my $name = $_) =~ s/^$directive//;
	$name = lcfirst($name)
	    unless ( $name =~ m/^[A-Z]{2,}/ );
	$buildData->{'content'} .= "        message=message//char(10)//'   -> ".$name."'\n";
    }
    $buildData->{'content'} .= "         call Galacticus_Error_Report('".$directive."ConstructorNamed',message)\n";
    $buildData->{'content'} .= "      end select\n";
    $buildData->{'content'} .= "      return\n";
    $buildData->{'content'} .= "   end function ".$directive."ConstructorNamed\n\n";

    # Create destructor.
    $buildData->{'content'} .= "   subroutine ".$directive."Destructor(self)\n";
    $buildData->{'content'} .= "      !%  {\\tt ".$directive."} object.\n";
    $buildData->{'content'} .= "      use Galacticus_Error\n";
    $buildData->{'content'} .= "      implicit none\n";
    $buildData->{'content'} .= "      type(".$directive."Class), intent(in   ) :: self\n\n";
    $buildData->{'content'} .= "      if (self%isIndestructible) call Galacticus_Error_Report('".$directive."Destructor','attempt to destroy indestructible object')\n";
    $buildData->{'content'} .= "      return\n";
    $buildData->{'content'} .= "   end subroutine ".$directive."Destructor\n\n";

    # Create initialization function.
    $buildData->{'content'} .= "   subroutine ".$directive."Initialize()\n";
    $buildData->{'content'} .= "      !% Initialize the default {\\normalfont \\ttfamily ".$directive."} object.\n";
    $buildData->{'content'} .= "      use ISO_Varying_String\n";
    $buildData->{'content'} .= "      use Input_Parameters\n";
    $buildData->{'content'} .= "      use Galacticus_Error\n";
    $buildData->{'content'} .= "      implicit none\n";
    $buildData->{'content'} .= "      type(varying_string) :: message\n\n";
    $buildData->{'content'} .= "      if (.not.moduleInitialized) then\n";
    $buildData->{'content'} .= "         !\$omp critical (".$directive."Initialization)\n";
    $buildData->{'content'} .= "         if (.not.moduleInitialized) then\n";
    $buildData->{'content'} .= "            !@ <inputParameter>\n";
    $buildData->{'content'} .= "            !@   <name>".$directive."Method</name>\n";
    $buildData->{'content'} .= "            !@   <defaultValue>".$buildData->{'default'}."</defaultValue>\n";
    $buildData->{'content'} .= "            !@   <attachedTo>module</attachedTo>\n";
    $buildData->{'content'} .= "            !@   <description>\n";
    $buildData->{'content'} .= "            !@     The method to be used for {\\normalfont \\ttfamily ".$directive."}.\n";
    $buildData->{'content'} .= "            !@   </description>\n";
    $buildData->{'content'} .= "            !@   <type>string</type>\n";
    $buildData->{'content'} .= "            !@   <cardinality>1</cardinality>\n";
    $buildData->{'content'} .= "            !@ </inputParameter>\n";
    $buildData->{'content'} .= "            call Get_Input_Parameter('".$directive."Method',".$directive."Method,defaultValue='".$buildData->{'default'}."')\n";
    $buildData->{'content'} .= "            moduleInitialized=.true.\n";
    $buildData->{'content'} .= "         end if\n";
    $buildData->{'content'} .= "         !\$omp end critical (".$directive."Initialization)\n";
    $buildData->{'content'} .= "      end if\n";
    $buildData->{'content'} .= "      select case (char(".$directive."Method))\n";
    foreach my $class ( @nonAbstractClasses ) {
	(my $name = $class->{'name'}) =~ s/^$directive//;
	$name = lcfirst($name)
	    unless ( $name =~ m/^[A-Z]{2,}/ );
	$buildData->{'content'} .= "     case ('".$name."')\n";
	if ( $class->{'defaultThreadPrivate'} eq "yes" ) {
	    $buildData->{'content'} .= "        allocate(".$class->{'name'}." :: ".$directive."Default)\n";
	    $buildData->{'content'} .= "        select type (".$directive."Default)\n";
	    $buildData->{'content'} .= "          type is (".$class->{'name'}.")\n";
	    $buildData->{'content'} .= "            ".$directive."Default=".$class->{'name'}."()\n";
	    $buildData->{'content'} .= "         end select\n";
	} else {
	    $buildData->{'content'} .= "        if (.not.associated(".$directive."PublicDefault)) then\n";
	    $buildData->{'content'} .= "           allocate(".$class->{'name'}." :: ".$directive."PublicDefault)\n";
	    $buildData->{'content'} .= "           select type (".$directive."PublicDefault)\n";
	    $buildData->{'content'} .= "           type is (".$class->{'name'}.")\n";
	    $buildData->{'content'} .= "             ".$directive."PublicDefault=".$class->{'name'}."()\n";
	    $buildData->{'content'} .= "           end select\n";
	    $buildData->{'content'} .= "        end if\n";
	    $buildData->{'content'} .= "         ".$directive."Default => ".$directive."PublicDefault\n";
	}
    }
    $buildData->{'content'} .= "      case default\n";
    $buildData->{'content'} .= "         message='Unrecognized option for [".$directive."Method](='//".$directive."Method//'). Available options are:'\n";
    foreach ( sort(@classNames) ) {
	(my $name = $_) =~ s/^$directive//;
	$name = lcfirst($name)
	    unless ( $name =~ m/^[A-Z]{2,}/ );
	$buildData->{'content'} .= "        message=message//char(10)//'   -> ".$name."'\n";
    }
    $buildData->{'content'} .= "         call Galacticus_Error_Report('".$directive."Initialize',message)\n";
    $buildData->{'content'} .= "      end select\n";
    $buildData->{'content'} .= "      ".$directive."Default%isIndestructible=.true.\n";
    $buildData->{'content'} .= "      ".$directive."Default%isDefaultValue  =.true.\n";
    $buildData->{'content'} .= "      return\n";
    $buildData->{'content'} .= "   end subroutine ".$directive."Initialize\n\n";

    # Create global state store/restore functions.
    if ( exists($buildData->{'stateful'}) && $buildData->{'stateful'} eq "yes" ) {
	$buildData->{'content'} .= "  !# <galacticusStateSnapshotTask>\n";
	$buildData->{'content'} .= "  !#  <unitName>".$directive."DoStateSnapshot</unitName>\n";
	$buildData->{'content'} .= "  !# </galacticusStateSnapshotTask>\n";
	$buildData->{'content'} .= "  subroutine ".$directive."DoStateSnapshot()\n";
	$buildData->{'content'} .= "    !% Snapshot the state.\n";
	$buildData->{'content'} .= "    implicit none\n";
	$buildData->{'content'} .= "    class  (".$directive."Class), pointer :: default\n\n";
	$buildData->{'content'} .= "    default => ".$directive."()\n";
	$buildData->{'content'} .= "    call default%stateSnapshot()\n";
	$buildData->{'content'} .= "    return\n";
	$buildData->{'content'} .= "  end subroutine ".$directive."DoStateSnapshot\n\n";
	$buildData->{'content'} .= "  !# <galacticusStateStoreTask>\n";
	$buildData->{'content'} .= "  !#  <unitName>".$directive."DoStateStore</unitName>\n";
	$buildData->{'content'} .= "  !# </galacticusStateStoreTask>\n";
	$buildData->{'content'} .= "  subroutine ".$directive."DoStateStore(stateFile,fgslStateFile)\n";
	$buildData->{'content'} .= "    !% Store the state to file.\n";
	$buildData->{'content'} .= "    implicit none\n";
	$buildData->{'content'} .= "    integer           , intent(in   ) :: stateFile\n";
	$buildData->{'content'} .= "    type   (fgsl_file), intent(in   ) :: fgslStateFile\n";
	$buildData->{'content'} .= "    class  (".$directive."Class), pointer :: default\n\n";
	$buildData->{'content'} .= "    default => ".$directive."()\n";
	$buildData->{'content'} .= "    call default%stateStore(stateFile,fgslStateFile)\n";
	$buildData->{'content'} .= "    return\n";
	$buildData->{'content'} .= "  end subroutine ".$directive."DoStateStore\n\n";
	$buildData->{'content'} .= "  !# <galacticusStateRetrieveTask>\n";
	$buildData->{'content'} .= "  !#  <unitName>".$directive."DoStateRetrieve</unitName>\n";
	$buildData->{'content'} .= "  !# </galacticusStateRetrieveTask>\n";
	$buildData->{'content'} .= "  subroutine ".$directive."DoStateRetrieve(stateFile,fgslStateFile)\n";
	$buildData->{'content'} .= "    !% Retrieve the state from file.\n";
	$buildData->{'content'} .= "    implicit none\n";
	$buildData->{'content'} .= "    integer           , intent(in   ) :: stateFile\n";
	$buildData->{'content'} .= "    type   (fgsl_file), intent(in   ) :: fgslStateFile\n";
	$buildData->{'content'} .= "    class  (".$directive."Class), pointer :: default\n\n";
	$buildData->{'content'} .= "    default => ".$directive."()\n";
	$buildData->{'content'} .= "    call default%stateRestore(stateFile,fgslStateFile)\n";
	$buildData->{'content'} .= "    return\n";
	$buildData->{'content'} .= "  end subroutine ".$directive."DoStateRetrieve\n\n";
    }

    # Create global calculation reset function.
    if ( exists($buildData->{'calculationReset'}) && $buildData->{'calculationReset'} eq "yes" ) {
	$buildData->{'content'} .= "  !# <calculationResetTask>\n";
	$buildData->{'content'} .= "  !#  <unitName>".$directive."DoCalculationReset</unitName>\n";
	$buildData->{'content'} .= "  !# </calculationResetTask>\n";
	$buildData->{'content'} .= "  subroutine ".$directive."DoCalculationReset(thisNode)\n";
	$buildData->{'content'} .= "    !% Store the state to file.\n";
	$buildData->{'content'} .= "    implicit none\n";
	$buildData->{'content'} .= "    type (treeNode), pointer, intent(inout) :: thisNode\n";
	$buildData->{'content'} .= "    class(".$directive."Class), pointer :: default\n\n";
	$buildData->{'content'} .= "    default => ".$directive."()\n";
	$buildData->{'content'} .= "    call default%calculationReset(thisNode)\n";
	$buildData->{'content'} .= "    return\n";
	$buildData->{'content'} .= "  end subroutine ".$directive."DoCalculationReset\n\n";
    }

    # Create functions.
    foreach my $method ( @methods ) {
	# Insert arguments.
	my @arguments;
	if ( exists($method->{'argument'}) ) {
	    if ( UNIVERSAL::isa($method->{'argument'},"ARRAY") ) {
		push(@arguments,@{$method->{'argument'}});
	    } else {
		push(@arguments,  $method->{'argument'} );
	    }
	}
	my $argumentList = "";
	my $argumentCode = "      class(".$directive."Class), intent(inout) :: self\n";
	my $separator = "";
	foreach my $argument ( @arguments ) {
	    (my $variables = $argument) =~ s/^.*::\s*(.*?)\s*$/$1/;
	    $argumentList .= $separator.$variables;
	    $argumentCode .= "      ".$argument."\n";
	    $separator     = ",";
	}
	my $type;
	my $category;
	my $self;
	my $extension = "Null";
	$extension = ""
	    if ( exists($method->{'code'}) );
	if ( $method->{'type'} eq "void" ) {
	    $category = "subroutine";
	    $type     = "";
	    $self     = "";
	} elsif ( $method->{'type'} =~ m/^class/ ) {
	    $category = "function";
	    $type     = "";
	    $self     = "      ".$method->{'type'}.", pointer :: ".$directive.ucfirst($method->{'name'}).$extension."\n";
	} elsif ( $method->{'type'} =~ m/^type/ ) {
	    $category = "function";
	    $type     = "";
	    $self     = "      ".$method->{'type'}." :: ".$directive.ucfirst($method->{'name'}).$extension."\n";
	} else {
	    $category = "function";
	    $type     = $method->{'type'}." ";
	    $self     = "";
	}
	$buildData->{'content'} .= "   ".$type.$category." ".$directive.ucfirst($method->{'name'}).$extension."(self";
	$buildData->{'content'} .= ",".$argumentList
	    unless ( $argumentList eq "" );
	$buildData->{'content'} .= ")\n";
	$buildData->{'content'} .= "      !% ".$method->{'description'}."\n";
	if ( exists($method->{'code'}) ) {
	    if ( exists($method->{'modules'}) ) {
		$buildData->{'content'} .= "      use ".$_."\n"
		    foreach ( split(/\s+/,$method->{'modules'}) );
	    }
	} else {
	    $buildData->{'content'} .= "      use Galacticus_Error\n";
	}
	$buildData->{'content'} .= "      implicit none\n";
	$buildData->{'content'} .= $self;
	$buildData->{'content'} .= $argumentCode;
	if ( exists($method->{'code'}) ) {
	    my $code = "      ".$method->{'code'};
	    $code =~ s/\n/\n      /g;
	    $buildData->{'content'} .= $code."\n";
	} else {
	    $buildData->{'content'} .= "      !GCC\$ attributes unused :: self";
	    $buildData->{'content'} .= ",".$argumentList
		unless ( $argumentList eq "" );
	    $buildData->{'content'} .= "\n";
	    if ( $category eq "function" ) {
		if ( $method->{'type'} =~ m/^class/ ) {
		    $buildData->{'content'} .= "      ".$directive.ucfirst($method->{'name'}).$extension." => null()\n";
		} else {
		    if ( $type eq "double precision " ) {
			$buildData->{'content'} .= "      ".$directive.ucfirst($method->{'name'}).$extension."=0.0d0\n";	
		    } elsif ( $type eq "logical " ) {
			$buildData->{'content'} .= "      ".$directive.ucfirst($method->{'name'}).$extension."=.false.\n";	
		    } elsif ( $type =~ m/^integer/ ) {
			$buildData->{'content'} .= "      ".$directive.ucfirst($method->{'name'}).$extension."=0\n";	
		    } elsif ( $method->{'type'} =~ m/^type\((.*)\)$/ ) {
			$buildData->{'content'} .= "      ".$directive.ucfirst($method->{'name'}).$extension."=zero".ucfirst($1)."\n";
		    }
		}
	    }
	    $buildData->{'content'} .= "      call Galacticus_Error_Report('".$method->{'name'}."Null','this is a null method - initialize the ".$directive." object before use')\n";
	}
	$buildData->{'content'} .= "      return\n";
	$buildData->{'content'} .= "   end ".$category." ".$directive.ucfirst($method->{'name'}).$extension."\n\n";
    }
    # Generate C-bindings if required.
    if ( @methodsCBound ) {
	# C-bound default constructor. Here, we use a wrapper object which contains a pointer to the default polymorphic Fortran
	# object. This wrapper is then passed back to the calling C++ function so that it can be stored in the appropriate C++
	# class.
	$buildData->{'content'} .= "   function ".$directive."_C() bind(c,name='".$directive."')\n";
	$buildData->{'content'} .= "     implicit none\n";
	$buildData->{'content'} .= "     type(c_ptr) :: ".$directive."_C\n";
	$buildData->{'content'} .= "     type(".$directive."Wrapper), pointer :: wrapper\n";
	$buildData->{'content'} .= "      if (.not.associated(".$directive."Default)) call ".$directive."Initialize()\n";
	$buildData->{'content'} .= "       allocate(wrapper)\n";
	$buildData->{'content'} .= "       wrapper%wrappedObject => ".$directive."Default\n";
	$buildData->{'content'} .= "       ".$directive."_C=c_loc(wrapper)\n";
	$buildData->{'content'} .= "     return\n";
	$buildData->{'content'} .= "   end function ".$directive."_C\n\n";
	# C-bound destructor. We simply deallocate the wrapper object, letting the associated finalizor clean up the Fortran
	# object.
	$buildData->{'content'} .= "   subroutine ".$directive."Destructor_C(wrapperC) bind(c,name='".$directive."Destructor')\n";
	$buildData->{'content'} .= "     implicit none\n";
	$buildData->{'content'} .= "     type(c_ptr), intent(in   ), value :: wrapperC\n";
	$buildData->{'content'} .= "     type(".$directive."Wrapper), pointer :: wrapper\n\n";
	$buildData->{'content'} .= "     call c_f_pointer(wrapperC,wrapper)\n";
	$buildData->{'content'} .= "     deallocate(wrapper)\n";
	$buildData->{'content'} .= "     return\n";
	$buildData->{'content'} .= "   end subroutine ".$directive."Destructor_C\n\n";
	# Generate method functions.
	foreach ( @methodsCBound ) {
	    my @arguments;
	    if ( exists($_->{'argument'}) ) {
		if ( UNIVERSAL::isa($_->{'argument'},"ARRAY") ) {
		    push(@arguments,@{$_->{'argument'}});
		} else {
		    push(@arguments,  $_->{'argument'} );
		}
	    }
	    my $separator    = "";
	    my $argumentList = "";
	    foreach my $argument ( @arguments ) {
		foreach my $intrinsic ( keys(%intrinsicDeclarations) ) {
		    my $declarator = $intrinsicDeclarations{$intrinsic};
		    if ( my @matches = $argument =~ m/$declarator->{'regEx'}/ ) {
			my $intrinsicName =                          $declarator->{'intrinsic' }    ;
			my $type          =                 $matches[$declarator->{'type'      }-1] ;
			my $attributeList =                 $matches[$declarator->{'attributes'}-1] ;
			$attributeList =~ s/^\s*,?\s*//;
			$attributeList =~ s/\s*$//;
			my @attributes = &Fortran::Utils::Extract_Variables($attributeList, keepQualifiers => 1, removeSpaces => 1);
			foreach my $attribute ( @attributes ) {
			    die("Galacticus::Build::Functions::Functions_Generate_Output:  attribute not supported for C++-binding")
				unless ( $attribute eq "intent(in)" );
			}
			my @variables     = split(/\s*,\s*/,$matches[$declarator->{'variables' }-1]);
			die("Galacticus::Build::Functions::Functions_Generate_Output: non-standard kinds are not supported for C++-binding")
			    if ( defined($type) );
			$argumentList .= $separator.join(",",@variables);
			$separator     = ",";
		    }
		}
	    }
	    $buildData->{'content'} .= "  double precision function ".$_->{'name'}."_C(";
	    $buildData->{'content'} .= "wrapperC".$separator
		if ( $_->{'pass'} eq "yes" );
	    $buildData->{'content'} .= $argumentList.") bind(c,name='".$_->{'name'}."_C')\n";
	    $buildData->{'content'} .= "     implicit none\n";
	    $buildData->{'content'} .= "     type(c_ptr), intent(in   ), value :: wrapperC\n";
	    foreach my $argument( @arguments ) {
		(my $argumentInteroperable = $argument) =~ s/(\s*::)/, value$1/;
		$buildData->{'content'} .= "     ".$argumentInteroperable."\n"
	    }
	    $buildData->{'content'} .= "     type(".$directive."Wrapper), pointer :: wrapper\n";
	    $buildData->{'content'} .= "     call c_f_pointer(wrapperC,wrapper)\n";
	    $buildData->{'content'} .= "     ".$_->{'name'}."_C=wrapper\%wrappedObject\%".$_->{'name'}."(".$argumentList.")\n";
	    $buildData->{'content'} .= "     return\n";
	    $buildData->{'content'} .= "   end function ".$_->{'name'}."_C\n\n";
	}
    }
    # Check if debugging is required.
    my $debug = 0;
    if ( exists($ENV{'GALACTICUS_FCFLAGS'}) ) {
	$debug = 1
	    if ( grep {$_ eq "-DDEBUGHDF5"} split(" ",$ENV{'GALACTICUS_FCFLAGS'}) );
    }
    # Insert post-contains implementation code.
    foreach my $class ( @{$buildData->{$directive}->{'classes'}} ) {
	my $unitDepth     = 0;
	my $containsFound = 0;
	open(my $classFile,$class->{'file'});
	until ( eof($classFile) ) {
	    &Fortran::Utils::Get_Fortran_Line($classFile,my $rawLine, my $processedLine, my $bufferedComments);
	    foreach my $unitType ( keys(%unitOpeners) ) {
		++$unitDepth
		    if ( $processedLine =~ m/$unitOpeners{$unitType}->{"regEx"}/i );
		--$unitDepth
		    if ( $processedLine =~ m/$unitClosers{$unitType}->{"regEx"}/i );
	    }
	    # Add HDF5 debug code.
	    if ( $debug ) {
		$rawLine .= "call IO_HDF5_Start_Critical()\n"
		    if ( $rawLine =~ m /^\s*\!\$omp\s+critical\s*\(HDF5_Access\)\s*$/ );
		$rawLine  = "call IO_HDF5_End_Critical()\n".$rawLine
		    if ( $rawLine =~ m /^\s*\!\$omp\s+end\s+critical\s*\(HDF5_Access\)\s*$/ );
	    }
	    # Strip directive lines.
	    $rawLine =~ s/^(\s*)!#/$1!/;
	    $buildData->{'content'} .= $rawLine
		if ( $containsFound == 1 );
	    $containsFound = 1
		if ( $processedLine =~ m/^\s*contains\s*$/i && $unitDepth == 0 );
	}
	close($classFile);
    }
    # Generate C-bindings here if required.
    if ( @methodsCBound ){
	# Iterate over methods and generate the necessary code.
	my $externCode;
	my $classCode;
	my $methodCode;
	foreach ( @methodsCBound ) {
	    my $type;
	    if ( $_->{'type'} eq "double precision" ) {
		$type = "double";
	    } else {
		die("Galacticus::Build::Functions::Functions_Generate_Output: type unsupported for C++-binding");
	    }
	    my $separator     = "";
	    my $fullSeparator = "";
	    my $argumentList  = "";
	    my $variableList  = "";
	    my $fullList      = "";
	    if ( $_->{'pass'} eq "yes" ) {
		$argumentList .= $separator."void*";
		$variableList .= $separator."fortranSelf";
		$separator     = ",";
	    }
	    my @arguments;
	    if ( exists($_->{'argument'}) ) {
		if ( UNIVERSAL::isa($_->{'argument'},"ARRAY") ) {
		    push(@arguments,@{$_->{'argument'}});
		} else {
		    push(@arguments,  $_->{'argument'} );
		}
	    }
	    foreach my $argument ( @arguments ) {
		foreach my $intrinsic ( keys(%intrinsicDeclarations) ) {
		    my $declarator = $intrinsicDeclarations{$intrinsic};
		    if ( my @matches = $argument =~ m/$declarator->{'regEx'}/ ) {
			my $intrinsicName =                          $declarator->{'intrinsic' }    ;
			my $type          =                 $matches[$declarator->{'type'      }-1] ;
			my $attributeList =                 $matches[$declarator->{'attributes'}-1] ;
			$attributeList =~ s/^\s*,?\s*//;
			$attributeList =~ s/\s*$//;
			my @attributes = &Fortran::Utils::Extract_Variables($attributeList, keepQualifiers => 1, removeSpaces => 1);
			foreach my $attribute ( @attributes ) {
			    die("Galacticus::Build::Functions::Functions_Generate_Output:  attribute not supported for C++-binding")
				unless ( $attribute eq "intent(in)" );
			}
			my @variables     = split(/\s*,\s*/,$matches[$declarator->{'variables' }-1]);
			die("Galacticus::Build::Functions::Functions_Generate_Output: non-standard kinds are not supported for C++-binding")
			    if ( defined($type) );
			my $cType;
			if ( $intrinsicName eq "double precision" ) {
			    $cType = "double";
			} else {
			    die("Galacticus::Build::Functions::Functions_Generate_Output: type not supported for C++-binding");
			}
			$argumentList .=     $separator.join(",",map($cType       ,1..scalar(@variables)));
			$variableList .=     $separator.join(",",                            @variables  );
			$fullList     .= $fullSeparator.join(",",map($cType." ".$_,          @variables ));
			$separator     = ",";
			$fullSeparator = ",";
		    }
		}
	    }
	    # Build extern and class declarations.
	    $externCode .= " ".$type." ".$_->{'name'}."_C(".$argumentList.");\n";
	    my $classArgumentList = $argumentList;
	    $classArgumentList =~ s/^void\*,?//
		if ( $_->{'pass'} eq "yes" );
	    $classCode  .= " ".$type." ".$_->{'name'}."(".$classArgumentList.");\n";
	    # Build the method.
	    $methodCode .= $type." ".$directive."Class::".$_->{'name'}." (".$fullList.") {\n";
	    $methodCode .= " return ".$_->{'name'}."_C(".$variableList.");\n";
	    $methodCode .= "}\n\n";
	}
	my $cBindings;
	$cBindings  = "// Generated automatically by Galacticus::Build::Function\n";
	$cBindings .= "//  From: ".$buildData->{'fileName'}."\n";
	$cBindings .= "//  Time: ".$now."\n\n";
	# Generate external linkage for creator, destructor, and method functions.
	$cBindings .= "extern \"C\"\n";
	$cBindings .= "{\n";
	$cBindings .= " void* ".$directive."();\n";
	$cBindings .= " void ".$directive."Destructor(void*);\n";
	$cBindings .= $externCode;
	$cBindings .= "}\n\n";
	# Create a class for this object.
	$cBindings .= "class ".$directive."Class {\n";
	$cBindings .= "  void *fortranSelf;\n";
	$cBindings .= " public:\n";
	$cBindings .= " ".$directive."Class ();\n";
	$cBindings .= " ~".$directive."Class ();\n";
	$cBindings .= $classCode;
	$cBindings .= "};\n\n";	
	# Create a creator.
	$cBindings .= $directive."Class::".$directive."Class () {\n";
	$cBindings .= " fortranSelf=".$directive."();\n";
	$cBindings .= "};\n\n";
	# Create a destructor.
	$cBindings .= $directive."Class::~".$directive."Class () {\n";
	$cBindings .= " ".$directive."Destructor(fortranSelf);\n";
	$cBindings .= "};\n\n";
	# Create methods.
	$cBindings .= $methodCode;
	open(cHndl,">".$ENV{'BUILDPATH'}."/".$directive.".h");
	print cHndl $cBindings;
	close(cHndl);
    }
    # Generate documentation.
    my $documentation = "\\subsubsection{".$buildData->{'descriptiveName'}."}\\label{sec:methods".ucfirst($directive)."}\n\n";
    $documentation   .= "Additional implementations for ".lc($buildData->{'descriptiveName'})." are added using the {\\normalfont \\ttfamily ".$directive."} class.\n";
    $documentation   .= "The implementation should be placed in a file containing the directive:\n";
    $documentation   .= "\\begin{verbatim}\n";
    $documentation   .= "!# <".$directive." name=\"".$directive."MyImplementation\">\n";
    $documentation   .= "!# <description>A short description of the implementation.</description>\n";
    $documentation   .= "!# </".$directive.">\n";
    $documentation   .= "\\end{verbatim}\n";
    $documentation   .= "where {\\normalfont \\ttfamily MyImplementation} is an appropriate name for the implemention. This file should be treated as a regular Fortran module, but without the initial {\\normalfont \\ttfamily module} and final {\\normalfont \\ttfamily end module} lines. That is, it may contain {\\normalfont \\ttfamily use} statements and variable declarations prior to the {\\normalfont \\ttfamily contains} line, and should contain all functions required by the implementation after that line. Function names should begin with {\\normalfont \\ttfamily ".&LaTeX_Breakable($directive."MyImplementation")."}. The file \\emph{must} define a type that extends the {\\normalfont \\ttfamily ".$directive."Class} class (or extends another type which is itself an extension of the {\\normalfont \\ttfamily ".$directive."Class} class), containing any data needed by the implementation along with type-bound functions required by the implementation. The following type-bound functions are required (unless inherited from the parent type):\n";
    $documentation   .= "\\begin{description}\n";
    # Create functions.
    foreach my $method ( @methods ) {
	$documentation   .= "\\item[{\\normalfont \\ttfamily ".$method->{'name'}."}] ".$method->{'description'};
	if ( exists($method->{'code'}) ) {
	    $documentation .= " A default implementation exists. If overridden the following interface must be used:\n";
	} else {
	    $documentation .= " Must have the following interface:\n";
	}
	$documentation   .= "\\begin{lstlisting}[language=Fortran,basicstyle=\\small\\ttfamily,escapechar=@,breaklines,prebreak=\\&,postbreak=\\&\\space\\space,columns=flexible,keepspaces=true,breakautoindent=true,breakindent=10pt]\n";
	# Insert arguments.
	my @arguments;
	if ( exists($method->{'argument'}) ) {
	    if ( UNIVERSAL::isa($method->{'argument'},"ARRAY") ) {
		push(@arguments,@{$method->{'argument'}});
	    } else {
		push(@arguments,  $method->{'argument'} );
	    }
	}
	unshift(@arguments,"class(".$directive."Class), intent(inout) :: self");
	my $argumentList = "";
	my $separator    = "";
	my @argumentDefinitions;
	foreach my $argument ( @arguments ) {
	    if ( $argument =~ $Fortran::Utils::variableDeclarationRegEx ) {
		my $intrinsic     = $1;
		my $type          = $2;
		my $attributeList = $3;
		my $variableList  = $4;
		my @variables  = &Fortran::Utils::Extract_Variables($variableList,keepQualifiers => 1,lowerCase => 0);
		my $declaration =
		{
		    intrinsic  => $intrinsic,
		    attributes => $attributeList,
		    variables  => \@variables
		}; 
		if ( defined($type) ) {
		    $type =~ s/\((.*)\)/$1/;
		    $declaration->{'type'} = $type;
		}
		if ( defined($attributeList) ) {
		    $attributeList =~ s/^\s*,\s*//;
		    my @attributes = &Fortran::Utils::Extract_Variables($attributeList,keepQualifiers => 1);
		    $declaration->{'attributes'} = \@attributes;
		}
		push(@argumentDefinitions,$declaration);
	    } else {
		print "Argument does not match expected pattern:\n\t".$argument."\n";
		die("Functions_Generate_Output: argument parse error");
	    }
	    (my $variables = $argument) =~ s/^.*::\s*(.*?)\s*$/$1/;
	    $argumentList .= $separator.$variables;
	    $separator     = ",";
	}
	my $type;
	my $category;
	if ( $method->{'type'} eq "void" ) {
	    $category = "subroutine";
	    $type     = "";
	} else {
	    $category = "function";
	    $type     = $method->{'type'}." ";
	}
	$documentation .= "   ".$type.$category." myImplementation".ucfirst($method->{'name'})."(";
	$documentation .= $argumentList
	    unless ( $argumentList eq "" );
	$documentation .= ")\n";
	$documentation .= &Fortran::Utils::Format_Variable_Defintions(\@argumentDefinitions);
	$documentation .= "   end ".$type.$category." myImplementation".ucfirst($method->{'name'})."\n";
	$documentation .= "\\end{lstlisting}\n\n";
    }
    $documentation   .= "\\end{description}\n\n";

    $documentation   .= "Existing implementations are:\n";
    $documentation   .= "\\begin{description}\n";
    foreach my $class ( @{$buildData->{$directive}->{'classes'}} ) {
	$documentation   .= "\\item[{\\normalfont \\ttfamily ".$class->{'name'}."}] ".$class->{'description'};
	$documentation   .= " \\iflabelexists{phys:".$directive.":".$class->{'name'}."}{See \\S\\ref{phys:".$directive.":".$class->{'name'}."}.}{}\n";
    }
    $documentation   .= "\\end{description}\n\n";
	
    system("mkdir -p doc/methods");
    open(my $docHndl,">doc/methods/".$directive.".tex");
    print $docHndl $documentation;
    close($docHndl);
}

sub Functions_Modules_Generate_Output {
    # Generate output for a "functionModules" directive.
    my $buildData = shift;

    # Assert that we have a file name and directive present.
    die("Galacticus::Build::Function::Functions_Parse_Directive: no fileName present"      )
	unless ( exists($buildData->{'fileName'}) );
    die("Galacticus::Build::Function::Functions_Parse_Directive: no directive present")
	unless ( exists($buildData->{'directive'}) );

    # Generate a timestamp.
    my $dt = DateTime->now->set_time_zone('local');
    (my $tz = $dt->format_cldr("ZZZ")) =~ s/(\d{2})(\d{2})/$1:$2/;
    my $now = $dt->ymd."T".$dt->hms.".".$dt->format_cldr("SSS").$tz;

    # Extract the directive.
    my $directive = $buildData->{'directive'};

    # Add a header.
    $buildData->{'content'}  = "! Generated automatically by Galacticus::Build::Function\n";
    $buildData->{'content'} .= "!  From: ".$buildData->{'fileName'}."\n";
    $buildData->{'content'} .= "!  Time: ".$now."\n\n";

    # Insert module use statements from implementation code.
    my %modules;
    foreach my $class ( @{$buildData->{$directive}->{'functionModules'}} ) {
	my $unitDepth = 0;
	open(my $classFile,$class->{'file'});
	until ( eof($classFile) ) {
	    &Fortran::Utils::Get_Fortran_Line($classFile,my $rawLine, my $processedLine, my $bufferedComments);
	    if ( $processedLine =~ m/^\s*use\s+([a-zA-Z0-9_\s:\,]+)/ ){
		$modules{$1} = $1;
	    }
	    last
		if ( $processedLine =~ m/^\s*contains\s*$/i && $unitDepth == 0 );
	}
	close($classFile);
    }

    # Generate the code.
    $buildData->{'content'} .= "use ".$_
	foreach ( sort(keys(%modules)) );
}

sub LaTeX_Breakable {
    my $text = shift;
    $text =~ s/([a-z])([A-Z])/$1\\-$2/g;
    return $text;
}

1;
