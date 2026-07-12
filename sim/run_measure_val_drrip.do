# run_measure_val_drrip.do
# Script do ModelSim: mede hit rate na config de VALIDACAO (SETS=4) com
# DRRIP (repl_drrip.v) plugado, via measure_harness.v.
# Assume cwd = /home/miguel/verilog (raiz do projeto).
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_measure_val_drrip.do

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/cache_datapath.v rtl/repl_lru_nway.v rtl/psel_dueling.v rtl/repl_drrip.v tb/measure_harness.v tb/measure_val_drrip_tb.v
vsim -c work.measure_val_drrip_tb
run -all
quit -f
