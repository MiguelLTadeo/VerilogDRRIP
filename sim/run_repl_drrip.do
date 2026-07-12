# run_repl_drrip.do
# Script do ModelSim para compilar e simular o testbench de repl_drrip.
# Assume que o diretorio de trabalho corrente do vsim/vlib e
# /home/miguel/verilog (ou seja, a raiz do projeto).
#
# repl_drrip.v INSTANCIA psel_dueling.v internamente (ver DECISAO DE
# PROJETO no cabecalho de rtl/repl_drrip.v: reusa o PSEL da Fase 5 em vez
# de reimplementar) -- por isso o vlog abaixo compila os DOIS arquivos de
# rtl/, na ordem (psel_dueling.v primeiro, ainda que o ModelSim normalmente
# resolva dependencias entre arquivos da mesma chamada de vlog independente
# de ordem; mantida por clareza de leitura).
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_repl_drrip.do
# ou, dentro do ModelSim GUI (com cwd = /home/miguel/verilog):
#   do sim/run_repl_drrip.do

# limpa qualquer lib work de uma rodada anterior ANTES de recriar, para
# que um rerun nunca misture binario compilado antigo com o RTL atual
# (evita mascarar um FAIL por estar rodando codigo obsoleto na lib).
if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/psel_dueling.v rtl/repl_drrip.v tb/repl_drrip_tb.v
vsim -c work.repl_drrip_tb
run -all
quit -f
