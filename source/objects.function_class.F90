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
Contains a module which defines the base class for all \mono{functionClass} classes.
!!}

module Function_Classes
  !!{
  Defines the base class for all \mono{functionClass} classes.
  !!}
  use :: ISO_Varying_String, only : assignment(=), varying_string
  implicit none
  private
  public :: functionClass

  type, abstract :: functionClass
     !!{
     The base class for all \mono{functionClass} classes.
     !!}
     logical :: isDefaultOfClass=.false.
     integer :: referenceCount  =0
   contains
     !![
     <methods>
       <method description="Reset the reference count to this object to 0." method="referenceCountReset" />
       <method description="Increment the reference count to this object." method="referenceCountIncrement" />
       <method description="Decrement the reference count to this object and return the new reference count." method="referenceCountDecrement" />
       <method description="Return true if this is the default object of this class." method="isDefault" />
     </methods>
     !!]
     procedure :: isDefault               => functionClassIsDefault
     procedure :: referenceCountReset     => functionClassReferenceCountReset
     procedure :: referenceCountIncrement => functionClassReferenceCountIncrement
     procedure :: referenceCountDecrement => functionClassReferenceCountDecrement
  end type functionClass

contains

  logical function functionClassIsDefault(self)
    !!{
    Return true if this is the default object of this class.
    !!}
    implicit none
    class(functionClass), intent(in   ) :: self

    functionClassIsDefault=self%isDefaultOfClass
    return
  end function functionClassIsDefault

  subroutine functionClassReferenceCountReset(self)
    !!{
    Reset the reference count to this object to 0.
    !!}
    implicit none
    class(functionClass), intent(inout) :: self

    self%referenceCount=1
    return
  end subroutine functionClassReferenceCountReset

  subroutine functionClassReferenceCountIncrement(self)
    !!{
    Increment the reference count to this object.
    !!}
    implicit none
    class(functionClass), intent(inout) :: self

    self%referenceCount=self%referenceCount+1
   return
  end subroutine functionClassReferenceCountIncrement

  integer function functionClassReferenceCountDecrement(self)
    !!{
    Decrement the reference count to this object and return the new count.
    !!}
    implicit none
    class(functionClass), intent(inout) :: self

    self%referenceCount=self%referenceCount-1
    functionClassReferenceCountDecrement=self%referenceCount
    return
  end function functionClassReferenceCountDecrement

end module Function_Classes
