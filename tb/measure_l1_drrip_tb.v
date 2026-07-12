// =============================================================================
// measure_l1_drrip_tb.v
// Wrapper de topo: mede hit rate na config de ENTREGA L1 do Apendice B
// (4KB, bloco 32B, 2-way -> ADDR_W=32, BLK_B=32, SETS=64, WAYS=2) com a
// politica DRRIP (repl_drrip.v), parametros de FABRICA (fieis ao paper,
// ver rtl/repl_drrip.v): RRPV_BITS=2, BRRIP_THROTTLE_BITS=5 (1/32),
// PSEL_BITS=10, SDM_SEL_BITS=4 (1/16 de cada lado para SETS=64).
//
// Trace: tb/traces/entrega_smoke.txt (ver nota em measure_l1_lru_tb.v --
// smoke test sintetico, so prova que roda sem erro nesta escala; Fase 9
// traz os benchmarks reais). EXPECTED_ACCESSES/EXPECTED_HITS ficam nos
// defaults -1 (sem checagem automatica).
//
// Como compilar/simular: vsim -c -do sim/run_measure_l1_drrip.do
// =============================================================================

`timescale 1ns/1ps

module measure_l1_drrip_tb;

    measure_harness #(
        .ADDR_W              (32),
        .BLK_B               (32),
        .SETS                (64),
        .WAYS                (2),
        .USE_DRRIP           (1),
        .RRPV_BITS           (2),
        .BRRIP_THROTTLE_BITS (5),
        .PSEL_BITS           (10),
        .SDM_SEL_BITS        (4),
        .TRACE_FILE          ("tb/traces/entrega_smoke.txt")
    ) u_measure ();

endmodule
