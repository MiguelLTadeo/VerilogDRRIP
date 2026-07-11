# run_psel_dueling.do
# Script do ModelSim para compilar e simular o testbench de psel_dueling.
# Assume que o diretorio de trabalho corrente do vsim/vlib e
# /home/miguel/verilog (ou seja, a raiz do projeto).
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_psel_dueling.do
# ou, dentro do ModelSim GUI (com cwd = /home/miguel/verilog):
#   do sim/run_psel_dueling.do

# limpa qualquer lib work de uma rodada anterior ANTES de recriar, para
# que um rerun nunca misture binario compilado antigo com o RTL atual
# (evita mascarar um FAIL por estar rodando codigo obsoleto na lib).
if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/psel_dueling.v tb/psel_dueling_tb.v
vsim -c work.psel_dueling_tb
run -all
quit -f
