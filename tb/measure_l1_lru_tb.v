// =============================================================================
// measure_l1_lru_tb.v
// Wrapper de topo: mede hit rate na config de ENTREGA L1 do Apendice B
// (4KB, bloco 32B, 2-way -> ADDR_W=32, BLK_B=32, SETS=64, WAYS=2 ->
// OFFSET_W=5, INDEX_W=6, TAG_W=21) com a politica LRU (repl_lru_nway.v).
//
// Trace usado: tb/traces/entrega_smoke.txt (SINTETICO/simples, ver
// cabecalho daquele arquivo -- NAO e um benchmark real do Apendice A, so
// prova que o harness RODA sem erro nesta escala e produz um hit rate
// plausivel; os benchmarks de verdade e a tabela comparativa L1/L2 x
// LRU/DRRIP sao a Fase 9). Por isso este wrapper NAO usa
// EXPECTED_ACCESSES/EXPECTED_HITS (fica nos defaults -1 = sem checagem
// automatica) -- so o proprio $display do harness reporta o resultado.
//
// Como compilar/simular: vsim -c -do sim/run_measure_l1_lru.do
// =============================================================================

`timescale 1ns/1ps

module measure_l1_lru_tb;

    measure_harness #(
        .ADDR_W     (32),
        .BLK_B      (32),
        .SETS       (64),
        .WAYS       (2),
        .USE_DRRIP  (0),
        .TRACE_FILE ("tb/traces/entrega_smoke.txt")
    ) u_measure ();

endmodule
