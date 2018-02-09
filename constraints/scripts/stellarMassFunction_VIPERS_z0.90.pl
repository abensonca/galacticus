#!/usr/bin/env perl
use strict;
use warnings;
use Cwd;
use lib exists($ENV{'GALACTICUS_ROOT_V094'}) ? $ENV{'GALACTICUS_ROOT_V094'}.'/perl' : cwd().'/perl';
use Galacticus::Path;
use PDL;
use PDL::IO::HDF5;
use Galacticus::Options;
use Galacticus::Constraints::MassFunctions;

# Compute likelihood (and make a plot) for a Galacticus model given the stellar mass function data from Davidzon (2013;
# http://adsabs.harvard.edu/abs/2013A%26A...558A..23D).

# Data structure to hold the specification for our mass function.
my $massFunctionConfig;

# Get name of input and output files.
die("stellarMassFunction_VIPERS_z0.90.pl <galacticusFile> [options]") unless ( scalar(@ARGV) >= 1 );
$massFunctionConfig->{'self'          } = $0;
$massFunctionConfig->{'galacticusFile'} = $ARGV[0];
# Create a hash of named arguments.
my $iArg = -1;
my %arguments =
    (
     quiet => 0
    );
&Galacticus::Options::Parse_Options(\@ARGV,\%arguments);

# Specify the properties of this mass function.
my $entry                                    = 0;
$massFunctionConfig->{'redshift'           } = pdl 0.90;
$massFunctionConfig->{'analysisLabel'      } = "vipersStellarMassFunctionZ0.90";
$massFunctionConfig->{'discrepancyFileName'} = "discrepancy".ucfirst($massFunctionConfig->{'analysisLabel'}).".hdf5";
$massFunctionConfig->{'massType'           } = "massStellar";
$massFunctionConfig->{'massErrorRandomDex' } = 0.07;
$massFunctionConfig->{'xRange'             } = "2.0e10:1.0e12";
$massFunctionConfig->{'yRange'             } = "3.0e-7:1.0e-2";
$massFunctionConfig->{'xLabel'             } = "\$M_\\star\$ [\$M_\\odot\$]";
$massFunctionConfig->{'yLabel'             } = "\$\\mathrm{d}n/\\mathrm{d}\\log M_\\star\$ [Mpc\$^{-3}\$]";
$massFunctionConfig->{'title'              } = "Stellar mass function at \$z\\approx 0.90\$";
$massFunctionConfig->{'systematicParameter'} = "vipersStellarMassFunctionZ0.90MassSystematic";
$massFunctionConfig->{'systematicOrder'    } = 1;
$massFunctionConfig->{'systematicZeroPoint'} = 11.3;

# Read the observed data.
my $observations                                      = new PDL::IO::HDF5(&galacticusPath()."data/observations/massFunctionsStellar/Stellar_Mass_Function_VIPERS_2013_z0.90.hdf5");
$massFunctionConfig ->{'x'                           }  = $observations->dataset('mass'                )->get    (                  );
$massFunctionConfig ->{'y'                           }  = $observations->dataset('massFunctionObserved')->get    (                  );
$massFunctionConfig ->{'yIsPer'                      }  = "ln";
$massFunctionConfig ->{'xScaling'                    }  = "linear";
$massFunctionConfig ->{'yScaling'                    }  = "linear";
$massFunctionConfig ->{'covariance'                  }  = $observations->dataset('covariance'          )->get    (                  );
$massFunctionConfig ->{'errorModel'                  }  = "logNormal"                                                                ;
($massFunctionConfig->{'observationLabel'            }) = $observations                                 ->attrGet('label'           );
($massFunctionConfig->{'hubbleConstantObserved'      }) = $observations->group  ('Parameters'          )->attrGet('H_0'             );
($massFunctionConfig->{'omegaMatterObserved'         }) = $observations->group  ('Parameters'          )->attrGet('Omega_Matter'    );
($massFunctionConfig->{'omegaDarkEnergyObserved'     }) = $observations->group  ('Parameters'          )->attrGet('Omega_DE'        );
($massFunctionConfig->{'cosmologyScalingMass'        }) = $observations->dataset('mass'                )->attrGet('cosmologyScaling');
($massFunctionConfig->{'cosmologyScalingMassFunction'}) = $observations->dataset('massFunction'        )->attrGet('cosmologyScaling');

# Construct the mass function.
&Galacticus::Constraints::MassFunctions::Construct(\%arguments,$massFunctionConfig);

exit;
