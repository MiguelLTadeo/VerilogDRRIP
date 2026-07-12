// =============================================================================
// measure_l2_drrip_tb.v
// Wrapper de topo: mede hit rate na config de ENTREGA L2 do Apendice B
// (32KB, bloco 64B, 8-way -> ADDR_W=32, BLK_B=64, SETS=64, WAYS=8) com a
// politica DRRIP (repl_drrip.v), parametros de FABRICA (fieis ao paper):
// RRPV_BITS=2, BRRIP_THROTTLE_BITS=5 (1/32), PSEL_BITS=10, SDM_SEL_BITS=4
// (1/16 de cada lado para SETS=64) -- MESMO mapeamento SDM do L1, ja que
// ambos tem SETS=64 (o mapeamento so depende do INDEX_W, nao de WAYS).
//
// Trace: tb/traces/entrega_smoke.txt (ver nota em measure_l1_lru_tb.v).
// EXPECTED_ACCESSES/EXPECTED_HITS ficam nos defaults -1 (sem checagem
// automatica) -- Fase 9 traz os benchmarks reais e a tabela comparativa.
//
// Como compilar/simular: vsim -c -do sim/run_measure_l2_drrip.do
// =============================================================================

`timescale 1ns/1ps

module measure_l2_drrip_tb;

    measure_harness #(
        .ADDR_W              (32),
        .BLK_B               (64),
        .SETS                (64),
        .WAYS                (8),
        .USE_DRRIP           (1),
        .RRPV_BITS           (2),
        .BRRIP_THROTTLE_BITS (5),
        .PSEL_BITS           (10),
        .SDM_SEL_BITS        (4),
        .TRACE_FILE          ("tb/traces/entrega_smoke.txt")
    ) u_measure ();

endmodule
