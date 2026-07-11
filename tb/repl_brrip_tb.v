// =============================================================================
// repl_brrip_tb.v
// Testbench autoverificavel para repl_brrip.v (Fase 4 - PI4 UNIPAMPA).
//
// Como compilar/simular no ModelSim (a partir de /home/miguel/verilog):
//
//   vlib work
//   vlog rtl/repl_brrip.v tb/repl_brrip_tb.v
//   vsim -c work.repl_brrip_tb -do "run -all; quit -f"
//
// (ou use o script pronto: `vsim -c -do sim/run_repl_brrip.do`)
//
// Config do DUT (config de validacao do plano, ver plano-cache.md):
//   SETS=4, WAYS=2, RRPV_BITS=2 -> INDEX_W=2, WAY_W=1, RRPV_MAX=3,
//   RRPV_INSERT_RARE=2 (=RRPV_MAX-1), RRPV_INSERT_COMMON=3 (=RRPV_MAX).
//
//   BRRIP_THROTTLE_BITS=2 -> periodo de throttle = 2^2 = 4 fills. Valor
//   DELIBERADAMENTE menor que o default de fabrica do modulo (5 bits,
//   fidelidade a 1/32 do paper) -- ver "NOTA DE MECANISMO DE THROTTLE" no
//   cabecalho de rtl/repl_brrip.v para a justificativa completa (com 1/32
//   seriam necessarios 32 fills so pra observar 1 ocorrencia do caso raro;
//   com 1/4 a sequencia fica pequena e 100% rastreavel na mao, exercitando
//   o wraparound completo do contador de throttle em poucas linhas, sem
//   mudar o mecanismo em si -- mesmo hardware, periodo menor).
//
// -----------------------------------------------------------------------
// Valores esperados CALCULADOS NA MAO antes de escrever o codigo.
//
// Mecanismo de throttle (ver rtl/repl_brrip.v): 1 contador GLOBAL
// (compartilhado por TODOS os sets/vias) `throttle_ctr`, largura
// BRRIP_THROTTLE_BITS=2, incrementa em 1 (wraparound automatico por
// largura fixa) a CADA fill_en_i efetivado -- nao a cada ciclo de clock.
// Decisao (combinacional, usando o valor CORRENTE/pre-incremento do
// contador NO MOMENTO do fill):
//   throttle_ctr==0 (2'b00) -> RARO  -> insere RRPV_INSERT_RARE   (=2)
//   throttle_ctr!=0         -> COMUM -> insere RRPV_INSERT_COMMON (=3)
// Como o contador zera no reset e incrementa em 1 por fill, a sequencia de
// throttle_ctr NO MOMENTO de cada fill sucessivo (1-indexado a partir do
// 1o fill apos o reset) e EXATAMENTE: 0,1,2,3,0,1,2,3,0,1,2,3,...
// -> RARO exatamente nos fills numero 1,5,9,13,... (todo fill cuja posicao,
//    1-indexada, e congruente a 1 modulo 4) -- proporcao EXATA 1/4, nao
//    estatistica, ja que o mecanismo e um contador determinstico, nao um
//    gerador pseudo-aleatorio "de verdade".
//
// Numeramos GLOBALMENTE (n=1,2,3,...) cada fill_en_i efetivamente pulsado
// ao longo de TODA a sequencia deste testbench (hits NAO avancam o
// contador, so fills avancam), pra poder prever o valor RARO/COMUM de cada
// um exatamente:
//
//   n=1: fill(way0,set0) ctr_antes=0 -> RARO  -> RRPV[0][0]=2 (ctr vira 1)
//   n=2: fill(way1,set0) ctr_antes=1 -> COMUM -> RRPV[1][0]=3 (ctr vira 2)
//   n=3: fill(way0,set1) ctr_antes=2 -> COMUM -> RRPV[0][1]=3 (ctr vira 3)
//   n=4: fill(way1,set1) ctr_antes=3 -> COMUM -> RRPV[1][1]=3 (ctr vira 0)
//   n=5: fill(way0,set2) ctr_antes=0 -> RARO  -> RRPV[0][2]=2 (ctr vira 1)
//
//   Os 5 fills acima (n=1..n=5), espalhados por sets/vias DIFERENTES de
//   proposito, prova DUAS coisas ao mesmo tempo: (a) a proporcao exata
//   RARO/COMUM/COMUM/COMUM/RARO prevista pela formula acima, e (b) que o
//   contador de throttle e GLOBAL (avanca independente de qual set/via
//   estiver sendo preenchida, nao reinicia por set).
//
//   n=6: fill(way1,set2) [fill na vitima do despejo direto, ver abaixo]
//        ctr_antes=1 -> COMUM -> RRPV[1][2]=3 (ctr vira 2)
//   n=7: fill(way1,set2) [2a rodada, mesma via -- demonstra reelegibilidade
//        imediata do caso COMUM, ver nota no cabecalho de repl_brrip.v]
//        ctr_antes=2 -> COMUM -> RRPV[1][2]=3 (ctr vira 3)
//   n=8: fill(way0,set3) [fill na vitima do despejo com aging, ver abaixo]
//        ctr_antes=3 -> COMUM -> RRPV[0][3]=3 (ctr vira 0)
//   n=9: fill(way0,set0) [setup do cenario 2 da race hit-vs-aging, ver
//        abaixo -- coincide numericamente com RRPV_INSERT do SRRIP porque
//        RRPV_MAX-1=2 em ambos, mas aqui a ORIGEM do valor 2 e o throttle
//        ter sorteado ctr_antes=0 nesta rodada, nao um valor fixo]
//        ctr_antes=0 -> RARO -> RRPV[0][0]=2 (ctr vira 1)
//
// ==== Despejo DIRETO no set2 (n=5 deixa way0=2, way1 intocado=RRPV_MAX) ===
//   victim_search(set2) -> encontrada em 1 ciclo, via=1 (unica em RRPV_MAX,
//   via0 esta em 2). Apos a busca, RRPV nao muda (busca so consulta+marca).
//   fill(way1,set2) = n=6 -> COMUM -> RRPV[1][2]=3 (=RRPV_MAX outra vez!).
//
//   Reelegibilidade imediata (propriedade caracteristica do BRRIP, ver nota
//   no cabecalho de repl_brrip.v): como o fill n=6 caiu no caso COMUM, a
//   via1 volta a RRPV_MAX IMEDIATAMENTE, sem nenhuma rodada de graca --
//   uma NOVA busca no mesmo set2, sem nenhum aging, encontra a MESMA via1
//   de novo, em 1 ciclo. fill(way1,set2) = n=7 -> COMUM de novo -> RRPV
//   permanece 3 -- o padrao se repete enquanto o throttle continuar COMUM.
//
// ==== Despejo COM AGING no set3, partindo de (0,0) (hit em ambas vias) ===
//   Mesma mecanica de repl_srrip.v (a FSM de busca e IDENTICA -- throttle
//   so afeta FILL, nao a busca de vitima nem o aging). Contagem de bordas
//   (mesma definicao do task do_victim_search: cyc=1 e a borda do proprio
//   pedido, contando ate victim_valid_o=1 inclusive):
//     cyc=1: IDLE->AGE, found=false sobre (0,0).
//     cyc=2: AGE, found=false sobre (0,0) -> aplica (0,0)->(1,1).
//     cyc=3: AGE, found=false sobre (1,1) -> aplica (1,1)->(2,2).
//     cyc=4: AGE, found=false sobre (2,2) -> aplica (2,2)->(3,3).
//     cyc=5: AGE, found=true sobre (3,3) -> FOUND, via0 (empate, menor
//            indice vence). exp_cycles=5, exp_way=0.
//   fill(way0,set3) = n=8 -> COMUM -> RRPV[0][3]=3. via1/set3 permanece em
//   3 (aging a deixou la, fill nao a afeta) -- as DUAS vias do set3 ficam
//   simultaneamente em RRPV_MAX apos este fill (consequencia esperada do
//   caso COMUM, nao um erro).
//
// -----------------------------------------------------------------------
// ==== RACE hit-vs-aging (replica os 2 cenarios de repl_srrip_tb.v) ========
//
// Mesma mascara de protecao de repl_srrip.v (found_c exclui, no set sob
// avaliacao, a via que hit_en_i estiver mirando NESTE MESMO ciclo) -- ver
// "NOTA DE RACE HIT-vs-AGING" no cabecalho de repl_srrip.v para a analise
// completa da race e da correcao (identica aqui, mesma FSM reusada).
//
// Cenario 1 (empate, alternativa disponivel) -- reusa o set0, redefinido
//   para (0,0) via hit (independente do estado residual dos fills n=1/n=2):
//     hit(way0,set0)->0 ; hit(way1,set0)->0
//     borda A: IDLE->AGE, found=false sobre (0,0)
//     borda B: aplica (0,0)->(1,1)
//     borda C: aplica (1,1)->(2,2)
//     borda D: aplica (2,2)->(3,3); found_c em D ainda le (2,2) pre-borda
//       -> false, sem interferencia do hit (ainda nao assertado)
//     ANTES da borda E, assert hit(way0,set0) -- via0 e a que venceria o
//       desempate se nao fosse a mascara.
//     borda E: found_c avaliado com (3,3) + mascara via0 -> via1 vence
//       (nao afetada pelo hit, tambem em RRPV_MAX). via0 termina em 0
//       (pos-hit), NAO e escolhida vitima.
//     borda F: FOUND->IDLE.
//   Estado busy transitorio (bordas A-D) mostra victim_way_o com o valor
//   STALE do ULTIMO despejo encontrado ANTES deste cenario -- que foi o
//   despejo com aging do set3 (via0) -- logo way=0 (stale) durante todo o
//   periodo busy=1,valid=0 deste cenario, ate a vitima real (via1) ser
//   encontrada na borda E.
//
// Cenario 2 (via hit e a UNICA candidata) -- reusa o set0 de novo,
//   redefinido explicitamente via fill(n=9, RARO->valor 2)+hit:
//     fill(way0,set0) [n=9, RARO] -> RRPV[0][0]=2 ; hit(way1,set0)->0
//     estado inicial (2,0) -- IDENTICO numericamente ao cenario 2 de
//     repl_srrip_tb.v (coincidencia: RRPV_INSERT_RARE=2=RRPV_MAX-1, mesmo
//     valor numerico do RRPV_INSERT fixo do SRRIP, mas aqui vindo do
//     throttle ter sorteado ctr_antes=0 nesta rodada).
//     borda A: IDLE->AGE, found=false sobre (2,0)
//     borda B: aplica (2,0)->(3,1) -- via0 SOZINHA alcanca RRPV_MAX; via1
//       ainda em 1.
//     ANTES da borda C, assert hit(way0,set0) -- a UNICA via em RRPV_MAX.
//     borda C: found_c mascarado -> false (sem alternativa) -> FSM
//       PERMANECE em S_AGE e aplica mais 1 rodada de aging: via0 sofre
//       hit (prioridade sobre aging no mesmo ciclo -> pos-hit=0, o
//       incremento de aging que tentaria leva-la a 3 e sobrescrito pelo
//       hit, que e aplicado por ultimo no always); via1 (nao mascarada)
//       envelhece normalmente 1->2. Estado apos C: (0,2).
//     borda D: aging natural sobre (0,2) -> aplica (0,2)->(1,3); via1
//       alcanca RRPV_MAX sozinha (unica candidata legitima agora).
//     borda E: found_c=true sobre (1,3) -> via1 vence LEGITIMAMENTE (via0
//       nao esta em RRPV_MAX, nenhuma mascara em jogo aqui).
//     borda F: FOUND->IDLE.
//   Estado busy transitorio (borda C) mostra victim_way_o STALE = via1
//   (ultimo despejo encontrado, que foi o proprio cenario 1 acima).
// -----------------------------------------------------------------------
// ==== Reset determinismo do throttle (padrao 100% reproduzivel) ==========
//
// Apos o cenario 2 acima, o contador de throttle esta em ctr=1 (avancou 1x
// no fill n=9). Pulsamos rst=1 por 1 ciclo (reset sincrono) e verificamos:
//   (a) dut.throttle_ctr volta a 0 (nao fica "preso" no valor anterior);
//   (b) TODO o storage de RRPV volta a RRPV_MAX (spot-check em 4 posicoes);
//   (c) a FSM de busca volta a IDLE (victim_way_reg tambem reseta a 0).
// Em seguida, REPETIMOS EXATAMENTE a mesma sequencia de 5 fills de n=1..n=5
// (mesmos ways/sets, mesma ordem) e conferimos que o padrao RARO/COMUM
// observado e IDENTICO byte a byte ao da primeira vez (RARO,COMUM,COMUM,
// COMUM,RARO -> valores 2,3,3,3,2), e que dut.throttle_ctr termina de novo
// em 1 -- prova de que a sequencia pseudo-aleatoria e 100% determinada pelo
// reset (nao existe estado "nao inicializado" da qual ela dependa: e um
// registrador comum, sem semente externa nem uso de $random).
// -----------------------------------------------------------------------
//
// Cobertura EXATA deste testbench: 74 checagens autoverificaveis (cada
// chamada de task check_*/do_victim_search conta 1 checagem, contadas na
// ordem em que aparecem no bloco `initial`):
//
//   pos-reset + larguras derivadas ......................... 10
//     check_derived_widths ................................. 1
//     pos-reset rrpv (2 vias x 4 sets) ..................... 8
//     throttle_ctr==0 logo apos reset ...................... 1
//   throttle: proporcao 1/4 (fills n=1..n=5, sets/vias
//     variados, prova tambem que o contador e global) ........ 9
//   hit (RRPV->0) no set1 + independencia do set0 ............ 6
//   despejo DIRETO set2 + reelegibilidade imediata (n=6,n=7) .. 9
//   despejo COM AGING set3 (n=8) .............................. 7
//   RACE hit-vs-aging cenario 1 (empate, alternativa) .......... 9
//   RACE hit-vs-aging cenario 2 (via hit e unica candidata,
//     setup com fill n=9) ..................................... 11
//   reset determinismo do throttle (check pre-reset + check
//     pos-reset do proprio ctr + 4 spot-checks de rrpv + FSM
//     de volta a IDLE + replay identico de n=1..n=5 com
//     check final do ctr) ..................................... 13
//
//   TOTAL .................................................... 74
// -----------------------------------------------------------------------
// =============================================================================

`timescale 1ns/1ps

module repl_brrip_tb;

    localparam SETS               = 4;
    localparam WAYS               = 2;
    localparam RRPV_BITS          = 2;
    localparam BRRIP_THROTTLE_BITS = 2; // periodo=4 -- ver justificativa no cabecalho

    localparam INDEX_W    = 2; // $clog2(SETS)     -- calculado a mao
    localparam WAY_W      = 1; // $clog2(WAYS)
    localparam [RRPV_BITS-1:0] RRPV_MAX           = 2'd3; // 2^RRPV_BITS - 1
    localparam [RRPV_BITS-1:0] RRPV_INSERT_RARE   = 2'd2; // RRPV_MAX - 1
    localparam [RRPV_BITS-1:0] RRPV_INSERT_COMMON = 2'd3; // RRPV_MAX

    reg clk;
    reg rst;

    reg                  hit_en_i;
    reg  [WAY_W-1:0]     hit_way_i;
    reg  [INDEX_W-1:0]   hit_index_i;

    reg                  fill_en_i;
    reg  [WAY_W-1:0]     fill_way_i;
    reg  [INDEX_W-1:0]   fill_index_i;

    reg                  victim_req_i;
    reg  [INDEX_W-1:0]   victim_index_i;
    wire                 victim_busy_o;
    wire                 victim_valid_o;
    wire [WAY_W-1:0]     victim_way_o;

    reg  [WAY_W-1:0]     rd_way_i;
    reg  [INDEX_W-1:0]   rd_index_i;
    wire [RRPV_BITS-1:0] rd_rrpv_o;

    integer errors;

    repl_brrip #(
        .SETS                (SETS),
        .WAYS                (WAYS),
        .RRPV_BITS           (RRPV_BITS),
        .BRRIP_THROTTLE_BITS (BRRIP_THROTTLE_BITS)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .hit_en_i        (hit_en_i),
        .hit_way_i       (hit_way_i),
        .hit_index_i     (hit_index_i),
        .fill_en_i       (fill_en_i),
        .fill_way_i      (fill_way_i),
        .fill_index_i    (fill_index_i),
        .victim_req_i    (victim_req_i),
        .victim_index_i  (victim_index_i),
        .victim_busy_o   (victim_busy_o),
        .victim_valid_o  (victim_valid_o),
        .victim_way_o    (victim_way_o),
        .rd_way_i        (rd_way_i),
        .rd_index_i      (rd_index_i),
        .rd_rrpv_o       (rd_rrpv_o)
    );

    // ---- clock (100 MHz simulado) --------------------------------------
    always #5 clk = ~clk;

    // =========================================================================
    // ---- tasks ---------------------------------------------------------------
    // =========================================================================

    task check_derived_widths;
    begin
        if (dut.INDEX_W !== INDEX_W || dut.WAY_W !== WAY_W ||
            dut.RRPV_MAX !== RRPV_MAX || dut.RRPV_INSERT_RARE !== RRPV_INSERT_RARE ||
            dut.RRPV_INSERT_COMMON !== RRPV_INSERT_COMMON) begin
            errors = errors + 1;
            $display("FALHA larguras derivadas: esperado INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d RRPV_INSERT_RARE=%0d RRPV_INSERT_COMMON=%0d | obtido INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d RRPV_INSERT_RARE=%0d RRPV_INSERT_COMMON=%0d",
                       INDEX_W, WAY_W, RRPV_MAX, RRPV_INSERT_RARE, RRPV_INSERT_COMMON,
                       dut.INDEX_W, dut.WAY_W, dut.RRPV_MAX, dut.RRPV_INSERT_RARE, dut.RRPV_INSERT_COMMON);
        end else begin
            $display("OK larguras derivadas: INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d RRPV_INSERT_RARE=%0d RRPV_INSERT_COMMON=%0d",
                       dut.INDEX_W, dut.WAY_W, dut.RRPV_MAX, dut.RRPV_INSERT_RARE, dut.RRPV_INSERT_COMMON);
        end
    end
    endtask

    task do_fill(input [WAY_W-1:0] way, input [INDEX_W-1:0] idx);
    begin
        @(negedge clk);
        fill_en_i    = 1'b1;
        fill_way_i   = way;
        fill_index_i = idx;
        @(negedge clk);
        fill_en_i = 1'b0;
    end
    endtask

    task do_hit(input [WAY_W-1:0] way, input [INDEX_W-1:0] idx);
    begin
        @(negedge clk);
        hit_en_i    = 1'b1;
        hit_way_i   = way;
        hit_index_i = idx;
        @(negedge clk);
        hit_en_i = 1'b0;
    end
    endtask

    task check_rrpv(input [511:0] label, input [WAY_W-1:0] way, input [INDEX_W-1:0] idx,
                     input [RRPV_BITS-1:0] exp);
    begin
        rd_way_i   = way;
        rd_index_i = idx;
        #1;
        if (rd_rrpv_o !== exp) begin
            errors = errors + 1;
            $display("FALHA rrpv [%0s] way=%0d set=%0d: esperado %0d obtido %0d",
                       label, way, idx, exp, rd_rrpv_o);
        end else begin
            $display("OK rrpv [%0s] way=%0d set=%0d -> %0d", label, way, idx, rd_rrpv_o);
        end
    end
    endtask

    task check_throttle_ctr(input [511:0] label, input [BRRIP_THROTTLE_BITS-1:0] exp);
    begin
        #1;
        if (dut.throttle_ctr !== exp) begin
            errors = errors + 1;
            $display("FALHA throttle_ctr [%0s]: esperado %0d obtido %0d",
                       label, exp, dut.throttle_ctr);
        end else begin
            $display("OK throttle_ctr [%0s] -> %0d", label, dut.throttle_ctr);
        end
    end
    endtask

    task check_search_state(input [511:0] label, input exp_busy, input exp_valid,
                             input [WAY_W-1:0] exp_way);
    begin
        #1;
        if (victim_busy_o !== exp_busy || victim_valid_o !== exp_valid ||
            victim_way_o !== exp_way) begin
            errors = errors + 1;
            $display("FALHA estado busca [%0s]: esperado busy=%0b valid=%0b way=%0d | obtido busy=%0b valid=%0b way=%0d",
                       label, exp_busy, exp_valid, exp_way, victim_busy_o, victim_valid_o, victim_way_o);
        end else begin
            $display("OK estado busca [%0s] -> busy=%0b valid=%0b way=%0d",
                       label, victim_busy_o, victim_valid_o, victim_way_o);
        end
    end
    endtask

    // pulsa victim_req_i e aguarda victim_valid_o, contando bordas de clock
    // (cyc=1 = despejo direto, sem nenhuma rodada de aging) -- mesma
    // convencao de repl_srrip_tb.v.
    task do_victim_search(input [511:0] label, input [INDEX_W-1:0] idx,
                           input [WAY_W-1:0] exp_way, input integer exp_cycles);
        integer cyc;
    begin
        @(negedge clk);
        victim_req_i   = 1'b1;
        victim_index_i = idx;
        @(negedge clk);
        victim_req_i = 1'b0;
        cyc = 1;
        while (victim_valid_o !== 1'b1 && cyc < 16) begin
            @(negedge clk);
            cyc = cyc + 1;
        end
        if (victim_valid_o !== 1'b1 || victim_way_o !== exp_way || cyc !== exp_cycles) begin
            errors = errors + 1;
            $display("FALHA victim_search [%0s] set=%0d: esperado way=%0d cycles=%0d | obtido valid=%0b way=%0d cycles=%0d",
                       label, idx, exp_way, exp_cycles, victim_valid_o, victim_way_o, cyc);
        end else begin
            $display("OK victim_search [%0s] set=%0d -> way=%0d cycles=%0d", label, idx, victim_way_o, cyc);
        end
        @(negedge clk); // consome a borda de retorno FOUND->IDLE
    end
    endtask

    // =========================================================================
    // ---- sequencia principal -------------------------------------------------
    // =========================================================================
    initial begin
        errors = 0;
        clk    = 1'b0;
        rst    = 1'b1;

        hit_en_i       = 1'b0; hit_way_i      = {WAY_W{1'b0}};    hit_index_i    = {INDEX_W{1'b0}};
        fill_en_i      = 1'b0; fill_way_i     = {WAY_W{1'b0}};    fill_index_i   = {INDEX_W{1'b0}};
        victim_req_i   = 1'b0; victim_index_i = {INDEX_W{1'b0}};
        rd_way_i       = {WAY_W{1'b0}};  rd_index_i    = {INDEX_W{1'b0}};

        @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        $display("==================================================================");
        $display("repl_brrip_tb: SETS=%0d WAYS=%0d RRPV_BITS=%0d BRRIP_THROTTLE_BITS=%0d",
                   SETS, WAYS, RRPV_BITS, BRRIP_THROTTLE_BITS);
        $display("==================================================================");

        check_derived_widths;

        $display("---- pos-reset: todas as vias/sets em RRPV_MAX, throttle_ctr=0 ----");
        check_rrpv("pos-reset way0/set0", 1'd0, 2'd0, RRPV_MAX);
        check_rrpv("pos-reset way1/set0", 1'd1, 2'd0, RRPV_MAX);
        check_rrpv("pos-reset way0/set1", 1'd0, 2'd1, RRPV_MAX);
        check_rrpv("pos-reset way1/set1", 1'd1, 2'd1, RRPV_MAX);
        check_rrpv("pos-reset way0/set2", 1'd0, 2'd2, RRPV_MAX);
        check_rrpv("pos-reset way1/set2", 1'd1, 2'd2, RRPV_MAX);
        check_rrpv("pos-reset way0/set3", 1'd0, 2'd3, RRPV_MAX);
        check_rrpv("pos-reset way1/set3", 1'd1, 2'd3, RRPV_MAX);
        check_throttle_ctr("pos-reset", 2'd0);

        $display("---- throttle bimodal: proporcao 1/4 (fills n=1..n=5, sets/vias variados) ----");
        do_fill(1'd0, 2'd0); // n=1: ctr_antes=0 -> RARO
        check_rrpv("n=1 fill way0/set0 (RARO)", 1'd0, 2'd0, RRPV_INSERT_RARE);
        check_rrpv("n=1 way1/set0 intocado", 1'd1, 2'd0, RRPV_MAX);

        do_fill(1'd1, 2'd0); // n=2: ctr_antes=1 -> COMUM
        check_rrpv("n=2 fill way1/set0 (COMUM)", 1'd1, 2'd0, RRPV_INSERT_COMMON);
        check_rrpv("n=2 way0/set0 nao afetado", 1'd0, 2'd0, RRPV_INSERT_RARE);

        do_fill(1'd0, 2'd1); // n=3: ctr_antes=2 -> COMUM
        check_rrpv("n=3 fill way0/set1 (COMUM)", 1'd0, 2'd1, RRPV_INSERT_COMMON);

        do_fill(1'd1, 2'd1); // n=4: ctr_antes=3 -> COMUM
        check_rrpv("n=4 fill way1/set1 (COMUM)", 1'd1, 2'd1, RRPV_INSERT_COMMON);

        do_fill(1'd0, 2'd2); // n=5: ctr_antes=0 (wrap) -> RARO
        check_rrpv("n=5 fill way0/set2 (RARO, wraparound do periodo)", 1'd0, 2'd2, RRPV_INSERT_RARE);
        check_rrpv("n=5 way1/set2 intocado (ainda RRPV_MAX de reset)", 1'd1, 2'd2, RRPV_MAX);
        check_throttle_ctr("apos n=5 (5 fills, ctr=5 mod 4=1)", 2'd1);

        $display("---- hit (RRPV->0) no set1 + independencia do set0 ----");
        do_hit(1'd0, 2'd1);
        check_rrpv("apos hit way0/set1", 1'd0, 2'd1, 2'd0);
        check_rrpv("way1/set1 nao afetado pelo hit", 1'd1, 2'd1, RRPV_INSERT_COMMON);
        do_hit(1'd1, 2'd1);
        check_rrpv("apos hit way1/set1", 1'd1, 2'd1, 2'd0);
        check_rrpv("way0/set1 continua 0", 1'd0, 2'd1, 2'd0);
        check_rrpv("set0 way0 continua intacto (independencia)", 1'd0, 2'd0, RRPV_INSERT_RARE);
        check_rrpv("set0 way1 continua intacto (independencia)", 1'd1, 2'd0, RRPV_INSERT_COMMON);

        $display("---- despejo DIRETO no set2 + reelegibilidade imediata (n=6,n=7) ----");
        do_victim_search("despejo direto set2", 2'd2, 1'd1, 1);
        check_rrpv("set2 way0 inalterado pela busca", 1'd0, 2'd2, RRPV_INSERT_RARE);
        check_rrpv("set2 way1 inalterado pela busca", 1'd1, 2'd2, RRPV_MAX);
        do_fill(1'd1, 2'd2); // n=6: ctr_antes=1 -> COMUM (fill na vitima)
        check_rrpv("n=6 set2 way1 apos fill na vitima (COMUM -> volta a RRPV_MAX)", 1'd1, 2'd2, RRPV_INSERT_COMMON);
        check_rrpv("n=6 set2 way0 nao afetado", 1'd0, 2'd2, RRPV_INSERT_RARE);

        do_victim_search("despejo direto set2, 2a rodada (reelegibilidade imediata, sem aging)", 2'd2, 1'd1, 1);
        check_rrpv("set2 way0 inalterado pela 2a busca", 1'd0, 2'd2, RRPV_INSERT_RARE);
        check_rrpv("set2 way1 inalterado pela 2a busca", 1'd1, 2'd2, RRPV_MAX);
        do_fill(1'd1, 2'd2); // n=7: ctr_antes=2 -> COMUM (fill na vitima, 2a vez)
        check_rrpv("n=7 set2 way1 apos fill na vitima (COMUM de novo)", 1'd1, 2'd2, RRPV_INSERT_COMMON);

        $display("---- despejo COM AGING no set3, a partir de (0,0) (n=8) ----");
        do_hit(1'd0, 2'd3); // RRPV[0][3]=0
        do_hit(1'd1, 2'd3); // RRPV[1][3]=0
        check_rrpv("set3 way0 antes da busca", 1'd0, 2'd3, 2'd0);
        check_rrpv("set3 way1 antes da busca", 1'd1, 2'd3, 2'd0);
        do_victim_search("despejo com aging set3 (0,0)->(3,3), 3 rodadas", 2'd3, 1'd0, 5);
        check_rrpv("set3 way0 apos aging (empate, via0 vence)", 1'd0, 2'd3, RRPV_MAX);
        check_rrpv("set3 way1 apos aging", 1'd1, 2'd3, RRPV_MAX);
        do_fill(1'd0, 2'd3); // n=8: ctr_antes=3 -> COMUM (fill na vitima)
        check_rrpv("n=8 set3 way0 apos fill na vitima (COMUM -> continua RRPV_MAX)", 1'd0, 2'd3, RRPV_INSERT_COMMON);
        check_rrpv("n=8 set3 way1 nao afetado pelo fill (fica em RRPV_MAX pelo aging)", 1'd1, 2'd3, RRPV_MAX);

        // =====================================================================
        // ---- RACE hit-vs-aging: cenario 1 (empate, alternativa disponivel) ----
        // =====================================================================
        $display("==================================================================");
        $display("---- RACE hit-vs-aging: cenario 1 (via hit tem alternativa/empate) ----");
        $display("==================================================================");
        do_hit(1'd0, 2'd0); // RRPV[0][0]=0 (redefine set0, independente do residuo de n=1/n=2)
        do_hit(1'd1, 2'd0); // RRPV[1][0]=0
        check_rrpv("set0 way0 antes da busca (cenario 1)", 1'd0, 2'd0, 2'd0);
        check_rrpv("set0 way1 antes da busca (cenario 1)", 1'd1, 2'd0, 2'd0);

        @(negedge clk); // pedido real -> borda A: IDLE->AGE (found=false sobre (0,0))
        victim_req_i   = 1'b1;
        victim_index_i = 2'd0;
        @(negedge clk);
        victim_req_i = 1'b0;

        @(negedge clk); // borda B: aplica (0,0)->(1,1)
        @(negedge clk); // borda C: aplica (1,1)->(2,2)
        @(negedge clk); // borda D: aplica (2,2)->(3,3) (found_c em D leu (2,2) pre-borda -> false)
        check_rrpv("set0 way0 apos borda D ((2,2)->(3,3))", 1'd0, 2'd0, RRPV_MAX);
        check_rrpv("set0 way1 apos borda D ((2,2)->(3,3))", 1'd1, 2'd0, RRPV_MAX);
        check_search_state("cenario1: ainda em AGE apos borda D (ambas em MAX)", 1'b1, 1'b0, 1'd0); // way=0 = stale do despejo com aging do set3

        hit_en_i    = 1'b1; // ANTES da borda de deteccao E, assert hit na via0 (venceria o desempate sem a mascara)
        hit_way_i   = 1'd0;
        hit_index_i = 2'd0;
        @(negedge clk); // borda E: found_c avaliado com (3,3) + mascara via0
        hit_en_i = 1'b0;

        check_search_state("cenario1: vitima=via1 (via0 preterida por estar sendo hit)", 1'b1, 1'b1, 1'd1);
        check_rrpv("cenario1: set0 way0 pos-hit (renasceu em 0, NAO foi escolhida vitima)", 1'd0, 2'd0, 2'd0);
        check_rrpv("cenario1: set0 way1 continua em RRPV_MAX (vitima legitima)", 1'd1, 2'd0, RRPV_MAX);

        @(negedge clk); // FOUND->IDLE
        check_search_state("cenario1: retorno a IDLE", 1'b0, 1'b0, 1'd1);

        // =====================================================================
        // ---- RACE hit-vs-aging: cenario 2 (via hit e a UNICA candidata) -------
        // =====================================================================
        $display("==================================================================");
        $display("---- RACE hit-vs-aging: cenario 2 (via hit e a UNICA candidata) --------");
        $display("==================================================================");
        do_fill(1'd0, 2'd0); // n=9: ctr_antes=0 -> RARO -> RRPV[0][0]=2
        check_rrpv("n=9 set0 way0 (RARO, setup cenario 2)", 1'd0, 2'd0, RRPV_INSERT_RARE);
        do_hit(1'd1, 2'd0);  // RRPV[1][0]=0
        check_rrpv("set0 way1 antes da busca (cenario 2)", 1'd1, 2'd0, 2'd0);

        @(negedge clk); // pedido real -> borda A: IDLE->AGE (found=false sobre (2,0))
        victim_req_i   = 1'b1;
        victim_index_i = 2'd0;
        @(negedge clk);
        victim_req_i = 1'b0;

        @(negedge clk); // borda B: aplica (2,0)->(3,1) -- via0 SOZINHA em MAX
        check_rrpv("set0 way0 apos borda B (3, unica em MAX)", 1'd0, 2'd0, RRPV_MAX);
        check_rrpv("set0 way1 apos borda B (1, ainda nao em MAX)", 1'd1, 2'd0, 2'd1);

        hit_en_i    = 1'b1; // ANTES da borda C, assert hit na UNICA via em MAX
        hit_way_i   = 1'd0;
        hit_index_i = 2'd0;
        @(negedge clk); // borda C: found_c mascarado -> false -> aging extra
        hit_en_i = 1'b0;

        check_search_state("cenario2: ainda em AGE (via0 mascarada, sem alternativa)", 1'b1, 1'b0, 1'd1); // way=1 = stale do cenario1
        check_rrpv("cenario2: set0 way0 pos-hit (0, prioridade hit sobre aging)", 1'd0, 2'd0, 2'd0);
        check_rrpv("cenario2: set0 way1 seguiu o aging normalmente (1->2)", 1'd1, 2'd0, 2'd2);

        @(negedge clk); // borda D: aging natural (0,2)->(1,3)
        check_rrpv("cenario2: set0 way0 apos borda D", 1'd0, 2'd0, 2'd1);
        check_rrpv("cenario2: set0 way1 apos borda D (MAX, unica candidata legitima)", 1'd1, 2'd0, RRPV_MAX);

        @(negedge clk); // borda E: found_c=true lendo (1,3) -- via1 vence (via0 nao esta em MAX, sem mascara em jogo)
        check_search_state("cenario2: vitima=via1 (encontrada legitimamente, sem race)", 1'b1, 1'b1, 1'd1);

        @(negedge clk); // FOUND->IDLE
        check_search_state("cenario2: retorno a IDLE", 1'b0, 1'b0, 1'd1);

        // =====================================================================
        // ---- reset determinismo do throttle ------------------------------------
        // =====================================================================
        $display("==================================================================");
        $display("---- reset determinismo do mecanismo de throttle ----");
        $display("==================================================================");
        check_throttle_ctr("antes do reset no meio da sim (n=9 avancou o ctr para 1)", 2'd1);

        @(negedge clk);
        rst = 1'b1;
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        check_throttle_ctr("apos reset no meio da sim (volta a 0, nao fica preso)", 2'd0);
        check_rrpv("apos reset: set0 way0 volta a RRPV_MAX", 1'd0, 2'd0, RRPV_MAX);
        check_rrpv("apos reset: set0 way1 volta a RRPV_MAX", 1'd1, 2'd0, RRPV_MAX);
        check_rrpv("apos reset: set3 way0 volta a RRPV_MAX", 1'd0, 2'd3, RRPV_MAX);
        check_rrpv("apos reset: set3 way1 volta a RRPV_MAX", 1'd1, 2'd3, RRPV_MAX);
        check_search_state("apos reset: FSM de busca volta a IDLE", 1'b0, 1'b0, 1'd0);

        $display("---- replay identico de n=1..n=5: mesma sequencia RARO/COMUM esperada ----");
        do_fill(1'd0, 2'd0); // n=1': ctr_antes=0 -> RARO (identico ao n=1 original)
        check_rrpv("replay n=1 fill way0/set0 (RARO)", 1'd0, 2'd0, RRPV_INSERT_RARE);
        do_fill(1'd1, 2'd0); // n=2': ctr_antes=1 -> COMUM
        check_rrpv("replay n=2 fill way1/set0 (COMUM)", 1'd1, 2'd0, RRPV_INSERT_COMMON);
        do_fill(1'd0, 2'd1); // n=3': ctr_antes=2 -> COMUM
        check_rrpv("replay n=3 fill way0/set1 (COMUM)", 1'd0, 2'd1, RRPV_INSERT_COMMON);
        do_fill(1'd1, 2'd1); // n=4': ctr_antes=3 -> COMUM
        check_rrpv("replay n=4 fill way1/set1 (COMUM)", 1'd1, 2'd1, RRPV_INSERT_COMMON);
        do_fill(1'd0, 2'd2); // n=5': ctr_antes=0 (wrap) -> RARO
        check_rrpv("replay n=5 fill way0/set2 (RARO, wraparound identico)", 1'd0, 2'd2, RRPV_INSERT_RARE);
        check_throttle_ctr("apos replay (5 fills, ctr=5 mod 4=1, identico ao original)", 2'd1);

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
