// =============================================================================
// repl_srrip_guard_neg_tb.v
// PI4 UNIPAMPA - teste NEGATIVO dedicado (ressalva MENOR #2 da revisao
// rtl-analyst da Fase 3) para o guard de elaboracao de repl_srrip.v que
// exige RRPV_BITS >= 1.
//
// *** ESTE TESTBENCH E PROJETADO PARA FALHAR NA ELABORACAO. ***
// Isso NAO e um bug deste arquivo: e o proprio artefato que prova que o
// guard de elaboracao (generate/if RRPV_BITS<1 -> instancia de modulo
// inexistente, ver rtl/repl_srrip.v) FUNCIONA de fato, e nao so "no papel".
//
// NAO faz parte do fluxo normal de simulacao (run_repl_srrip.do) -- e
// compilado/rodado SOMENTE por sim/run_repl_srrip_guard_neg.do, que trata
// "elaboracao falhou" como o resultado de SUCESSO deste teste (ver
// cabecalho daquele script para os detalhes de como isso e verificado).
//
// Como compilar/simular manualmente no ModelSim (a partir de
// /home/miguel/verilog) -- espera-se erro fatal de elaboracao, NAO um
// "RESULTADO: PASS" no estilo dos outros testbenches deste projeto:
//
//   vlib work
//   vlog rtl/repl_srrip.v tb/repl_srrip_guard_neg_tb.v
//   vsim -c work.repl_srrip_guard_neg_tb -do "run -all; quit -f"
//   -> comando `vsim` deve terminar com exit code != 0 (erro de elaboracao,
//      "design unit was not found" / "Error loading design" apontando para
//      repl_srrip_requires_rrpv_bits_ge_1_do_not_instantiate_with_other_config)
//
// (ou use o script pronto: `vsim -c -do sim/run_repl_srrip_guard_neg.do`)
// =============================================================================

`timescale 1ns/1ps

module repl_srrip_guard_neg_tb;

    // instancia INVALIDA de proposito: RRPV_BITS=0 viola o pre-requisito
    // documentado no cabecalho de repl_srrip.v (RRPV_BITS>=1). A elaboracao
    // desta instancia deve abortar com erro fatal -- se isso NAO acontecer
    // (ou seja, se a simulacao chegar a rodar e imprimir qualquer coisa),
    // o guard de elaboracao esta QUEBRADO e este teste deve ser considerado
    // FALHO (ver script .do para como isso e verificado de forma
    // automatizavel).
    localparam SETS_NEG      = 4;
    localparam WAYS_NEG      = 2;
    localparam RRPV_BITS_NEG = 0; // <-- valor invalido de proposito

    reg                          clk_neg;
    reg                          rst_neg;
    reg                          hit_en_i_neg;
    reg  [0:0]                   hit_way_i_neg;
    reg  [$clog2(SETS_NEG)-1:0]  hit_index_i_neg;
    reg                          fill_en_i_neg;
    reg  [0:0]                   fill_way_i_neg;
    reg  [$clog2(SETS_NEG)-1:0]  fill_index_i_neg;
    reg                          victim_req_i_neg;
    reg  [$clog2(SETS_NEG)-1:0]  victim_index_i_neg;
    wire                         victim_busy_o_neg;
    wire                         victim_valid_o_neg;
    wire [0:0]                   victim_way_o_neg;
    reg  [0:0]                   rd_way_i_neg;
    reg  [$clog2(SETS_NEG)-1:0]  rd_index_i_neg;
    wire                         rd_rrpv_o_neg; // RRPV_BITS_NEG==0 -> largura degenerada, so importa p/ conectar a porta

    repl_srrip #(
        .SETS      (SETS_NEG),
        .WAYS      (WAYS_NEG),
        .RRPV_BITS (RRPV_BITS_NEG) // <-- dispara o guard de elaboracao esperado
    ) u_dut_invalido (
        .clk             (clk_neg),
        .rst             (rst_neg),
        .hit_en_i        (hit_en_i_neg),
        .hit_way_i       (hit_way_i_neg),
        .hit_index_i     (hit_index_i_neg),
        .fill_en_i       (fill_en_i_neg),
        .fill_way_i      (fill_way_i_neg),
        .fill_index_i    (fill_index_i_neg),
        .victim_req_i    (victim_req_i_neg),
        .victim_index_i  (victim_index_i_neg),
        .victim_busy_o   (victim_busy_o_neg),
        .victim_valid_o  (victim_valid_o_neg),
        .victim_way_o    (victim_way_o_neg),
        .rd_way_i        (rd_way_i_neg),
        .rd_index_i      (rd_index_i_neg),
        .rd_rrpv_o       (rd_rrpv_o_neg)
    );

    // Se, por algum motivo, a elaboracao NAO falhar (guard quebrado), este
    // bloco chega a rodar e imprime um veredito claramente NEGATIVO -- para
    // que mesmo uma leitura manual do log (sem depender so do exit code do
    // vsim) deixe evidente que o guard falhou em bloquear a config invalida.
    initial begin
        clk_neg = 1'b0;
        rst_neg = 1'b1;
        $display("==================================================================");
        $display("FALHA DO GUARD: repl_srrip elaborou com RRPV_BITS=0 sem erro fatal.");
        $display("Isto e um FAIL deste teste negativo -- o guard de elaboracao em");
        $display("rtl/repl_srrip.v (generate/if RRPV_BITS<1) deveria ter abortado a");
        $display("elaboracao antes de chegar aqui.");
        $display("==================================================================");
        $finish;
    end

endmodule
