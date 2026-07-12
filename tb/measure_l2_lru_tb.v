// =============================================================================
// measure_l2_lru_tb.v
// Wrapper de topo: mede hit rate na config de ENTREGA L2 do Apendice B
// (32KB, bloco 64B, 8-way -> ADDR_W=32, BLK_B=64, SETS=64, WAYS=8 ->
// OFFSET_W=6, INDEX_W=6, TAG_W=20) com a politica LRU (repl_lru_nway.v,
// matricial, Fase 7 -- unico modulo LRU deste projeto que suporta 8-way).
//
// Trace: tb/traces/entrega_smoke.txt (ver nota em measure_l1_lru_tb.v --
// smoke test sintetico, mesmo arquivo reusado do L1: ambos ADDR_W=32/
// SETS=64, o unico endereco que muda de interpretacao entre L1/L2 e o
// OFFSET_W, o que nao afeta a validade do arquivo como entrada). Fase 9
// traz os benchmarks reais. EXPECTED_ACCESSES/EXPECTED_HITS ficam nos
// defaults -1 (sem checagem automatica).
//
// Como compilar/simular: vsim -c -do sim/run_measure_l2_lru.do
// =============================================================================

`timescale 1ns/1ps

module measure_l2_lru_tb;

    measure_harness #(
        .ADDR_W     (32),
        .BLK_B      (64),
        .SETS       (64),
        .WAYS       (8),
        .USE_DRRIP  (0),
        .TRACE_FILE ("tb/traces/entrega_smoke.txt")
    ) u_measure ();

endmodule
