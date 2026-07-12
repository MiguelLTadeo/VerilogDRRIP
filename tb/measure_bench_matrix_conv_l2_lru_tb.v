// =============================================================================
// measure_bench_matrix_conv_l2_lru_tb.v
// GERADO por bench/gen_measure_wrappers.py -- Fase 9 (bench_traces + run
// comparativo). NAO EDITAR A MAO: para mudar algo, edite o gerador e rode
// `python3 bench/gen_measure_wrappers.py` de novo (idempotente).
//
// Mede hit rate do benchmark real do Apendice A "Convolucao 2D (reuso em janela)"
// na config de ENTREGA L2 do Apendice B
// (L2 (unif.): 32KB, bloco 64B, 8-way -> SETS=64, WAYS=8, OFFSET=6 INDEX=6 TAG=20) com politica LRU (repl_lru_nway.v, matricial, unico modulo LRU do projeto que cobre tanto 2-way quanto 8-way).
//
// Trace: tb/traces/bench_matrix_conv.txt (gerado por bench/apendice_a_instrumented.c, ver
// cabecalho la para o esquema de enderecamento sintetico e as escalas
// usadas). EXPECTED_ACCESSES/EXPECTED_HITS ficam nos defaults -1 (sem
// checagem automatica) -- o resultado desta rodada E o dado comparativo
// (ver resultados/hit_rate_comparativo.md).
//
// Como compilar/simular: vsim -c -do sim/run_measure_bench_matrix_conv_l2_lru.do
// (executar a partir da raiz do repo, /home/miguel/verilog)
// =============================================================================

`timescale 1ns/1ps

module measure_bench_matrix_conv_l2_lru_tb;

    measure_harness #(
        .ADDR_W     (32),
        .BLK_B      (64),
        .SETS       (64),
        .WAYS       (8),
        .USE_DRRIP  (0),
        .TRACE_FILE ("tb/traces/bench_matrix_conv.txt")
    ) u_measure ();

endmodule
