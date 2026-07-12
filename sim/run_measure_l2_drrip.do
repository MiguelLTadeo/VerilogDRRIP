# run_measure_l2_drrip.do
# Script do ModelSim: mede hit rate na config de ENTREGA L2 do Apendice B
# (32KB/64B bloco/8-way -> SETS=64) com DRRIP (repl_drrip.v) plugado, via
# measure_harness.v. Trace sintetico de fumaca (ver
# tb/traces/entrega_smoke.txt) -- Fase 9 traz os benchmarks reais.
# Assume cwd = /home/miguel/verilog (raiz do projeto).
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_measure_l2_drrip.do

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/cache_datapath.v rtl/repl_lru_nway.v rtl/psel_dueling.v rtl/repl_drrip.v tb/measure_harness.v tb/measure_l2_drrip_tb.v
vsim -c work.measure_l2_drrip_tb
run -all
quit -f
