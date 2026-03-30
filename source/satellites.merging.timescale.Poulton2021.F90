!! Copyright 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018,
!!           2019, 2020, 2021, 2022, 2023, 2024, 2025, 2026
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

  !!{
  Implements calculations of satellite merging times using the \cite{poulton_extracting_2021} method.
  !!}

  use :: Dark_Matter_Halo_Scales , only : darkMatterHaloScaleClass
  use :: Dark_Matter_Profiles_DMO, only : darkMatterProfileDMOClass

  !![
  <satelliteMergingTimescales name="satelliteMergingTimescalesPoulton2021">
   <description>
    A satellite merging timescales class which computes merging timescales using the fitting formula of
    \cite{poulton_extracting_2021}. The merging timescale is:
    \begin{equation}
     T_\mathrm{merge} = A \, T_\mathrm{dyn}(r) \left(\frac{r}{R_\mathrm{vir}}\right)^b \left(\frac{R_\mathrm{peri}}{R_\mathrm{vir}}\right)^c,
    \end{equation}
    where $T_\mathrm{dyn}(r) = r/v_\mathrm{circ}(r)$ is the local dynamical time, $R_\mathrm{peri}$ is the
    pericentric distance computed using the locally Keplerian approximation with the enclosed host mass, and
    \begin{equation}
     b = \begin{cases} b_\mathrm{interior} & r < R_\mathrm{vir} \\ b_\mathrm{exterior} & r \geq R_\mathrm{vir} \end{cases}.
    \end{equation}
    The default parameter values $A=5.5$, $c=0.2$, $b_\mathrm{interior}=-0.5$, and $b_\mathrm{exterior}=-1.0$ are
    those favoured by \cite{poulton_extracting_2021}.
   </description>
  </satelliteMergingTimescales>
  !!]
  type, extends(satelliteMergingTimescalesClass) :: satelliteMergingTimescalesPoulton2021
     !!{
     A class implementing the \cite{poulton_extracting_2021} method for satellite merging timescales.
     !!}
     private
     class           (darkMatterHaloScaleClass ), pointer :: darkMatterHaloScale_  => null()
     class           (darkMatterProfileDMOClass), pointer :: darkMatterProfileDMO_ => null()
     double precision                                     :: timescaleMultiplier
     double precision                                     :: A
     double precision                                     :: c
     double precision                                     :: bInterior
     double precision                                     :: bExterior
   contains
     final     ::                     poulton2021Destructor
     procedure :: timeUntilMerging => poulton2021TimeUntilMerging
  end type satelliteMergingTimescalesPoulton2021

  interface satelliteMergingTimescalesPoulton2021
     !!{
     Constructors for the \refClass{satelliteMergingTimescalesPoulton2021} satellite merging timescale class.
     !!}
     module procedure poulton2021ConstructorParameters
     module procedure poulton2021ConstructorInternal
  end interface satelliteMergingTimescalesPoulton2021

contains

  function poulton2021ConstructorParameters(parameters) result(self)
    !!{
    Constructor for the \cite{poulton_extracting_2021} merging timescale class which builds the object from a parameter set.
    !!}
    use :: Error           , only : Error_Report
    use :: Galacticus_Nodes, only : defaultBasicComponent
    use :: Input_Parameters, only : inputParameter        , inputParameters
    implicit none
    type            (satelliteMergingTimescalesPoulton2021)                :: self
    type            (inputParameters                      ), intent(inout) :: parameters
    class           (darkMatterHaloScaleClass             ), pointer       :: darkMatterHaloScale_
    class           (darkMatterProfileDMOClass            ), pointer       :: darkMatterProfileDMO_
    double precision                                                       :: timescaleMultiplier  , A         , &
         &                                                                    c                    , bInterior , &
         &                                                                    bExterior

    if (.not.defaultBasicComponent%massIsGettable()) call Error_Report('this method requires that the "mass" property of the basic component be gettable'//{introspection:location})
    !![
    <inputParameter>
      <name>timescaleMultiplier</name>
      <defaultValue>1.0d0</defaultValue>
      <description>A multiplier for the merging timescale in the \cite{poulton_extracting_2021} satellite merging timescale calculations.</description>
      <source>parameters</source>
    </inputParameter>
    <inputParameter>
      <name>A</name>
      <defaultValue>5.5d0</defaultValue>
      <description>The normalization constant, $A$, in the \cite{poulton_extracting_2021} satellite merging timescale fitting formula.</description>
      <source>parameters</source>
    </inputParameter>
    <inputParameter>
      <name>c</name>
      <defaultValue>0.2d0</defaultValue>
      <description>The exponent, $c$, on the pericentric distance ratio in the \cite{poulton_extracting_2021} satellite merging timescale fitting formula.</description>
      <source>parameters</source>
    </inputParameter>
    <inputParameter>
      <name>bInterior</name>
      <defaultValue>-0.5d0</defaultValue>
      <description>The radial exponent, $b$, in the \cite{poulton_extracting_2021} satellite merging timescale fitting formula for satellites inside the virial radius ($r &lt; R_\mathrm{vir}$).</description>
      <source>parameters</source>
    </inputParameter>
    <inputParameter>
      <name>bExterior</name>
      <defaultValue>-1.0d0</defaultValue>
      <description>The radial exponent, $b$, in the \cite{poulton_extracting_2021} satellite merging timescale fitting formula for satellites outside the virial radius ($r \geq R_\mathrm{vir}$).</description>
      <source>parameters</source>
    </inputParameter>
    <objectBuilder class="darkMatterHaloScale"  name="darkMatterHaloScale_"  source="parameters"/>
    <objectBuilder class="darkMatterProfileDMO" name="darkMatterProfileDMO_" source="parameters"/>
    !!]
    self=satelliteMergingTimescalesPoulton2021(timescaleMultiplier,A,c,bInterior,bExterior,darkMatterHaloScale_,darkMatterProfileDMO_)
    !![
    <inputParametersValidate source="parameters"/>
    <objectDestructor name="darkMatterHaloScale_" />
    <objectDestructor name="darkMatterProfileDMO_"/>
    !!]
    return
  end function poulton2021ConstructorParameters

  function poulton2021ConstructorInternal(timescaleMultiplier,A,c,bInterior,bExterior,darkMatterHaloScale_,darkMatterProfileDMO_) result(self)
    !!{
    Constructor for the \cite{poulton_extracting_2021} merging timescale class.
    !!}
    implicit none
    type            (satelliteMergingTimescalesPoulton2021)                        :: self
    double precision                                       , intent(in   )         :: timescaleMultiplier  , A         , &
         &                                                                            c                    , bInterior , &
         &                                                                            bExterior
    class           (darkMatterHaloScaleClass             ), intent(in   ), target :: darkMatterHaloScale_
    class           (darkMatterProfileDMOClass            ), intent(in   ), target :: darkMatterProfileDMO_
    !![
    <constructorAssign variables="timescaleMultiplier, A, c, bInterior, bExterior, *darkMatterHaloScale_, *darkMatterProfileDMO_"/>
    !!]

    return
  end function poulton2021ConstructorInternal

  subroutine poulton2021Destructor(self)
    !!{
    Destructor for the \refClass{satelliteMergingTimescalesPoulton2021} satellite merging timescale class.
    !!}
    implicit none
    type(satelliteMergingTimescalesPoulton2021), intent(inout) :: self

    !![
    <objectDestructor name="self%darkMatterHaloScale_" />
    <objectDestructor name="self%darkMatterProfileDMO_"/>
    !!]
    return
  end subroutine poulton2021Destructor

  double precision function poulton2021TimeUntilMerging(self,node,orbit)
    !!{
    Return the timescale for merging satellites using the \cite{poulton_extracting_2021} method.
    !!}
    use :: Galacticus_Nodes                , only : nodeComponentBasic             , treeNode
    use :: Kepler_Orbits                   , only : keplerOrbit
    use :: Mass_Distributions              , only : massDistributionClass
    use :: Numerical_Constants_Astronomical, only : gravitationalConstant_internal , MpcPerKmPerSToGyr
    implicit none
    class           (satelliteMergingTimescalesPoulton2021), intent(inout) :: self
    type            (treeNode                             ), intent(inout) :: node
    type            (keplerOrbit                          ), intent(inout) :: orbit
    type            (treeNode                             ), pointer       :: nodeHost
    class           (nodeComponentBasic                   ), pointer       :: basic
    class           (massDistributionClass                ), pointer       :: massDistribution_
    double precision                                                       :: orbitalRadius        , virialRadius    , &
         &                                                                    velocityCircular      , dynamicalTime   , &
         &                                                                    G_M_encl              , pericenterRadius, &
         &                                                                    massSatellite         , bExponent

    ! Find the host node.
    if (node%isSatellite()) then
       nodeHost => node%parent
    else
       nodeHost => node%parent%firstChild
    end if
    ! Return infinite timescale for unbound orbits.
    if (orbit%eccentricity() >= 1.0d0) then
       poulton2021TimeUntilMerging=satelliteMergeTimeInfinite
       return
    end if
    ! Get the orbital radius and host virial radius.
    orbitalRadius=orbit%radius                        (         )
    virialRadius =self %darkMatterHaloScale_%radiusVirial(nodeHost)
    ! Get the local circular velocity at the orbital radius.
    massDistribution_ => self%darkMatterProfileDMO_%get         (nodeHost      )
    velocityCircular  =  massDistribution_          %rotationCurve(orbitalRadius)
    !![
    <objectDestructor name="massDistribution_"/>
    !!]
    ! Return instantaneous merging if circular velocity vanishes (e.g. r → 0).
    if (velocityCircular <= 0.0d0) then
       poulton2021TimeUntilMerging=0.0d0
       return
    end if
    ! Local dynamical time T_dyn(r) = r/v_circ(r), converted from Mpc/(km/s) to Gyr.
    dynamicalTime=orbitalRadius/velocityCircular*MpcPerKmPerSToGyr
    ! G×M_encl(r) = r×v_circ²(r) [Mpc×(km/s)²].
    G_M_encl=orbitalRadius*velocityCircular**2
    ! Pericentric radius via the locally-Keplerian approximation including the two-body
    ! reduced mass correction (Poulton et al. 2021, eq. for R_peri):
    !   R_peri = j²×(1+M_sat/M_encl) / [(1+e)×G×M_encl]
    ! where j = orbit%angularMomentum() is specific angular momentum per unit satellite
    ! mass [Mpc×km/s], and G×M_encl = r×v_circ² avoids explicit use of G except in the
    ! dimensionless mass ratio M_sat/M_encl = M_sat×G_internal/G_M_encl.
    basic            =>  node%basic()
    massSatellite    =   basic%mass()
    pericenterRadius = +orbit%angularMomentum()**2                                              &
         &             *(1.0d0+massSatellite*gravitationalConstant_internal/G_M_encl)           &
         &             /((1.0d0+orbit%eccentricity())*G_M_encl)
    ! Select radial exponent b depending on whether satellite is inside or outside R_vir.
    if (orbitalRadius < virialRadius) then
       bExponent=self%bInterior
    else
       bExponent=self%bExterior
    end if
    ! Evaluate the Poulton et al. (2021) fitting formula.
    poulton2021TimeUntilMerging=+self%timescaleMultiplier                    &
         &                      *self%A                                      &
         &                      *dynamicalTime                               &
         &                      *(orbitalRadius   /virialRadius)**bExponent  &
         &                      *(pericenterRadius/virialRadius)**self%c
    return
  end function poulton2021TimeUntilMerging
