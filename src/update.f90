module update
  use global_kkl , only : cphi1
  use global_kkl , only : cphi2
  use global_kkl , only : fphi
  use global_kkl , only : eta
  use global_kkl , only : cd1
  use global_kkl , only : cmu
  use global_sst , only : beta1
  use global_sst , only : beta2
  use global_sst , only : bstar
  use global_sst , only : sst_F1
  use global_vars, only : imx
  use global_vars, only : jmx
  use global_vars, only : kmx

  use global_vars, only : volume
    
  use global_vars, only : n_var
  use global_vars, only : imx
  use global_vars, only : jmx
  use global_vars, only : kmx
  use global_vars, only : gm
  use global_vars, only : sst_n_var
  use global_vars, only : qp
  use global_vars, only : qp_inf
  use global_vars, only : dist
  use global_vars, only : mu

  use global_vars, only : time_stepping_method
  use global_vars, only : time_step_accuracy
  use global_vars, only : global_time_step
  use global_vars, only : delta_t
  use global_vars, only : turbulence
  use global_vars, only : process_id

  use global_vars, only: F_p
  use global_vars, only: G_p
  use global_vars, only: H_p
  use global_vars, only: mass_residue
  use global_vars, only: x_mom_residue
  use global_vars, only: y_mom_residue
  use global_vars, only: z_mom_residue
  use global_vars, only: energy_residue
  use global_vars, only: TKE_residue
  use global_vars, only: omega_residue
  use global_vars, only: kl_residue
  use global_vars, only: residue

  use utils, only: alloc
  use utils, only:  dealloc 
  use utils, only:  dmsg
  use utils, only:  DEBUG_LEVEL

  use string

#include "error.inc"
#include "mpi.inc"
    private

    real, dimension(:,:,:,:), allocatable :: U_store
    real, dimension(:,:,:,:), allocatable :: R_store
    real, dimension(:)      , allocatable :: u1
    real, dimension(:)      , allocatable :: u2
    real, dimension(:)      , allocatable :: R

    ! Public methods
    public :: setup_update
    public :: destroy_update
    public :: get_next_solution

    contains


      subroutine setup_update()
        implicit none

        call alloc(u1,1,n_var)
        call alloc(u2,1,n_var)
        call alloc(R ,1,n_var)

        select case (time_step_accuracy)
          case ("none", "TVDRK3")
            ! Do nothing
            continue
          case ("RK2", "RK4")
            call alloc(U_store,-2,imx+2,-2,jmx+2,-2,kmx+2,1,n_var)
            call alloc(R_store, 1,imx-1, 1,jmx-1, 1,kmx-1,1,n_var)
          case default
            Fatal_error
        end select

      end subroutine setup_update


      subroutine destroy_update()
        implicit none

        select case (time_step_accuracy)
          case ("none", "TVDRK3")
            ! Do nothing
            continue
          case ("RK2", "RK4")
            call dealloc(U_store)
            call dealloc(R_store)
          case default
            Fatal_error
        end select
        call dealloc(u1)
        call dealloc(u2)
        call dealloc(R)

      end subroutine destroy_update


      subroutine get_next_solution()
        implicit none
        select case (time_step_accuracy)
            case ("none")
              call update_with("conservative", 1. ,1., .FALSE.) 
            case ("RK4")
              R_store=0.
              U_store = qp
              call update_with("conservative", 0.5  , 1., .FALSE., R_store, U_store) 
              call update_with("conservative", 0.5  , 2., .FALSE., R_store, U_store) 
              call update_with("conservative", 1.0  , 2., .FALSE., R_store, U_store) 
              call update_with("conservative", 1./6., 1., .TRUE. , R_store, U_store) 
            case("RK2")
              R_store=0.
              U_store(1:imx-1, 1:jmx-1, 1:kmx-1,1:n_var) = qp(1:imx-1, 1:jmx-1, 1:kmx-1,1:n_var)
              call update_with("conservative", 0.5  , 1., .FALSE., R_store, U_store) 
              call update_with("conservative", 0.5  , 1., .TRUE., R_store, U_store) 
            case ("TVDRK3")
              R_store=0.
              U_store(1:imx-1, 1:jmx-1, 1:kmx-1,1:n_var) = qp(1:imx-1, 1:jmx-1, 1:kmx-1,1:n_var)
              call update_with("conservative", 1.0  , 1.) 
              call update_with("conservative", 1.0  , 1.) 
              qp(1:imx-1,1:jmx-1,1:kmx-1,1:n_var) = 0.75*U_store(1:imx-1, 1:jmx-1, 1:kmx-1,1:n_var) +&
              0.25*qp(1:imx-1,1:jmx-1,1:kmx-1,1:n_var)
              call update_with("conservative", 0.5  , 1.) 
              qp(1:imx-1,1:jmx-1,1:kmx-1,1:n_var) = 0.33*U_store(1:imx-1, 1:jmx-1, 1:kmx-1,1:n_var) +&
              0.66*qp(1:imx-1,1:jmx-1,1:kmx-1,1:n_var)
            case default
              Fatal_error
        end select
      end subroutine get_next_solution

      subroutine update_with(type, time_factor, store_factor, use, Rn, un)
        implicit none
        character(len=*), intent(in) :: type
        real, intent(in), optional :: time_factor ! time factor
        real, intent(in), optional :: store_factor ! time factor
        logical, intent(in), optional :: use
        real, dimension(-2:imx+2,-2:jmx+2,-2:kmx+2,1:n_var), intent(in), optional :: un
        real, dimension(1:imx-1,1:jmx-1,1:kmx-1,1:n_var), intent(inout), optional :: Rn
        real               :: TF = 1.0 !time factor
        real               :: SF = 1.0!store factor
        Logical               :: TU = .FALSE. !to use or nor
        integer :: i,j,k
        real :: KE=0.
        real :: beta

        if(present(time_factor)) TF=time_factor
        if(present(store_factor)) SF=store_factor
        if(present(use)) TU=use

        select case(type)
          case('primitive')
            !include "update_primitive.inc"

            !update primitive variable
            do k = 1,kmx-1
              do j = 1,jmx-1
                do i = 1,imx-1
            
                  !check if user want to update from particular solution
                  if(present(un))then
                    u1(1:n_var) = un(i,j,k,1:n_var)
                  else
                    u1(1:n_var) = qp(i,j,k,1:n_var)
                  end if
            
                  ! finding primitive residue
                  R(1) = mass_residue(i,j,k)
                  R(2) = -1*(u1(2)/u1(1))*mass_residue(i,j,k) + x_mom_residue(i,j,k)/u1(1)
                  R(3) = -1*(u1(3)/u1(1))*mass_residue(i,j,k) + y_mom_residue(i,j,k)/u1(1)
                  R(4) = -1*(u1(4)/u1(1))*mass_residue(i,j,k) + z_mom_residue(i,j,k)/u1(1)
                  R(5) = 0.5*(gm-1.)*(sum(u1(2:4)**2)*mass_residue(i,j,k)) &
                         -(gm-1.)*u1(2)*x_mom_residue(i,j,k)               &
                         -(gm-1.)*u1(3)*y_mom_residue(i,j,k)               &
                         -(gm-1.)*u1(4)*z_mom_residue(i,j,k)               &
                         +(gm-1.)*energy_residue(i,j,k)
            
                  select case(turbulence)
                    case('none')
                      !do nothing
                      continue
                    case('sst')
                      beta = beta1*sst_F1(i,j,k) + (1. - sst_F1(i,j,k))*beta2
                      R(5) = R(5) - (gm-1.)*TKE_residue(i,j,k)
                      R(6) = -(u1(6)/u1(1))*mass_residue(i,j,k)&
                             +(1./(1.+bstar*u1(6)*delta_t(i,j,k)))*TKE_residue(i,j,k)/u1(1)
                      R(7) = -(u1(7)/u1(1))*mass_residue(i,j,k)&
                             +(1./(1.+2.*beta*u1(6)*delta_t(i,j,k)))*omega_residue(i,j,k)/u1(1)
                    case('kkl')
                      eta  = u1(1)*dist(i,j,k)*(sqrt(0.3*u1(6))/(20*mu(i,j,k)))
                      fphi = (1+cd1*eta)/(1+eta**4)
                      R(5) = R(5) - (gm-1.)*TKE_residue(i,j,k)
                      R(6) = -(u1(6)/u1(1))*mass_residue(i,j,k)&
                             + 1./(1.+(2.5*((cmu**0.75)*u1(1)*(u1(6)**1.5)/u1(7))&
                             -(2*mu(i,j,k)/dist(i,j,k))*delta_t(i,j,k)))*TKE_residue(i,j,k)/u1(1)
                      R(7) = -(u1(7)/u1(1))*mass_residue(i,j,k)&
                             + 1./(1.-(6*mu(i,j,k)*fphi)*delta_t(i,j,k))*kl_residue(i,j,k)/u1(1)
                    case DEFAULT
                      Fatal_error
                  end select
            
                        
                 !check if user want to store residue
                  if(present(Rn)) then
                    Rn(i,j,k,1:n_var) = Rn(i,j,k,1:n_var) + SF*R(1:n_var)
                    if(TU) R(:) = Rn(i,j,k,:)
                  end if
                 
            
                 !update
                 u2(:) = u1(:) - R(:)*(TF*delta_t(i,j,k)/volume(i,j,k))
            
                 !check solution for non pyhysical results
                 if((u2(1) < 0.) .or. (u2(5) < 0.))then
                   Fatal_error
                 else !update
                   qp(i,j,k,1:5) = u2(1:5)
                   if(u2(6)>0.) qp(i,j,k,6) = u2(6)
                   if(u2(7)>0.) qp(i,j,k,7) = u2(7)
                 end if
                end do
              end do
            end do
            
          case('conservative')
            !include "update_conservative.inc"

            !update conservative variable
            do k = 1,kmx-1
              do j = 1,jmx-1
                do i = 1,imx-1

                  ! getting conservative variable
                  !check if user want to update from particular solution
                  if(present(un))then
                    u1(1)  = un(i,j,k,1)
                    u1(2:) = un(i,j,k,2:)*u1(1)
                    select case(turbulence)
                      case('sst', 'kkl')
                        KE = u1(6)
                      case DEFAULT
                        KE = 0.
                    end select
                    u1(5) = un(i,j,k,5)/(gm-1.) + (0.5*sum(u1(2:4)**2)/u1(1)) + KE
                  else
                    u1(1)  = qp(i,j,k,1)
                    u1(2:) = qp(i,j,k,2:)*u1(1)
                    select case(turbulence)
                      case('sst', 'kkl')
                        KE = u1(6)
                      case DEFAULT
                        KE = 0.
                    end select
                    u1(5) = qp(i,j,k,5)/(gm-1.) + (0.5*sum(u1(2:4)**2)/u1(1)) + KE
                  end if

                 ! get R
                  R(1:n_var) = residue(i,j,k,1:n_var) 
                  select case(trim(turbulence))
                    case('none')
                      !do nothing
                      continue
                    case('sst')
                      beta = beta1*sst_F1(i,j,k) + (1. - sst_F1(i,j,k))*beta2
                      R(6) = R(6)/(1+(beta*qp(i,j,k,7)*delta_t(i,j,k)))
                      R(7) = R(7)/(1+(2*beta*qp(i,j,k,7)*delta_t(i,j,k)))
                    case('kkl')
                      eta  = u1(1)*dist(i,j,k)*(sqrt(0.3*u1(6))/(20*mu(i,j,k)))
                      fphi = (1+cd1*eta)/(1+eta**4)
                      R(6) = R(6)/(1.+(2.5*((cmu**0.75)*sqrt(u1(1))*(u1(6)**1.5)/u1(7))&
                             -(2*mu(i,j,k)/(dist(i,j,k)**2))*delta_t(i,j,k)))
                      R(7) = R(7)/(1.-(6*mu(i,j,k)*fphi/(dist(i,j,k)**2))*delta_t(i,j,k))
                    case DEFAULT
                      Fatal_error
                  end select

                 !check if user want to store residue
                 if(present(Rn)) then
                   Rn(i,j,k,1:n_var) = Rn(i,j,k,1:n_var) + SF*R(1:n_var)
                   if(TU) R(:) = Rn(i,j,k,:)
                 end if

                 !update
                 u2(1:n_var) = u1(1:n_var) - R(1:n_var)*(TF*delta_t(i,j,k)/volume(i,j,k))

                ! getting primitve variable back variable
                  u2(1)  = u2(1)
                  u2(2:) = u2(2:)/u2(1)
                  select case(turbulence)
                    case('sst', 'kkl')
                      KE = u2(6)
                    case DEFAULT
                      KE = 0.
                  end select
                  u2(5) = (gm-1.)*u2(1)*(u2(5) - (0.5*sum(u2(2:4)**2)) - KE)

                 !check solution for non pyhysical results
                 if((u2(1) < 0.) .or. (u2(5)) < 0.)then
                   Fatal_error
                 else !update
                   qp(i,j,k,1:5) = u2(1:5)
                   if(u2(6)>0.) qp(i,j,k,6) = u2(6)
                   if(u2(7)>0.) qp(i,j,k,7) = u2(7)
                 end if
                end do
              end do
            end do

          case DEFAULT
            Fatal_error
        end select

      end subroutine update_with


end module update
