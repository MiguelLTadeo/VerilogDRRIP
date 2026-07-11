# run_repl_lru.do
# Script do ModelSim para compilar e simular o testbench de repl_lru.
# Assume que o diretorio de trabalho corrente do vsim/vlib e
# /home/miguel/verilog (ou seja, a raiz do projeto).
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_repl_lru.do
# ou, dentro do ModelSim GUI (com cwd = /home/miguel/verilog):
#   do sim/run_repl_lru.do

# limpa qualquer lib work de uma rodada anterior ANTES de recriar, para
# que um rerun nunca misture binario compilado antigo com o RTL atual
# (evita mascarar um FAIL por estar rodando codigo obsoleto na lib).
if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/repl_lru.v tb/repl_lru_tb.v
vsim -c work.repl_lru_tb
run -all
quit -f
