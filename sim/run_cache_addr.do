# run_cache_addr.do
# Script do ModelSim para compilar e simular o testbench de cache_addr.
# Assume que o diretorio de trabalho corrente do vsim/vlib e
# /home/miguel/verilog (ou seja, a raiz do projeto).
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_cache_addr.do
# ou, dentro do ModelSim GUI (com cwd = /home/miguel/verilog):
#   do sim/run_cache_addr.do

# limpa qualquer lib work de uma rodada anterior ANTES de recriar, para
# que um rerun nunca misture binario compilado antigo com o RTL atual
# (evita mascarar um FAIL por estar rodando codigo obsoleto na lib).
if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/cache_addr.v tb/cache_addr_tb.v
vsim -c work.cache_addr_tb
run -all
quit -f
