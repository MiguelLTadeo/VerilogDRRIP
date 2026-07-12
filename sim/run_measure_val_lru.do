# run_measure_val_lru.do
# Script do ModelSim: mede hit rate na config de VALIDACAO (SETS=4) com
# LRU (repl_lru_nway.v) plugado, via measure_harness.v.
# Assume que o diretorio de trabalho corrente do vsim/vlib e
# /home/miguel/verilog (ou seja, a raiz do projeto -- os caminhos de trace
# em TRACE_FILE nos wrappers tb/measure_*_tb.v sao relativos a isso).
#
# Compila TODOS os modulos de politica (LRU e DRRIP) mesmo so usando LRU
# aqui -- measure_harness.v referencia os dois dentro de blocos generate
# (so 1 dos 2 e efetivamente ELABORADO conforme USE_DRRIP), mas
# compila-los todos de uma vez mantem os 6 scripts desta fase uniformes e
# elimina qualquer duvida sobre resolucao de modulo em tempo de vlog.
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_measure_val_lru.do

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/cache_datapath.v rtl/repl_lru_nway.v rtl/psel_dueling.v rtl/repl_drrip.v tb/measure_harness.v tb/measure_val_lru_tb.v
vsim -c work.measure_val_lru_tb
run -all
quit -f
