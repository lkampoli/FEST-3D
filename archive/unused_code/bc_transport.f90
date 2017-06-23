module bc_transport
  !--------------------------------------------
  ! 170515  Jatinder Pal Singh Sandhu
  ! Aim : applying boundary condition to domain
  !-------------------------------------------
  use global_vars, only: imin_id
  use global_vars, only: imax_id
  use global_vars, only: jmin_id
  use global_vars, only: jmax_id
  use global_vars, only: kmin_id
  use global_vars, only: kmax_id
  use global_vars, only: imx
  use global_vars, only: jmx
  use global_vars, only: kmx
  use global_vars, only: turbulence
  use global_vars, only: mu
  use global_vars, only: mu_t
  use global_vars, only: process_id
  use global_vars, only: face_names
  use global_vars, only: id

  use utils,       only: turbulence_read_error

  implicit none
  private

  integer                        :: face_num

  public :: populate_ghost_transport
  public :: copy


  contains

    subroutine populate_ghost_transport()
      implicit none
      integer :: i
      character(len=4) :: face

      
      do i = 1,6
        face_num = i
        face = face_names(face_num)

        select case(id(face_num))

          case(-4:-1,-6)
            call extrapolate(face)

          case(-5)
            call adiabatic_wall(face)

          case Default
            if(id(i)>=0) then
              continue !interface boundary 
            else
              print*, " boundary condition not recognised -> id is :", id(i)
            end if

          end select
        end do
      end subroutine populate_ghost_transport


      subroutine extrapolate(face)
        implicit none
        character(len=*), intent(in) :: face
        select case (turbulence)
          case('none')
            !do nothing
            continue
          case('sst')
            call copy(mu_t   , "symm", face)
          case DEFAULT
            call turbulence_read_error()
        end select
      end subroutine extrapolate

      subroutine adiabatic_wall(face)
        implicit none
        character(len=*), intent(in) :: face
        select case (turbulence)
          case('none')
            !do nothing
            continue
          case('sst')
            call copy(mu_t   , "anti", face)
          case DEFAULT
            call turbulence_read_error()
        end select
      end subroutine adiabatic_wall

      subroutine copy(var, type, face)
        implicit none
        character(len=*), intent(in) :: face
        character(len=*), intent(in) :: type
        real, dimension(-2:imx+2, -2:jmx+2, -2:kmx+2), intent(inout) :: var
        real :: a2=1

        select case(type)
          case("anti")
            a2 = -1
          case("symm")
            a2 =  1
          case DEFAULT
            print*, "ERROR: Wrong boundary condition type"
        end select

        select case(face)
          case("imin")
              var(      0, 1:jmx-1, 1:kmx-1) = a2*var(     1, 1:jmx-1, 1:kmx-1)
          case("imax")
              var(  imx  , 1:jmx-1, 1:kmx-1) = a2*var( imx-1, 1:jmx-1, 1:kmx-1)
          case("jmin")
              var(1:imx-1,       0, 1:kmx-1) = a2*var(1:imx-1,      1, 1:kmx-1)
          case("jmax")
              var(1:imx-1,   jmx  , 1:kmx-1) = a2*var(1:imx-1,  jmx-1, 1:kmx-1)
          case("kmin")
              var(1:imx-1, 1:jmx-1,       0) = a2*var(1:imx-1, 1:jmx-1,      1)
          case("kmax")
              var(1:imx-1, 1:jmx-1,   kmx  ) = a2*var(1:imx-1, 1:jmx-1,  kmx-1)
          case DEFAULT
            print*, "ERROR: wrong face for boundary condition"
        end select
      end subroutine copy


end module bc_transport