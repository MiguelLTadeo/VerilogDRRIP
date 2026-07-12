# set_top.tcl
# Troca o TOP_LEVEL_ENTITY do projeto cache_pi4 via linha de comando,
# recebendo o nome do modulo como argumento posicional.
#
# Uso: quartus_sh -t set_top.tcl -- <nome_do_modulo>

package require ::quartus::project

set top_name [lindex $quartus(args) 1]

project_open cache_pi4
set_global_assignment -name TOP_LEVEL_ENTITY $top_name
export_assignments
project_close
