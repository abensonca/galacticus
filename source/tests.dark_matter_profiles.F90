!! Copyright 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016
!!    Andrew Benson <abenson@obs.carnegiescience.edu>
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

!% Contains a program which tests dark matter profiles.

program Test_Dark_Matter_Profiles
  !% Tests dark matter profiles.
  use ISO_Varying_String
  use Memory_Management
  use Input_Parameters
  use Galacticus_Nodes
  use Node_Components
  use Unit_Tests
  use Cosmology_Functions
  use Dark_Matter_Halo_Scales
  use Dark_Matter_Profiles
  implicit none
  type            (treeNode                      ), pointer      :: node
  class           (nodeComponentBasic            ), pointer      :: basic
  class           (nodeComponentDarkMatterProfile), pointer      :: dmProfile
  class           (cosmologyFunctionsClass       ), pointer      :: cosmologyFunctions_
  class           (darkMatterHaloScaleClass      ), pointer      :: darkMatterHaloScale_
  double precision                                , parameter    :: concentration            =8.0d0                                                          , &
       &                                                            massVirial               =1.0d0
  double precision                                , dimension(7) :: radius                   =[0.125d0, 0.250d0, 0.500d0, 1.000d0, 2.000d0, 4.000d0, 8.000d0]
  double precision                                , dimension(7) :: mass                                                                                     , &
       &                                                            density                                                                                  , &
       &                                                            fourier
  type            (darkMatterProfileBurkert      )               :: darkMatterProfileBurkert_
  type            (varying_string                )               :: parameterFile
  integer                                                        :: i
  double precision                                               :: radiusScale

  ! Read in basic code memory usage.
  call Code_Memory_Usage         ('tests.dark_matter_profiles.size')
  ! Begin unit tests.
  call Unit_Tests_Begin_Group    ('Dark matter profiles'           )
  ! Read in controlling parameters.
  parameterFile='testSuite/parameters/darkMatterProfiles.xml'
  call Input_Parameters_File_Open(parameterFile                    )
  ! Initialize node components.
  call Node_Components_Initialize(                                 )
  ! Create a node.
  node                      => treeNode                                    (                 )
  ! Create components.
  basic                     => node                    %basic              (autoCreate=.true.)
  dmProfile                 => node                    %darkMatterProfile  (autoCreate=.true.)
  ! Get required objects.
  cosmologyFunctions_       => cosmologyFunctions                          (                 )
  darkMatterHaloScale_      => darkMatterHaloScale                         (                 )
  darkMatterProfileBurkert_ =  darkMatterProfileBurkert                    (                 )
  ! Set properties.
  call basic%timeSet     (cosmologyFunctions_%cosmicTime(1.0d0))
  call basic%massSet     (massVirial                           )
  ! Compute scale radius.
  radiusScale               = +darkMatterHaloScale_    %virialRadius       (node             ) &
       &                      /concentration             
  call dmProfile%scaleSet(radiusScale                          )
  ! Test Burkert profile.
  call Unit_Tests_Begin_Group('Burkert profile')
  do i=1,7
     mass   (i)=darkMatterProfileBurkert_%enclosedMass(node,      radiusScale*radius(i))
     density(i)=darkMatterProfileBurkert_%density     (node,      radiusScale*radius(i))*radiusScale**3
     fourier(i)=darkMatterProfileBurkert_%kSpace      (node,1.0d0/radiusScale/radius(i))
  end do
  call Assert(                        &
       &      'enclosed mass'       , &
       &      mass                  , &
       &      [                       &
       &       4.1583650166653620d-4, &
       &       2.9870571374971090d-3, &
       &       1.8812441757378840d-2, &
       &       8.9614051908432800d-2, &
       &       0.2805458115927276d+0, &
       &       0.5990982283029260d+0, &
       &       1.0000000000000000d+0  &
       &      ]                     , &
       &      relTol=1.0d-6           &
       &     )  
  call Assert(                        &
       &      'density'             , &
       &      density               , &
       &      [                       &
       &       4.9082352873191440d-2, &
       &       4.2225259457083800d-2, &
       &       2.9909558782101030d-2, &
       &       1.4020105679109860d-2, &
       &       3.7386948477626290d-3, &
       &       6.5976967901693440d-4, &
       &       9.5863970455452000d-5  &
       &      ]                     , &
       &      relTol=1.0d-6           &
       &     )
  call Assert(                        &
       &      'fourier'             , &
       &      fourier               , &
       &      [                       &
       &       3.2941046717529910d-4, &
       &       6.7507368425877680d-3, &
       &       6.0387631952687390d-2, &
       &       0.2118984282100852d+0, &
       &       0.5171391325515731d+0, &
       &       0.8364966656849830d+0, &
       &       0.9557322027757890d+0  &
       &      ]                     , &
       &      relTol=1.0d-6           &
       &     )  
  call Unit_Tests_End_Group       ()
  ! Close the input parameter file.
  call Input_Parameters_File_Close()
  ! End unit tests.
  call Unit_Tests_End_Group       ()
  call Unit_Tests_Finish          ()
end program Test_Dark_Matter_Profiles