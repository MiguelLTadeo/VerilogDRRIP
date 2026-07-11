# run_repl_brrip.do
# Script do ModelSim para compilar e simular o testbench de repl_brrip.
# Assume que o diretorio de trabalho corrente do vsim/vlib e
# /home/miguel/verilog (ou seja, a raiz do projeto).
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_repl_brrip.do
# ou, dentro do ModelSim GUI (com cwd = /home/miguel/verilog):
#   do sim/run_repl_brrip.do

# limpa qualquer lib work de uma rodada anterior ANTES de recriar, para
# que um rerun nunca misture binario compilado antigo com o RTL atual
# (evita mascarar um FAIL por estar rodando codigo obsoleto na lib).
if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/repl_brrip.v tb/repl_brrip_tb.v
vsim -c work.repl_brrip_tb
run -all
quit -f
