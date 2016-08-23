#!/usr/bin/env perl
use strict;
use warnings;
use Cwd;
use lib exists($ENV{'GALACTICUS_ROOT_V094'}) ? $ENV{'GALACTICUS_ROOT_V094'}.'/perl' : cwd().'/perl';
use Galacticus::Path;

# Find the maximum likelihood estimate of the covariance matrix for the Baldry et al. (2012) GAMA stellar mass function.
# Andrew Benson (11-June-2014)

# Simply run the generic script with our config file as argument.
system(&galacticusPath()."constraints/dataAnalysis/scripts/covarianceMatrix.pl ".&galacticusPath()."constraints/dataAnalysis/stellarMassFunction_GAMA_z0.03/covarianceMatrixControl.xml");

exit;
