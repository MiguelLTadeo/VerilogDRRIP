# run_measure_l1_lru.do
# Script do ModelSim: mede hit rate na config de ENTREGA L1 do Apendice B
# (4KB/32B bloco/2-way -> SETS=64) com LRU (repl_lru_nway.v) plugado, via
# measure_harness.v. Trace sintetico de fumaca (ver
# tb/traces/entrega_smoke.txt) -- Fase 9 traz os benchmarks reais.
# Assume cwd = /home/miguel/verilog (raiz do projeto).
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_measure_l1_lru.do

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/cache_datapath.v rtl/repl_lru_nway.v rtl/psel_dueling.v rtl/repl_drrip.v tb/measure_harness.v tb/measure_l1_lru_tb.v
vsim -c work.measure_l1_lru_tb
run -all
quit -f
