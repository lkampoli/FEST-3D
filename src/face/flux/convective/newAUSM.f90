module ausmUP
    !-------------------------------------------------------------------
    ! The slau scheme is a type of flux-splitting scheme
    !-------------------------------------------------------------------
    
    use global_vars, only : imx
    use global_vars, only : jmx
    use global_vars, only : kmx

    use global_vars, only : xnx, xny, xnz !face unit normal x
    use global_vars, only : ynx, yny, ynz !face unit normal y
    use global_vars, only : znx, zny, znz !face unit normal z
    use global_vars, only : xA, yA, zA    !face area

    use global_vars, only : gm
    use global_vars, only : n_var
    use global_vars, only : turbulence
    use global_vars, only : process_id
    use global_vars, only : current_iter
    use global_vars, only : max_iters
    use global_vars, only : make_F_flux_zero
    use global_vars, only : make_G_flux_zero
    use global_vars, only : make_H_flux_zero

    use utils, only: alloc, dealloc, dmsg
    use face_interpolant, only: x_qp_left, x_qp_right 
    use face_interpolant, only: y_qp_left, y_qp_right
    use face_interpolant, only:  z_qp_left, z_qp_right

    !ausm
    use face_interpolant, only: x_qp_left, x_qp_right, y_qp_left, y_qp_right, &
                z_qp_left, z_qp_right, &
            x_density_left, x_x_speed_left, x_y_speed_left, x_z_speed_left, &
                x_pressure_left, &
            x_density_right, x_x_speed_right, x_y_speed_right, x_z_speed_right, &
                x_pressure_right, &
            y_density_left, y_x_speed_left, y_y_speed_left, y_z_speed_left, &
                y_pressure_left, &
            y_density_right, y_x_speed_right, y_y_speed_right, y_z_speed_right, &
                y_pressure_right, &
            z_density_left, z_x_speed_left, z_y_speed_left, z_z_speed_left, &
                z_pressure_left, &
            z_density_right, z_x_speed_right, z_y_speed_right, z_z_speed_right, &
                z_pressure_right

    implicit none
    private

    real, public, dimension(:, :, :, :), allocatable, target :: F, G, H, residue
    real, dimension(:, :, :, :), pointer :: flux_p

    ! Public members
    public :: setup_scheme
    public :: destroy_scheme
    public :: compute_fluxes
    public :: get_residue
    
    contains

        subroutine setup_scheme()

            implicit none

            call dmsg(1, 'slau', 'setup_scheme')

            call alloc(F, 1, imx, 1, jmx-1, 1, kmx-1, 1, n_var, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'F - slau.')
            call alloc(G, 1, imx-1, 1, jmx, 1, kmx-1, 1, n_var, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'G - slau.')
            call alloc(H, 1, imx-1, 1, jmx-1, 1, kmx, 1, n_var, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'H - slau.')
            call alloc(residue, 1, imx-1, 1, jmx-1, 1, kmx-1, 1, n_var, &
                    errmsg='Error: Unable to allocate memory for ' // &
                        'residue - slau.')

        end subroutine setup_scheme

        subroutine destroy_scheme()

            implicit none

            call dmsg(1, 'slau', 'destroy_scheme')
            
            call dealloc(F)
            call dealloc(G)
            call dealloc(H)

        end subroutine destroy_scheme

        subroutine compute_flux(f_dir)

            implicit none
            character, intent(in) :: f_dir
            integer :: i, j, k 
            integer :: i_f, j_f, k_f ! Flags to determine face direction
            real, dimension(:, :, :), pointer :: fA, nx, ny, nz
            real, dimension(:,:,:,:), pointer :: f_qp_left, f_qp_right
            real, dimension(1:n_var) :: F_plus, F_minus
            real :: pbar
            real :: HL, HR !enthalpy
            real :: uL, uR
            real :: vL, vR
            real :: wL, wR
            real :: pL, pR
            real :: rL, rR
            real :: cL, cR
            real :: C
            real :: ML, MR
            real :: VnL, VnR
            real :: betaL, betaR
            real :: alphaL, alphaR
            real :: FmL, FmR
            real :: Mface

            call dmsg(1, 'slau', 'compute_flux '//trim(f_dir))
            
            select case (f_dir)
                case ('x')
                    i_f = 1
                    j_f = 0
                    k_f = 0
                    flux_p => F
                    fA => xA
                    nx => xnx
                    ny => xny
                    nz => xnz
                    f_qp_left => x_qp_left
                    f_qp_right => x_qp_right
                case ('y')
                    i_f = 0
                    j_f = 1
                    k_f = 0
                    flux_p => G
                    fA => yA
                    nx => ynx
                    ny => yny
                    nz => ynz
                    f_qp_left => y_qp_left
                    f_qp_right => y_qp_right
                case ('z')
                    i_f = 0
                    j_f = 0
                    k_f = 1
                    flux_p => H
                    fA => zA
                    nx => znx
                    ny => zny
                    nz => znz
                    f_qp_left => z_qp_left
                    f_qp_right => z_qp_right
                case default
                    call dmsg(5, 'slau', 'compute_flux', &
                            'Direction not recognised')
                    stop
            end select
            

            do k = 1, kmx - 1 + k_f
             do j = 1, jmx - 1 + j_f 
              do i = 1, imx - 1 + i_f

                ! -- primitve face state assignment --
                ! ---- left face quantities ----
                rL = f_qp_left(i,j,k,1)
                uL = f_qp_left(i,j,k,2)
                vL = f_qp_left(i,j,k,3)
                wL = f_qp_left(i,j,k,4)
                pL = f_qp_left(i,j,k,5)

                ! ---- right face quantities ----
                rR = f_qp_right(i,j,k,1)
                uR = f_qp_right(i,j,k,2)
                vR = f_qp_right(i,j,k,3)
                wR = f_qp_right(i,j,k,4)
                pR = f_qp_right(i,j,k,5)

                !-- calculated quntaties --
                ! ---- total enthalpy ----
                HL = (0.5*(uL*uL + vL*vL + wL*wL)) + ((gm/(gm - 1.))*pL/rL)
                HR = (0.5*(uR*uR + vR*vR + wR*wR)) + ((gm/(gm - 1.))*pR/rR)

                ! ---- face normal velocity ----
                VnL = uL*nx(i, j, k) + vL*ny(i, j, k) + wL*nz(i, j, k)
                VnR = uR*nx(i, j, k) + vR*ny(i, j, k) + wR*nz(i, j, k)

                ! ---- speed of sound ----
                cL = sqrt(gm*pL/rL)
                cR = sqrt(gm*pR/rR)
                C  = 0.5*(cL + cR)

                ! ---- Mach at face ----
                ML = VnL/C
                MR = VnR/C

                ! ---- switch for supersonic flow ----
                alphaL= max(0, 1-floor(abs(ML)))
                alphaR= max(0, 1-floor(abs(MR)))

                
                ! Compute '+' direction quantities
                FmL   = (0.5*(1.0+sign(1.0, ML))*(1.0 - alphaL)*ML) + alphaL*0.25*((1.0+ML)**2)
                betaL = (0.5*(1.0+sign(1.0, ML))*(1.0 - alphaL))    + alphaL*0.25*((1.0+ML)**2) * (2.0 - ML)

                ! Compute '-' direction quantities
                FmR   = (0.5*(1.0-sign(1.0, MR))*(1.0 - alphaR)*MR) - alphaR*0.25*((1.0-MR)**2)
                betaR = (0.5*(1.0-sign(1.0, MR))*(1.0 - alphaR))    + alphaR*0.25*((1.0-MR)**2)*(2.0 + MR)
                
                Mface = FmL + FmR

                ! -- mass --
                ! AUSM modification             
                if(Mface>0.0)then
                    F_plus(1) = Mface*c*(rL)
                    F_minus(1) = 0.0
                else
                    F_minus(1) = Mface*c*(rR)
                    F_plus(1) = 0.0
                end if
                F_plus(1)  = F_plus(1) *(i_f*make_F_flux_zero(i) &
                                       + j_f*make_G_flux_zero(j) &
                                       + k_f*make_H_flux_zero(k))
                F_minus(1) = F_minus(1)*(i_f*make_F_flux_zero(i) &
                                       + j_f*make_G_flux_zero(j) &
                                       + k_f*make_H_flux_zero(k))


                ! F plus mass flux
                ! Construct other fluxes in terms of the F mass flux
                !F_plus(1) = 0.5*(mass + abs(mass))
                F_plus(2) = (F_plus(1) * uL)
                F_plus(3) = (F_plus(1) * vL)
                F_plus(4) = (F_plus(1) * wL)
                F_plus(5) = (F_plus(1) * HL)
                
                ! F minus mass flux
                ! Construct other fluxes in terms of the F mass flux
                !F_minus(1) = 0.5*(mass - abs(mass))
                F_minus(2) = (F_minus(1) * uR)
                F_minus(3) = (F_minus(1) * vR)
                F_minus(4) = (F_minus(1) * wR)
                F_minus(5) = (F_minus(1) * HR)

                !! -- Turbulence variables mass flux --
                if(n_var>5) then
                  F_plus(6:)  = F_Plus(1)  * f_qp_left(i,j,k,6:)
                  F_minus(6:) = F_minus(1) * f_qp_right(i,j,k,6:)
                end if

                ! total flux
                flux_p(i, j, k, :) = F_plus(:) + F_minus(:)

                ! -- Pressure --
                pbar = (betaL + betaR)*0.5*(pL+pR)

                ! Get the total flux for a face
                ! -- Pressure flux addition --
                flux_p(i, j, K, 2) = flux_p(i, j, k, 2) + (pbar * nx(i, j, k))
                flux_p(i, j, K, 3) = flux_p(i, j, k, 3) + (pbar * ny(i, j, k))
                flux_p(i, j, K, 4) = flux_p(i, j, k, 4) + (pbar * nz(i, j, k))

                flux_p(i, j, k, :) = flux_p(i, j, k, :)*fA(i,j,k)
              end do
             end do
            end do 

        end subroutine compute_flux

        subroutine compute_fluxes()
            
            implicit none
            
            call dmsg(1, 'slau', 'compute_fluxes')

            call compute_flux('x')
            if (any(isnan(F))) then
                call dmsg(5, 'slau', 'compute_residue', 'ERROR: F flux Nan detected')
                stop
            end if    

            call compute_flux('y')
            if (any(isnan(G))) then 
                call dmsg(5, 'slau', 'compute_residue', 'ERROR: G flux Nan detected')
                stop
            end if    
            
            if(kmx==2) then
              H = 0.
            else
              call compute_flux('z')
            end if
            if (any(isnan(H))) then
                call dmsg(5, 'slau', 'compute_residue', 'ERROR: H flux Nan detected')
                stop
            end if

        end subroutine compute_fluxes

        subroutine get_residue()
            !-----------------------------------------------------------
            ! Compute the residue for the slau scheme
            !-----------------------------------------------------------

            implicit none
            
            integer :: i, j, k, l

            call dmsg(1, 'slau', 'compute_residue')

            do l = 1, n_var
             do k = 1, kmx - 1
              do j = 1, jmx - 1
               do i = 1, imx - 1
               residue(i, j, k, l) = (F(i+1, j, k, l) - F(i, j, k, l)) &
                                   + (G(i, j+1, k, l) - G(i, j, k, l)) &
                                   + (H(i, j, k+1, l) - H(i, j, k, l))
               end do
              end do
             end do
            end do
        
        end subroutine get_residue

end module ausmUP