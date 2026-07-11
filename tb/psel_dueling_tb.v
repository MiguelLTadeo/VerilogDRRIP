// =============================================================================
// psel_dueling_tb.v
// Testbench autoverificavel para psel_dueling.v (Fase 5 - PI4 UNIPAMPA).
//
// Como compilar/simular no ModelSim (a partir de /home/miguel/verilog):
//
//   vlib work
//   vlog rtl/psel_dueling.v tb/psel_dueling_tb.v
//   vsim -c work.psel_dueling_tb -do "run -all; quit -f"
//
// (ou use o script pronto: `vsim -c -do sim/run_psel_dueling.do`)
//
// -----------------------------------------------------------------------
// Por que este testbench NAO instancia cache_addr.v/repl_srrip.v/
// repl_brrip.v (fidelidade ao plano-cache.md, item 5: "valide SEPARADO da
// cache pequena (4 sets nao comportam SDMs reais)"): o psel_dueling.v e
// puramente o contador PSEL + a logica de decisao de politica, alimentado
// aqui DIRETAMENTE por uma sequencia SINTETICA (calculada na mao ANTES de
// escrever este arquivo, ver tabela abaixo) de pulsos miss_srrip_i/
// miss_brrip_i. A integracao real com SDMs mapeados a sets fisicos da
// cache e uma fase futura, fora deste plano.
//
// -----------------------------------------------------------------------
// Config do DUT (config de validacao DESTA FASE, REDUZIDA de proposito):
//   PSEL_BITS=4 -> faixa 0..15, PSEL_MAX=15 (4'b1111), PSEL_MIN=0 (4'b0000),
//   PSEL_RESET=8 (4'b1000, MSB=1, meio exato da faixa par 0..15).
//
//   Por que 4 bits aqui em vez do default de PRODUCAO (PSEL_BITS=10,
//   fidelidade direta ao paper -- faixa 0..1023, reset=512): com 10 bits
//   seriam necessarios ate 512 pulsos consecutivos so para atravessar a
//   faixa inteira e observar as saturacoes -- viavel em hardware real
//   (contador de 10 bits e barato), mas inflaria este testbench sem
//   agregar cobertura nova (o mecanismo -- incrementa/decrementa/satura/
//   MSB decide -- e IDENTICO independente da largura; so o periodo/faixa
//   muda). Reduzir para 4 bits (faixa 0..15) mantem a sequencia de eventos
//   pequena e 100% rastreavel na mao, exercitando saturacao em AMBOS os
//   extremos e a virada do MSB em poucas dezenas de linhas de teste, sem
//   abrir mao de nenhuma garantia estrutural (mesmo hardware, parametro
//   diferente) -- mesmo espirito de BRRIP_THROTTLE_BITS reduzido em
//   tb/repl_brrip_tb.v (ver cabecalho daquele arquivo para o precedente
//   direto desta pratica no projeto).
//
// -----------------------------------------------------------------------
// Convencao (replicada do cabecalho de rtl/psel_dueling.v, necessaria para
// ler a tabela abaixo):
//   miss_brrip_i INCREMENTA o psel; miss_srrip_i DECREMENTA o psel.
//   follower_use_brrip_o = ~MSB. MSB=psel[3] (bit mais significativo, ja
//   que PSEL_BITS=4 -> indice 3).
//
// -----------------------------------------------------------------------
// Valores esperados CALCULADOS NA MAO antes de escrever o codigo (tabela
// completa; "evento" numerado E1..E44 na ordem em que sao aplicados no
// bloco `initial` abaixo; valores em binario de 4 bits entre parenteses
// para deixar o bit MSB explicito):
//
//   RESET inicial:                       psel=8  (1000) MSB=1 foll=0
//
//   ---- (i) SUBIDA: 7x miss_brrip_i, 8->15 --------------------------------
//   E1  B  8->9   (1001) MSB=1 foll=0
//   E2  B  9->10  (1010) MSB=1 foll=0
//   E3  B  10->11 (1011) MSB=1 foll=0
//   E4  B  11->12 (1100) MSB=1 foll=0
//   E5  B  12->13 (1101) MSB=1 foll=0
//   E6  B  13->14 (1110) MSB=1 foll=0
//   E7  B  14->15 (1111) MSB=1 foll=0   <- atingiu PSEL_MAX
//
//   ---- (iii) SATURACAO SUPERIOR: 2x miss_brrip_i alem do teto ------------
//   E8  B  15->15 (1111) trava, sem wraparound. MSB=1 foll=0
//   E9  B  15->15 (1111) trava de novo.          MSB=1 foll=0
//
//   ---- (ii) DESCIDA + (v) VIRADA DO MSB (para baixo): 15x miss_srrip_i ---
//   E10 S  15->14 (1110) MSB=1 foll=0
//   E11 S  14->13 (1101) MSB=1 foll=0
//   E12 S  13->12 (1100) MSB=1 foll=0
//   E13 S  12->11 (1011) MSB=1 foll=0
//   E14 S  11->10 (1010) MSB=1 foll=0
//   E15 S  10->9  (1001) MSB=1 foll=0
//   E16 S  9->8   (1000) MSB=1 foll=0
//   E17 S  8->7   (0111) MSB=0 foll=1   <-- VIRADA DO MSB (8->7, item v)
//   E18 S  7->6   (0110) MSB=0 foll=1
//   E19 S  6->5   (0101) MSB=0 foll=1
//   E20 S  5->4   (0100) MSB=0 foll=1
//   E21 S  4->3   (0011) MSB=0 foll=1
//   E22 S  3->2   (0010) MSB=0 foll=1
//   E23 S  2->1   (0001) MSB=0 foll=1
//   E24 S  1->0   (0000) MSB=0 foll=1   <- atingiu PSEL_MIN
//
//   ---- (iv) SATURACAO INFERIOR: 2x miss_srrip_i alem do piso -------------
//   E25 S  0->0   (0000) trava, sem wraparound. MSB=0 foll=1
//   E26 S  0->0   (0000) trava de novo.          MSB=0 foll=1
//
//   ---- (vii) MISS SIMULTANEO na borda inferior (cancelamento) ------------
//   E27 SB 0->0   (ambos pulsam no mesmo ciclo; cancelamento, NAO
//                  incrementa nem decrementa -- ver justificativa completa
//                  no cabecalho de rtl/psel_dueling.v). MSB=0 foll=1
//
//   ---- preparo: 5x miss_brrip_i para alcancar um ponto MEIO da faixa -----
//   (necessario para o proximo teste de simultaneidade NAO coincidir com
//   nenhuma borda de saturacao, provando que o cancelamento e um mecanismo
//   REAL, nao apenas um efeito colateral de saturacao)
//   E28 B  0->1  (0001) MSB=0 foll=1
//   E29 B  1->2  (0010) MSB=0 foll=1
//   E30 B  2->3  (0011) MSB=0 foll=1
//   E31 B  3->4  (0100) MSB=0 foll=1
//   E32 B  4->5  (0101) MSB=0 foll=1
//
//   ---- (vii) MISS SIMULTANEO em ponto MEIO da faixa (cancelamento real) --
//   E33 SB 5->5  (ambos pulsam; se houvesse prioridade fixa para um lado o
//                 resultado seria 4 [prioridade srrip] ou 6 [prioridade
//                 brrip] -- o resultado observado (5, inalterado) PROVA
//                 cancelamento simetrico, nao prioridade disfarcada).
//                 MSB=0 foll=1
//
//   ---- (v) VIRADA DO MSB (para cima), continuando com miss_brrip_i -------
//   E34 B  5->6  (0110) MSB=0 foll=1
//   E35 B  6->7  (0111) MSB=0 foll=1
//   E36 B  7->8  (1000) MSB=1 foll=0   <-- VIRADA DO MSB (7->8, sentido oposto de E17)
//
//   ---- preparo: 7x miss_brrip_i para alcancar o teto de novo -------------
//   E37 B  8->9   (1001) MSB=1 foll=0
//   E38 B  9->10  (1010) MSB=1 foll=0
//   E39 B  10->11 (1011) MSB=1 foll=0
//   E40 B  11->12 (1100) MSB=1 foll=0
//   E41 B  12->13 (1101) MSB=1 foll=0
//   E42 B  13->14 (1110) MSB=1 foll=0
//   E43 B  14->15 (1111) MSB=1 foll=0
//
//   ---- (vii) MISS SIMULTANEO na borda superior (cancelamento) ------------
//   E44 SB 15->15 (ambos pulsam; cancelamento -- coincide numericamente com
//                  o que a saturacao isolada tambem daria, testado por
//                  completude/simetria com E27). MSB=1 foll=0
//
//   ---- (vi) RESET no meio da simulacao: volta ao ponto medio documentado -
//   apos reset (com psel em 15, longe do meio, ANTES do reset): psel deve
//   voltar exatamente a PSEL_RESET=8 (1000), MSB=1, foll=0 -- prova que o
//   reset NAO retem estado anterior (mesmo espirito do teste de "reset
//   determinismo" de tb/repl_brrip_tb.v, adaptado para este contador).
//
//   ---- (viii) PULSO SUSTENTADO (ressalva #2 da revisao rtl-analyst): -----
//   rtl/psel_dueling.v afirma no comentario da porta miss_srrip_i/
//   miss_brrip_i que manter o pulso em nivel alto por VARIOS ciclos
//   consecutivos (violando o contrato "pulso de 1 ciclo") e comportamento
//   BEM DEFINIDO -- incrementa/decrementa a CADA borda de clock enquanto o
//   sinal permanecer alto. Nenhum teste ate aqui exercitava isso (todas as
//   tasks do_miss_srrip/do_miss_brrip/do_miss_both pulsam por EXATAMENTE 1
//   ciclo). Este bloco sustenta miss_brrip_i em alto por 4 ciclos
//   consecutivos (sem baixar entre eles) partindo do estado pos-reset do
//   item (vi) (psel=8), depois sustenta miss_srrip_i em alto por 5 ciclos
//   consecutivos -- valores calculados na mao:
//
//   Estado de partida (pos-reset, item vi): psel=8 (1000) MSB=1 foll=0
//
//   -- sustenta miss_brrip_i=1 por 4 bordas de clock consecutivas (sem
//      baixar o sinal entre elas) --
//   E45 B(sustentado) 8->9   (1001) MSB=1 foll=0   <- 1a borda com sinal alto
//   E46 B(sustentado) 9->10  (1010) MSB=1 foll=0   <- 2a borda, sinal AINDA alto
//   E47 B(sustentado) 10->11 (1011) MSB=1 foll=0   <- 3a borda, sinal AINDA alto
//   E48 B(sustentado) 11->12 (1100) MSB=1 foll=0   <- 4a borda, sinal AINDA alto
//   (miss_brrip_i baixado logo apos E48, antes da proxima borda)
//   E49 (sinal baixo) 12->12 (1100) MSB=1 foll=0   <- confirma que o incremento
//        PARA assim que o sinal e liberado (nao "vazam" incrementos extras)
//
//   -- sustenta miss_srrip_i=1 por 5 bordas de clock consecutivas, partindo
//      de 12 (inclui a VIRADA DO MSB na ultima borda, 8->7, sentido oposto
//      de E36) --
//   E50 S(sustentado) 12->11 (1011) MSB=1 foll=0   <- 1a borda com sinal alto
//   E51 S(sustentado) 11->10 (1010) MSB=1 foll=0   <- 2a borda, sinal AINDA alto
//   E52 S(sustentado) 10->9  (1001) MSB=1 foll=0   <- 3a borda, sinal AINDA alto
//   E53 S(sustentado) 9->8   (1000) MSB=1 foll=0   <- 4a borda, sinal AINDA alto
//   E54 S(sustentado) 8->7   (0111) MSB=0 foll=1   <- 5a borda: VIRADA DO MSB
//        acontecendo NO MEIO de um pulso sustentado (nao so em pulsos de 1
//        ciclo como E17/E36) -- prova que a logica de decisao dos
//        seguidores reage corretamente mesmo sob pulso sustentado.
//   (miss_srrip_i baixado logo apos E54, antes da proxima borda)
//   E55 (sinal baixo) 7->7   (0111) MSB=0 foll=1   <- confirma que o
//        decremento PARA assim que o sinal e liberado.
//
// -----------------------------------------------------------------------
// Cobertura EXATA deste testbench: 58 checagens autoverificaveis (cada
// chamada de check_derived_params/check_state conta 1 checagem, contadas na
// ordem em que aparecem no bloco `initial`):
//
//   check_derived_params (PSEL_MAX/PSEL_MIN/PSEL_RESET do DUT) ......... 1
//   pos-reset inicial (item vi) .......................................... 1
//   (i)   subida E1..E7 ................................................. 7
//   (iii) saturacao superior E8..E9 ...................................... 2
//   (ii)+(v) descida + virada do MSB p/ baixo E10..E24 .................. 15
//   (iv)  saturacao inferior E25..E26 .................................... 2
//   (vii) simultaneo na borda inferior E27 ................................ 1
//   preparo ate o meio da faixa E28..E32 .................................. 5
//   (vii) simultaneo no meio da faixa E33 .................................. 1
//   (v)   virada do MSB p/ cima E34..E36 ................................... 3
//   preparo ate o teto de novo E37..E43 ..................................... 7
//   (vii) simultaneo na borda superior E44 .................................. 1
//   (vi)  reset no meio da simulacao (retorno ao ponto medio) ............... 1
//   (viii) pulso sustentado miss_brrip_i, 4 bordas + 1 estabilidade E45..E49 . 5
//   (viii) pulso sustentado miss_srrip_i, 5 bordas + 1 estabilidade E50..E55 . 6
//
//   TOTAL .................................................................. 58
// -----------------------------------------------------------------------
// =============================================================================

`timescale 1ns/1ps

module psel_dueling_tb;

    localparam PSEL_BITS = 4;

    localparam [PSEL_BITS-1:0] PSEL_MAX   = 4'd15; // 2^PSEL_BITS - 1
    localparam [PSEL_BITS-1:0] PSEL_MIN   = 4'd0;
    localparam [PSEL_BITS-1:0] PSEL_RESET = 4'd8;  // 2^(PSEL_BITS-1), meio da faixa

    reg clk;
    reg rst;
    reg miss_srrip_i;
    reg miss_brrip_i;
    wire follower_use_brrip_o;
    wire [PSEL_BITS-1:0] psel_o;   // porta de debug combinacional (ressalva #1)

    integer errors;

    psel_dueling #(
        .PSEL_BITS (PSEL_BITS)
    ) dut (
        .clk                  (clk),
        .rst                  (rst),
        .miss_srrip_i         (miss_srrip_i),
        .miss_brrip_i         (miss_brrip_i),
        .follower_use_brrip_o (follower_use_brrip_o),
        .psel_o               (psel_o)
    );

    // ---- clock (100 MHz simulado) --------------------------------------
    always #5 clk = ~clk;

    // =========================================================================
    // ---- tasks -----------------------------------------------------------
    // =========================================================================

    task check_derived_params;
    begin
        if (dut.PSEL_MAX !== PSEL_MAX || dut.PSEL_MIN !== PSEL_MIN || dut.PSEL_RESET !== PSEL_RESET) begin
            errors = errors + 1;
            $display("FALHA derivados: esperado PSEL_MAX=%0d PSEL_MIN=%0d PSEL_RESET=%0d | obtido PSEL_MAX=%0d PSEL_MIN=%0d PSEL_RESET=%0d",
                       PSEL_MAX, PSEL_MIN, PSEL_RESET, dut.PSEL_MAX, dut.PSEL_MIN, dut.PSEL_RESET);
        end else begin
            $display("OK derivados: PSEL_MAX=%0d PSEL_MIN=%0d PSEL_RESET=%0d",
                       dut.PSEL_MAX, dut.PSEL_MIN, dut.PSEL_RESET);
        end
    end
    endtask

    // pulsa miss_srrip_i por 1 ciclo (decrementa o PSEL, ver convencao no
    // cabecalho de rtl/psel_dueling.v)
    task do_miss_srrip;
    begin
        @(negedge clk);
        miss_srrip_i = 1'b1;
        @(negedge clk);
        miss_srrip_i = 1'b0;
    end
    endtask

    // pulsa miss_brrip_i por 1 ciclo (incrementa o PSEL)
    task do_miss_brrip;
    begin
        @(negedge clk);
        miss_brrip_i = 1'b1;
        @(negedge clk);
        miss_brrip_i = 1'b0;
    end
    endtask

    // pulsa AMBOS miss_srrip_i e miss_brrip_i no MESMO ciclo (cenario item
    // vii: cancelamento, ver justificativa no cabecalho de rtl/psel_dueling.v)
    task do_miss_both;
    begin
        @(negedge clk);
        miss_srrip_i = 1'b1;
        miss_brrip_i = 1'b1;
        @(negedge clk);
        miss_srrip_i = 1'b0;
        miss_brrip_i = 1'b0;
    end
    endtask

    // Fonte PRIMARIA de verificacao: a porta de debug psel_o (ressalva #1
    // da revisao rtl-analyst -- antes deste testbench usava referencia
    // hierarquica dut.psel_reg como unica fonte, o que funciona em
    // simulacao mas quebra a consistencia de interface do projeto, ja que
    // cache_addr.v/repl_lru.v/repl_srrip.v/repl_brrip.v todos expoem
    // estado interno via porta rd_*_o dedicada, nao por hierarquia).
    // dut.psel_reg e mantido como checagem de CONSISTENCIA SECUNDARIA
    // (prova que psel_o e de fato um espelho fiel e combinacional do
    // registrador interno, nao uma porta desconectada ou com latencia) --
    // uma falha em qualquer um dos dois lados conta como falha desta
    // checagem.
    task check_state(input [511:0] label, input [PSEL_BITS-1:0] exp_psel, input exp_foll);
    begin
        #1;
        if (psel_o !== exp_psel || follower_use_brrip_o !== exp_foll) begin
            errors = errors + 1;
            $display("FALHA [%0s]: esperado psel=%0d foll=%0b | obtido psel_o=%0d foll=%0b",
                       label, exp_psel, exp_foll, psel_o, follower_use_brrip_o);
        end else if (psel_o !== dut.psel_reg) begin
            // psel_o (porta) e dut.psel_reg (hierarquico, so p/ checagem de
            // consistencia) divergiram -- psel_o pararia de ser um espelho
            // fiel do estado interno, o que seria um bug na propria porta
            // de debug (nao no contador em si, ja verificado OK acima).
            errors = errors + 1;
            $display("FALHA [%0s]: psel_o=%0d diverge de dut.psel_reg=%0d (porta de debug incoerente)",
                       label, psel_o, dut.psel_reg);
        end else begin
            $display("OK [%0s] -> psel_o=%0d foll=%0b", label, psel_o, follower_use_brrip_o);
        end
    end
    endtask

    // =========================================================================
    // ---- sequencia principal -----------------------------------------------
    // =========================================================================
    initial begin
        errors       = 0;
        clk          = 1'b0;
        rst          = 1'b1;
        miss_srrip_i = 1'b0;
        miss_brrip_i = 1'b0;

        @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        $display("==================================================================");
        $display("psel_dueling_tb: PSEL_BITS=%0d (PSEL_MAX=%0d, PSEL_RESET=%0d)", PSEL_BITS, PSEL_MAX, PSEL_RESET);
        $display("==================================================================");

        check_derived_params;

        $display("---- pos-reset: psel no ponto medio documentado (item vi) ----");
        check_state("pos-reset", 4'd8, 1'b0);

        $display("---- (i) SUBIDA: 7x miss_brrip_i, 8->15 ----");
        do_miss_brrip; check_state("E1  8->9",   4'd9,  1'b0);
        do_miss_brrip; check_state("E2  9->10",  4'd10, 1'b0);
        do_miss_brrip; check_state("E3  10->11", 4'd11, 1'b0);
        do_miss_brrip; check_state("E4  11->12", 4'd12, 1'b0);
        do_miss_brrip; check_state("E5  12->13", 4'd13, 1'b0);
        do_miss_brrip; check_state("E6  13->14", 4'd14, 1'b0);
        do_miss_brrip; check_state("E7  14->15 (PSEL_MAX)", 4'd15, 1'b0);

        $display("---- (iii) SATURACAO SUPERIOR: 2x miss_brrip_i alem do teto ----");
        do_miss_brrip; check_state("E8  15->15 (satura, sem wraparound)", 4'd15, 1'b0);
        do_miss_brrip; check_state("E9  15->15 (satura de novo)",          4'd15, 1'b0);

        $display("---- (ii)+(v) DESCIDA + virada do MSB p/ baixo: 15x miss_srrip_i ----");
        do_miss_srrip; check_state("E10 15->14", 4'd14, 1'b0);
        do_miss_srrip; check_state("E11 14->13", 4'd13, 1'b0);
        do_miss_srrip; check_state("E12 13->12", 4'd12, 1'b0);
        do_miss_srrip; check_state("E13 12->11", 4'd11, 1'b0);
        do_miss_srrip; check_state("E14 11->10", 4'd10, 1'b0);
        do_miss_srrip; check_state("E15 10->9",  4'd9,  1'b0);
        do_miss_srrip; check_state("E16 9->8",   4'd8,  1'b0);
        do_miss_srrip; check_state("E17 8->7 (VIRADA DO MSB p/ baixo)", 4'd7, 1'b1);
        do_miss_srrip; check_state("E18 7->6",  4'd6, 1'b1);
        do_miss_srrip; check_state("E19 6->5",  4'd5, 1'b1);
        do_miss_srrip; check_state("E20 5->4",  4'd4, 1'b1);
        do_miss_srrip; check_state("E21 4->3",  4'd3, 1'b1);
        do_miss_srrip; check_state("E22 3->2",  4'd2, 1'b1);
        do_miss_srrip; check_state("E23 2->1",  4'd1, 1'b1);
        do_miss_srrip; check_state("E24 1->0 (PSEL_MIN)", 4'd0, 1'b1);

        $display("---- (iv) SATURACAO INFERIOR: 2x miss_srrip_i alem do piso ----");
        do_miss_srrip; check_state("E25 0->0 (satura, sem wraparound)", 4'd0, 1'b1);
        do_miss_srrip; check_state("E26 0->0 (satura de novo)",          4'd0, 1'b1);

        $display("---- (vii) MISS SIMULTANEO na borda inferior (cancelamento) ----");
        do_miss_both; check_state("E27 0->0 (simultaneo, cancelamento na borda)", 4'd0, 1'b1);

        $display("---- preparo: 5x miss_brrip_i ate um ponto MEIO da faixa ----");
        do_miss_brrip; check_state("E28 0->1", 4'd1, 1'b1);
        do_miss_brrip; check_state("E29 1->2", 4'd2, 1'b1);
        do_miss_brrip; check_state("E30 2->3", 4'd3, 1'b1);
        do_miss_brrip; check_state("E31 3->4", 4'd4, 1'b1);
        do_miss_brrip; check_state("E32 4->5", 4'd5, 1'b1);

        $display("---- (vii) MISS SIMULTANEO no MEIO da faixa (cancelamento real, sem saturacao envolvida) ----");
        do_miss_both; check_state("E33 5->5 (simultaneo no meio, prova cancelamento)", 4'd5, 1'b1);

        $display("---- (v) VIRADA DO MSB p/ cima, continuando com miss_brrip_i ----");
        do_miss_brrip; check_state("E34 5->6", 4'd6, 1'b1);
        do_miss_brrip; check_state("E35 6->7", 4'd7, 1'b1);
        do_miss_brrip; check_state("E36 7->8 (VIRADA DO MSB p/ cima)", 4'd8, 1'b0);

        $display("---- preparo: 7x miss_brrip_i ate o teto de novo ----");
        do_miss_brrip; check_state("E37 8->9",   4'd9,  1'b0);
        do_miss_brrip; check_state("E38 9->10",  4'd10, 1'b0);
        do_miss_brrip; check_state("E39 10->11", 4'd11, 1'b0);
        do_miss_brrip; check_state("E40 11->12", 4'd12, 1'b0);
        do_miss_brrip; check_state("E41 12->13", 4'd13, 1'b0);
        do_miss_brrip; check_state("E42 13->14", 4'd14, 1'b0);
        do_miss_brrip; check_state("E43 14->15 (PSEL_MAX)", 4'd15, 1'b0);

        $display("---- (vii) MISS SIMULTANEO na borda superior (cancelamento) ----");
        do_miss_both; check_state("E44 15->15 (simultaneo, cancelamento na borda)", 4'd15, 1'b0);

        $display("---- (vi) RESET no meio da simulacao: retorno ao ponto medio documentado ----");
        @(negedge clk);
        rst = 1'b1;
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);
        check_state("apos reset no meio da sim (retorna a PSEL_RESET, nao retem 15)", 4'd8, 1'b0);

        // =====================================================================
        // ---- (viii) PULSO SUSTENTADO (ressalva #2 da revisao rtl-analyst) ----
        // Ao contrario de do_miss_brrip/do_miss_srrip/do_miss_both (que
        // pulsam por EXATAMENTE 1 ciclo), este bloco mantem o sinal em
        // nivel alto por VARIOS ciclos consecutivos SEM baixa-lo entre
        // bordas, exercitando o comportamento "BEM DEFINIDO" descrito no
        // cabecalho de rtl/psel_dueling.v para essa violacao de contrato de
        // pulso: incrementa/decrementa a CADA borda de clock enquanto o
        // sinal permanecer alto. Valores calculados na mao no cabecalho
        // deste arquivo (ver bloco "(viii) PULSO SUSTENTADO" acima).
        // =====================================================================
        $display("---- (viii) PULSO SUSTENTADO: miss_brrip_i em alto por 4 bordas consecutivas ----");
        @(negedge clk);
        miss_brrip_i = 1'b1;                          // fica alto ate ser explicitamente baixado abaixo
        @(negedge clk); check_state("E45 sustentado B 8->9",   4'd9,  1'b0);
        @(negedge clk); check_state("E46 sustentado B 9->10",  4'd10, 1'b0);
        @(negedge clk); check_state("E47 sustentado B 10->11", 4'd11, 1'b0);
        @(negedge clk); check_state("E48 sustentado B 11->12", 4'd12, 1'b0);
        miss_brrip_i = 1'b0;                          // libera o sinal antes da proxima borda
        @(negedge clk); check_state("E49 B liberado (12 estavel, sem incremento extra)", 4'd12, 1'b0);

        $display("---- (viii) PULSO SUSTENTADO: miss_srrip_i em alto por 5 bordas consecutivas (inclui virada do MSB) ----");
        @(negedge clk);
        miss_srrip_i = 1'b1;                          // fica alto ate ser explicitamente baixado abaixo
        @(negedge clk); check_state("E50 sustentado S 12->11", 4'd11, 1'b0);
        @(negedge clk); check_state("E51 sustentado S 11->10", 4'd10, 1'b0);
        @(negedge clk); check_state("E52 sustentado S 10->9",  4'd9,  1'b0);
        @(negedge clk); check_state("E53 sustentado S 9->8",   4'd8,  1'b0);
        @(negedge clk); check_state("E54 sustentado S 8->7 (VIRADA DO MSB em pulso sustentado)", 4'd7, 1'b1);
        miss_srrip_i = 1'b0;                          // libera o sinal antes da proxima borda
        @(negedge clk); check_state("E55 S liberado (7 estavel, sem decremento extra)", 4'd7, 1'b1);

        // ---- resumo final -----------------------------------------------------
        $display("==================================================================");
        if (errors == 0)
            $display("RESULTADO: PASS (0 erros)");
        else
            $display("RESULTADO: FAIL (%0d erro(s))", errors);
        $display("==================================================================");

        $finish;
    end

endmodule
