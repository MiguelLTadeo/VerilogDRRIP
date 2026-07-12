// =============================================================================
// measure_val_lru_tb.v
// Wrapper de topo: mede hit rate na config de VALIDACAO do plano
// (ADDR_W=8, BLK_B=4, SETS=4, WAYS=2) com a politica LRU (repl_lru_nway.v)
// plugada em cache_datapath.v via measure_harness.v.
//
// Este e o teste que PROVA O HARNESS EM SI: tb/traces/val_smoke.txt foi
// construido de proposito para NUNCA exigir uma decisao de vitima real --
// cada um dos 4 sets so recebe, ao longo de TODO o trace, no MAXIMO 2 tags
// distintas (exatamente WAYS=2), entao NENHUMA decisao de eviction/vitima
// jamais e disparada. Isso significa que o hit/miss esperado e
// IDENTICO independente de qual politica estiver plugada (LRU ou DRRIP) --
// o objetivo aqui NAO e revalidar a politica (ja validada nas Fases 2-8
// parte1), e sim provar que o HARNESS conta hits/misses corretamente.
//
// Calculo manual do trace (ver tb/traces/val_smoke.txt, 18 linhas):
//   enderecos {tag,index,offset}: 0x10/0x20 no set0(idx=00),
//   0x14/0x24 no set1(idx=01), 0x18/0x28 no set2(idx=10),
//   0x1C/0x2C no set3(idx=11) -- offset=2 bits (BLK_B=4), sempre 0x0.
//   Sequencia: (miss,miss,hit,hit) em cada 1 dos 4 sets [16 acessos: 8
//   misses (compulsorios, 1o toque de cada endereco) + 8 hits imediatos],
//   seguido de 1 hit extra por set relendo o 2o endereco de cada set em
//   ordem embaralhada (+4 hits), fechando com 2 hits finais re-lendo os
//   2 primeiros enderecos (set0). Total: 18 acessos, 8 misses, 10 hits.
//   HIT RATE = 10/18 = 55.556%.
//
// Como compilar/simular: vsim -c -do sim/run_measure_val_lru.do
// =============================================================================

`timescale 1ns/1ps

module measure_val_lru_tb;

    measure_harness #(
        .ADDR_W            (8),
        .BLK_B             (4),
        .SETS              (4),
        .WAYS              (2),
        .USE_DRRIP         (0),
        .TRACE_FILE        ("tb/traces/val_smoke.txt"),
        .EXPECTED_ACCESSES (18),
        .EXPECTED_HITS     (10)
    ) u_measure ();

endmodule
