module mapping

  use global, only: MAP_FILE_UNIT
  use global, only: mapfile

  use global_vars, only: total_process
  use global_vars, only: process_id

  use utils      , only: DEBUG_LEVEL
  use utils      , only: dmsg
  use string
  use fclose     , only: close_file

  !map variablews
  use global_vars, only: imx
  use global_vars, only: jmx
  use global_vars, only: kmx
  use global_vars, only: otherface
  use global_vars, only: dir_switch

  implicit none
  private
  integer, dimension(6), private :: ilo
  integer, dimension(6), private :: jlo
  integer, dimension(6), private :: klo
  integer, dimension(6), private :: ihi
  integer, dimension(6), private :: jhi
  integer, dimension(6), private :: khi

  integer, dimension(6), public :: Pilo
  integer, dimension(6), public :: Pjlo
  integer, dimension(6), public :: Pklo
  integer, dimension(6), public :: Pihi
  integer, dimension(6), public :: Pjhi
  integer, dimension(6), public :: Pkhi

  integer, dimension(6), public :: PiDir
  integer, dimension(6), public :: PjDir
  integer, dimension(6), public :: PkDir

  integer, dimension(6), public :: Gilo
  integer, dimension(6), public :: Gjlo
  integer, dimension(6), public :: Gklo
  integer, dimension(6), public :: Gihi
  integer, dimension(6), public :: Gjhi
  integer, dimension(6), public :: Gkhi
  
  integer, dimension(6), public :: mpi_class=-1

  public :: read_interface_map

    contains

      subroutine read_interface_map()
        implicit none
        integer :: ios
        integer :: max_call

        integer :: i
        integer :: b1,b2,f1,f2
        integer :: s11,s12,s21,s22
        integer :: e11,e12,e21,e22
        integer :: switch
        integer :: class
        !--- initialize indicies --!
        max_call = total_process*6
        ilo(1) = 1  ; ihi(1) = 1
        ilo(2) = imx; ihi(2) = imx
        ilo(3) = 1  ; ihi(3) = imx
        ilo(4) = 1  ; ihi(4) = imx
        ilo(5) = 1  ; ihi(5) = imx
        ilo(6) = 1  ; ihi(6) = imx

        jlo(1) = 1  ; jhi(1) = jmx
        jlo(2) = 1  ; jhi(2) = jmx
        jlo(3) = 1  ; jhi(3) = 1
        jlo(4) = jmx; jhi(4) = jmx
        jlo(5) = 1  ; jhi(5) = jmx
        jlo(6) = 1  ; jhi(6) = jmx

        klo(1) = 1  ; khi(1) = kmx
        klo(2) = 1  ; khi(2) = kmx
        klo(3) = 1  ; khi(3) = kmx
        klo(4) = 1  ; khi(4) = kmx
        klo(5) = 1  ; khi(5) = 1
        klo(6) = kmx; khi(6) = kmx

        otherface(1)=2
        otherface(2)=1
        otherface(3)=4
        otherface(4)=3
        otherface(5)=6
        otherface(6)=5
        !--- end of variable intializaiton --!

        !--- reading map file  ---!

        open(MAP_FILE_UNIT, file=mapfile, status='old', action='read')
        read(MAP_FILE_UNIT,*) ! ignore header
        do i=1,max_call
          read(MAP_FILE_UNIT,*, iostat=ios) b1,f1,s11,e11,s12,e12,&
                                            b2,f2,s21,e21,s22,e22,switch,class
          if(is_iostat_end(ios)) EXIT
          if(b1==process_id)then
            if(f1==1) then
              otherface(1)=f2
              jlo(1)=s21
              jhi(1)=e21
              klo(1)=s22
              khi(1)=e22
              dir_switch(1)=switch
              mpi_class(1)=class
            elseif(f1==2) then
              otherface(2)=f2
              jlo(2)=s21
              jhi(2)=e21
              klo(2)=s22
              khi(2)=e22
              dir_switch(2)=switch
              mpi_class(2)=class
            elseif(f1==3) then
              otherface(3)=f2
              ilo(3)=s21
              ihi(3)=e21
              klo(3)=s22
              khi(3)=e22
              dir_switch(3)=switch
              mpi_class(3)=class
            elseif(f1==4) then
              otherface(4)=f2
              ilo(4)=s21
              ihi(4)=e21
              klo(4)=s22
              khi(4)=e22
              dir_switch(4)=switch
              mpi_class(4)=class
            elseif(f1==5) then
              otherface(5)=f2
              ilo(5)=s21
              ihi(5)=e21
              jlo(5)=s22
              jhi(5)=e22
              dir_switch(5)=switch
              mpi_class(5)=class
            elseif(f1==6) then
              otherface(6)=f2
              ilo(6)=s21
              ihi(6)=e21
              jlo(6)=s22
              jhi(6)=e22
              dir_switch(6)=switch
              mpi_class(6)=class
            end if
          else 
            continue
          end if
        end do

        call close_file(MAP_FILE_UNIT)
        call change_map_to_particular_range()
        print*, "MPI_CLASS:", mpi_class
      end subroutine read_interface_map

      subroutine change_map_to_particular_range()
        !-------------------------------------
        !eg: 1-kmx to 0 to kmx for data transfer
        !--------------------------------------
        implicit none
        integer :: i
        Pilo=ilo
        Pjlo=jlo
        Pklo=klo
        Pihi=ihi
        Pjhi=jhi
        Pkhi=khi
        PiDir=1
        PjDir=1
        PkDir=1
        do i=1,6
          if(ilo(i)==1 .and. i>2)then
            Pilo(i)=1
            Gilo(i)=-2
          end if
          if(jlo(i)==1 .and. (i>4 .or.i<3) )then
            Pjlo(i)=1
            Gjlo(i)=-2
          end if
          if(klo(i)==1 .and. i<5)then
            Pklo(i)=1
            Gklo(i)=-2
          end if
          if(ihi(i)==1 .and. i>2)then
            Pihi(i)=1          
            Gihi(i)=-2         
            PiDir(i)=-1
          end if               
          if(jhi(i)==1 .and. (i>4 .or. i<3))then
            Pjhi(i)=1          
            Gjhi(i)=-2          
            PjDir(i)=-1
          end if               
          if(khi(i)==1 .and. i<5)then
            Pkhi(i)=1
            Gkhi(i)=-2
            PkDir(i)=-1
          end if
          if(ilo(i)>1 .and. i>2) then
            Gilo(i)=ilo(i)+3
            Pilo(i)=ilo(i)-1
            PiDir(i)=-1
          end if
          if(jlo(i)>1 .and. (i>4 .or. i<5)) then
            Gjlo(i)=jlo(i)+3
            Pjlo(i)=jlo(i)-1
            PjDir(i)=-1
          end if
          if(klo(i)>1 .and. i<5) then
            Gklo(i)=klo(i)+3
            Pklo(i)=klo(i)-1
            PkDir(i)=-1
          end if
          if(ihi(i)>1 .and. i>2) then
            Gihi(i)=ihi(i)+3
            Pihi(i)=ihi(i)-1
          end if
          if(jhi(i)>1 .and. (i>4 .or. i<5)) then
            Gjhi(i)=jhi(i)+3
            Pjhi(i)=jhi(i)-1
          end if
          if(khi(i)>1 .and. i<5) then
            Gkhi(i)=khi(i)+3
            Pkhi(i)=khi(i)-1
          end if
        end do
        
      end subroutine change_map_to_particular_range
          


end module mapping
