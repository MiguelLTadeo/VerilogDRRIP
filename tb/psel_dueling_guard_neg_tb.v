// =============================================================================
// psel_dueling_guard_neg_tb.v
// PI4 UNIPAMPA - teste NEGATIVO dedicado para o guard de elaboracao de
// psel_dueling.v que exige PSEL_BITS >= 2.
//
// *** ESTE TESTBENCH E PROJETADO PARA FALHAR NA ELABORACAO. ***
// Isso NAO e um bug deste arquivo: e o proprio artefato que prova que o
// guard de elaboracao (generate/if PSEL_BITS<2 -> instancia de modulo
// inexistente, ver rtl/psel_dueling.v) FUNCIONA de fato, e nao so "no
// papel". Mesmo padrao de tb/repl_srrip_guard_neg_tb.v (Fase 3) e
// tb/repl_brrip_guard_neg_tb.v (Fase 4), adaptado para o parametro deste
// modulo (PSEL_BITS).
//
// NAO faz parte do fluxo normal de simulacao (run_psel_dueling.do) -- e
// compilado/rodado SOMENTE por sim/run_psel_dueling_guard_neg.do, que trata
// "elaboracao falhou" como o resultado de SUCESSO deste teste (ver
// cabecalho daquele script para os detalhes de como isso e verificado).
//
// Como compilar/simular manualmente no ModelSim (a partir de
// /home/miguel/verilog) -- espera-se erro fatal de elaboracao, NAO um
// "RESULTADO: PASS" no estilo dos outros testbenches deste projeto:
//
//   vlib work
//   vlog rtl/psel_dueling.v tb/psel_dueling_guard_neg_tb.v
//   vsim -c work.psel_dueling_guard_neg_tb -do "run -all; quit -f"
//   -> comando `vsim` deve terminar com exit code != 0 (erro de elaboracao,
//      "design unit was not found" / "Error loading design" apontando para
//      psel_dueling_requires_psel_bits_ge_2_do_not_instantiate_with_other_config)
//
// (ou use o script pronto: `vsim -c -do sim/run_psel_dueling_guard_neg.do`)
// =============================================================================

`timescale 1ns/1ps

module psel_dueling_guard_neg_tb;

    // instancia INVALIDA de proposito: PSEL_BITS=1 viola o pre-requisito
    // documentado no cabecalho de rtl/psel_dueling.v (PSEL_BITS>=2). A
    // elaboracao desta instancia deve abortar com erro fatal -- se isso NAO
    // acontecer (ou seja, se a simulacao chegar a rodar e imprimir qualquer
    // coisa), o guard de elaboracao esta QUEBRADO e este teste deve ser
    // considerado FALHO (ver script .do para como isso e verificado de
    // forma automatizavel).
    localparam PSEL_BITS_NEG = 1; // <-- valor invalido de proposito

    reg  clk_neg;
    reg  rst_neg;
    reg  miss_srrip_i_neg;
    reg  miss_brrip_i_neg;
    wire follower_use_brrip_o_neg;
    wire [PSEL_BITS_NEG-1:0] psel_o_neg; // porta de debug (ressalva #1); so importa p/ conectar a porta -- a elaboracao deve abortar antes de qualquer valor ser observado

    psel_dueling #(
        .PSEL_BITS (PSEL_BITS_NEG) // <-- dispara o guard de elaboracao esperado
    ) u_dut_invalido (
        .clk                  (clk_neg),
        .rst                  (rst_neg),
        .miss_srrip_i         (miss_srrip_i_neg),
        .miss_brrip_i         (miss_brrip_i_neg),
        .follower_use_brrip_o (follower_use_brrip_o_neg),
        .psel_o               (psel_o_neg)
    );

    // Se, por algum motivo, a elaboracao NAO falhar (guard quebrado), este
    // bloco chega a rodar e imprime um veredito claramente NEGATIVO -- para
    // que mesmo uma leitura manual do log (sem depender so do exit code do
    // vsim) deixe evidente que o guard falhou em bloquear a config invalida.
    initial begin
        clk_neg          = 1'b0;
        rst_neg          = 1'b1;
        miss_srrip_i_neg = 1'b0;
        miss_brrip_i_neg = 1'b0;
        $display("==================================================================");
        $display("FALHA DO GUARD: psel_dueling elaborou com PSEL_BITS=1 sem erro fatal.");
        $display("Isto e um FAIL deste teste negativo -- o guard de elaboracao em");
        $display("rtl/psel_dueling.v (generate/if PSEL_BITS<2) deveria ter abortado");
        $display("a elaboracao antes de chegar aqui.");
        $display("==================================================================");
        $finish;
    end

endmodule
