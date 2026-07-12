# run_measure_bench_matrix_conv_l2_drrip.do
# GERADO por bench/gen_measure_wrappers.py -- Fase 9. NAO EDITAR A MAO.
# Script do ModelSim: mede hit rate do benchmark 'matrix_conv' do Apendice A na
# config de ENTREGA L2 com a politica DRRIP, via measure_harness.v.
# Assume cwd = /home/miguel/verilog (raiz do projeto).
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_measure_bench_matrix_conv_l2_drrip.do

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/cache_datapath.v rtl/repl_lru_nway.v rtl/psel_dueling.v rtl/repl_drrip.v tb/measure_harness.v tb/measure_bench_matrix_conv_l2_drrip_tb.v
vsim -c work.measure_bench_matrix_conv_l2_drrip_tb
run -all
quit -f
