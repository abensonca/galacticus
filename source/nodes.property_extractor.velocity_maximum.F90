!! Copyright 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018,
!!           2019, 2020, 2021
!!    Andrew Benson <abenson@carnegiescience.edu>
!!
!! This file is part of Galacticus.
!!
!!    Galacticus is free software: you can redistribute it and/or modify
!!    it under the terms of the GNU General Public License as published by
!!    the Free Software Foundation, either version 3 of the License, or
!!    (at your option) any later version.
!!
!!    Galacticus is distributed in the hope that it will be useful,
!!    but WITHOUT ANY WARRANTY; without even the implied warranty of
!!    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!!    GNU General Public License for more details.
!!
!!    You should have received a copy of the GNU General Public License
!!    along with Galacticus.  If not, see <http://www.gnu.org/licenses/>.

!% Contains a module which implements a cooling rate property extractor class.

  use :: Dark_Matter_Profiles_DMO, only : darkMatterProfileDMO, darkMatterProfileDMOClass

  !# <nodePropertyExtractor name="nodePropertyExtractorVelocityMaximum">
  !#  <description>A cooling rate property extractor class.</description>
  !# </nodePropertyExtractor>
  type, extends(nodePropertyExtractorScalar) :: nodePropertyExtractorVelocityMaximum
     !% A velocityMaximum property extractor class.
     private
     class(darkMatterProfileDMOClass), pointer :: darkMatterProfileDMO_ => null()
   contains
     final     ::                velocityMaximumDestructor
     procedure :: extract     => velocityMaximumExtract
     procedure :: name        => velocityMaximumName
     procedure :: description => velocityMaximumDescription
     procedure :: unitsInSI   => velocityMaximumUnitsInSI
     procedure :: type        => velocityMaximumType
  end type nodePropertyExtractorVelocityMaximum

  interface nodePropertyExtractorVelocityMaximum
     !% Constructors for the ``velocityMaximum'' output analysis class.
     module procedure velocityMaximumConstructorParameters
     module procedure velocityMaximumConstructorInternal
  end interface nodePropertyExtractorVelocityMaximum

contains

  function velocityMaximumConstructorParameters(parameters) result(self)
    !% Constructor for the {\normalfont \ttfamily velocityMaximum} property extractor class which takes a parameter set as input.
    use :: Input_Parameters, only : inputParameter, inputParameters
    implicit none
    type (nodePropertyExtractorVelocityMaximum)                :: self
    type (inputParameters                     ), intent(inout) :: parameters
    class(darkMatterProfileDMOClass           ), pointer       :: darkMatterProfileDMO_

    !# <objectBuilder class="darkMatterProfileDMO" name="darkMatterProfileDMO_" source="parameters"/>
    self=nodePropertyExtractorVelocityMaximum(darkMatterProfileDMO_)
    !# <inputParametersValidate source="parameters"/>
    !# <objectDestructor name="darkMatterProfileDMO_"/>
    return
  end function velocityMaximumConstructorParameters

  function velocityMaximumConstructorInternal(darkMatterProfileDMO_) result(self)
    !% Internal constructor for the {\normalfont \ttfamily velocityMaximum} property extractor class.
    implicit none
    type (nodePropertyExtractorVelocityMaximum)                        :: self
    class(darkMatterProfileDMOClass           ), intent(in   ), target :: darkMatterProfileDMO_
    !# <constructorAssign variables="*darkMatterProfileDMO_"/>

    return
  end function velocityMaximumConstructorInternal

  subroutine velocityMaximumDestructor(self)
    !% Destructor for the {\normalfont \ttfamily velocityMaximum} property extractor class.
    implicit none
    type(nodePropertyExtractorVelocityMaximum), intent(inout) :: self

    !# <objectDestructor name="self%darkMatterProfileDMO_"/>
    return
  end subroutine velocityMaximumDestructor

  double precision function velocityMaximumExtract(self,node,instance)
    !% Implement a last isolated redshift output analysis.
    use :: Galacticus_Nodes, only : nodeComponentBasic, treeNode
    implicit none
    class(nodePropertyExtractorVelocityMaximum), intent(inout)           :: self
    type (treeNode                            ), intent(inout), target   :: node
    type (multiCounter                        ), intent(inout), optional :: instance
    !$GLC attributes unused :: instance

    velocityMaximumExtract=self%darkMatterProfileDMO_%circularVelocityMaximum(node)
    return
  end function velocityMaximumExtract

  function velocityMaximumName(self)
    !% Return the name of the last isolated redshift property.
    implicit none
    type (varying_string                      )                :: velocityMaximumName
    class(nodePropertyExtractorVelocityMaximum), intent(inout) :: self
    !$GLC attributes unused :: self

    velocityMaximumName=var_str('darkMatterProfileDMOVelocityMaximum')
    return
  end function velocityMaximumName

  function velocityMaximumDescription(self)
    !% Return a description of the velocityMaximum property.
    implicit none
    type (varying_string                      )                :: velocityMaximumDescription
    class(nodePropertyExtractorVelocityMaximum), intent(inout) :: self
    !$GLC attributes unused :: self

    velocityMaximumDescription=var_str('Maximum rotation velocity of the dark matter profile [km/s].')
    return
  end function velocityMaximumDescription

  double precision function velocityMaximumUnitsInSI(self)
    !% Return the units of the last isolated redshift property in the SI system.
    use :: Numerical_Constants_Prefixes, only : kilo
    implicit none
    class(nodePropertyExtractorVelocityMaximum), intent(inout) :: self
    !$GLC attributes unused :: self

    velocityMaximumUnitsInSI=kilo
    return
  end function velocityMaximumUnitsInSI

  integer function velocityMaximumType(self)
    !% Return the type of the last isolated redshift property.
    use :: Output_Analyses_Options, only : outputAnalysisPropertyTypeLinear
    implicit none
    class(nodePropertyExtractorVelocityMaximum), intent(inout) :: self
    !$GLC attributes unused :: self

    velocityMaximumType=outputAnalysisPropertyTypeLinear
    return
  end function velocityMaximumType

