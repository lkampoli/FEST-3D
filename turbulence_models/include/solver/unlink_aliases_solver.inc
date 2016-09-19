!include in solver.f90

      select case (turbulence)

          case ("none")
              !include nothing
              continue

          case ("sst")
              include "turbulence_models/sst/solver/unlink_aliases_solver.inc"

          case DEFAULT
              call dmsg(5, "turbulence_models/include/state", "unlink_aliases_solver", &
                        "ERROR: Turbulence model not recognised")
              STOP

      end select