!should be included in state file, in subroutine name same as this file name 
         
              call dmsg(1, 'turbulence_models/sst/state', 'init_infinity_values')
              tk_inf = 1.5*((0.05**2)*&
                            (x_speed_inf**2+&
                             y_speed_inf**2+&
                             z_speed_inf**2))
              tw_inf = tk_inf/(mu_ref*0.001)