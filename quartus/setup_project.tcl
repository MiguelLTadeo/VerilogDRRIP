# setup_project.tcl
# Cria/atualiza o projeto Quartus deste repositorio via linha de comando
# (quartus_sh -t setup_project.tcl), sem precisar abrir a GUI.
#
# Uso (a partir de quartus/, com quartus_sh no PATH):
#   quartus_sh -t setup_project.tcl
#
# Depois de rodar isso 1 vez, o projeto (cache_pi4.qpf/.qsf) fica pronto
# pra abrir na GUI do Quartus normalmente, ou pra rodar so a etapa de
# Analysis & Synthesis via linha de comando com:
#   quartus_map cache_pi4

package require ::quartus::project

set project_name "cache_pi4"

# Device alvo REAL do projeto (Apendice B / agentes do repo): Cyclone III
# EP3C25F324C6. ATENCAO -- rodar quartus_map de fato exige que o PACOTE
# DE SUPORTE DE DISPOSITIVO desta familia esteja instalado (nao so o
# software Quartus). Nesta maquina, `/home/miguel/intelFPGA_lite/20.1/
# devdata` esta VAZIO -- nenhum pacote de dispositivo instalado, de
# NENHUMA familia (nem Cyclone III, nem nenhuma outra) -- entao
# Analysis & Synthesis nao roda ainda, mesmo que o projeto/RTL estejam
# 100% corretos. Alem disso, Cyclone III especificamente exige o Quartus
# II LEGADO (ate a versao 13.0sp1) -- o Quartus Prime (18.x em diante,
# incluindo este 20.1) descontinuou suporte a essa familia. Ver o guia
# GUIA_SIMULACAO_SINTESE.md na raiz do repo pra instrucoes completas de
# instalacao do pacote de dispositivo antes de rodar quartus_map.
set family       "Cyclone III"
set device       "EP3C25F324C6"

if {[project_exists $project_name]} {
    project_open $project_name
} else {
    project_new $project_name -overwrite
}

set_global_assignment -name FAMILY $family
set_global_assignment -name DEVICE $device
set_global_assignment -name TOP_LEVEL_ENTITY cache_datapath

# todos os modulos RTL sintetizaveis do projeto (rtl/*.v) -- adiciona
# TODOS de uma vez, mesmo que so 1 seja o TOP_LEVEL_ENTITY corrente:
# assim trocar TOP_LEVEL_ENTITY (ex. pra repl_drrip, repl_lru_nway, etc.)
# no .qsf ou na GUI nao exige re-adicionar arquivo nenhum.
foreach f [glob -nocomplain ../rtl/*.v] {
    set_global_assignment -name VERILOG_FILE $f
}

export_assignments
project_close
