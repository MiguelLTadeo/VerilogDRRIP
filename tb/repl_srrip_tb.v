// =============================================================================
// repl_srrip_tb.v
// Testbench autoverificavel para repl_srrip.v (Fase 3 - PI4 UNIPAMPA).
//
// Como compilar/simular no ModelSim (a partir de /home/miguel/verilog):
//
//   vlib work
//   vlog rtl/repl_srrip.v tb/repl_srrip_tb.v
//   vsim -c work.repl_srrip_tb -do "run -all; quit -f"
//
// (ou use o script pronto: `vsim -c -do sim/run_repl_srrip.do`)
//
// Este testbench cobre DUAS instancias do DUT:
//   dut    : config de validacao do plano (SETS=4, WAYS=2, RRPV_BITS=2)
//   dut_w4 : SETS=2, WAYS=4, RRPV_BITS=2 -- prova que repl_srrip.v GENERALIZA
//            para associatividade > 2 (diferenca chave vs repl_lru.v, que so
//            funciona p/ WAYS==2). Ver comentario de generalizacao no
//            cabecalho de repl_srrip.v.
//
// Em ambas as configs: RRPV_BITS=2 -> RRPV_MAX=2'b11=3, RRPV_INSERT=3-1=2.
//   dut    : INDEX_W=$clog2(4)=2, WAY_W=$clog2(2)=1
//   dut_w4 : INDEX_W=$clog2(2)=1, WAY_W=$clog2(4)=2
//
// -----------------------------------------------------------------------
// Valores esperados CALCULADOS NA MAO antes de escrever o codigo.
//
// Convencao da FSM de busca de vitima (ver repl_srrip.v):
//   - vitima_req_i pulsado com a FSM em IDLE latcheia victim_index_i e
//     avalia IMEDIATAMENTE (mesmo ciclo) se ja existe via com RRPV==MAX.
//   - se sim: "despejo direto", 1 ciclo de latencia (cyc=1 na contagem do
//     task do_victim_search abaixo, que conta o num. de bordas de clock
//     decorridas desde o pedido ate victim_valid_o=1 inclusive).
//   - se nao: entra em AGE; a CADA ciclo em AGE, reavalia com os valores
//     CORRENTES; se ainda nao achou, incrementa TODAS as vias do set em 1
//     (sem saturar) e permanece em AGE p/ reavaliar no ciclo seguinte.
//   - desempate: menor indice de via vence.
//
// ==== Config principal (dut: SETS=4, WAYS=2) ============================
//
// 0) Pos-reset: RRPV[via][set] = RRPV_MAX(3) para TODAS as 2 vias x 4 sets.
//
// 1) Insercao (RRPV_INSERT=2) no set0, provando independencia entre vias
//    e entre sets:
//      fill(way0,set0)               -> RRPV[0][0]=2 ; RRPV[1][0] ainda=3
//      fill(way1,set0)               -> RRPV[1][0]=2
//      set1 (way0,way1) inalterado   -> continuam em 3,3
//
// 2) Hit (RRPV->0) no set0:
//      hit(way0,set0) -> RRPV[0][0]=0 ; RRPV[1][0] ainda=2 (nao afetado)
//      hit(way1,set0) -> RRPV[1][0]=0 ; RRPV[0][0] continua 0
//      set1 continua intacto em 3,3 (independencia)
//
// 3) Despejo DIRETO no set2 (sem aging): forca so a via1 a estar em
//    RRPV_MAX, deixando a via0 abaixo, pra provar que o desempate/selecao
//    encontra a via CORRETA (via1), nao so a via0 por coincidencia de
//    prioridade:
//      fill(way0,set2)               -> RRPV[0][2]=2 ; RRPV[1][2] continua=3
//      victim_search(set2)           -> encontrada em 1 ciclo, via=1
//                                        (unica com RRPV==3)
//      apos a busca, RRPV nao muda (busca so consulta+marca):
//        RRPV[0][2]=2 ; RRPV[1][2]=3
//      fill(way1,set2) (fill na vitima, completando o fluxo de eviction)
//                                     -> RRPV[1][2]=2 ; RRPV[0][2] continua=2
//
//    Apos este passo, victim_way_reg (registrador interno) = 1 (ultima
//    vitima encontrada) -- relevante p/ os checks de "estado stale" no
//    passo 4 abaixo, ANTES da nova vitima ser encontrada.
//
// 4) Despejo COM AGING no set3, partindo de (0,0) -- nenhuma via em
//    RRPV_MAX inicialmente, e sao necessarias 3 rodadas de incremento
//    para chegar em (3,3) e a busca finalmente encontrar uma vitima
//    (empate entre via0/via1, via0 vence por menor indice). Este teste
//    tambem sustenta um pedido de busca ESPURIO por 2 bordas de clock
//    enquanto a FSM esta ocupada (busy=1), provando que ele e IGNORADO
//    (a FSM so aceita pedido novo em IDLE).
//
//    NOTA DE TIMING (chave p/ entender a contagem de bordas abaixo): cada
//    rodada de aging consome EXATAMENTE 1 borda de clock pra aplicar o
//    incremento; a deteccao de "achou RRPV_MAX" so fica visivel na borda
//    SEGUINTE aquela que aplicou o incremento decisivo (o `if(found_c)`
//    dentro do estado AGE e avaliado com os valores de ANTES da propria
//    borda, entao incremento e deteccao nunca acontecem na mesma borda).
//
//      hit(way0,set3) -> RRPV[0][3]=0 ; hit(way1,set3) -> RRPV[1][3]=0
//      (estado inicial do set3: 0,0 -- nenhuma em 3, precisa de 3 rodadas)
//
//      pulso victim_req_i(idx=3): 1a borda, IDLE->AGE (found=false p/
//        (0,0)). busy=1, valid=0. victim_way_o ainda mostra o valor STALE
//        do passo 3 (=1), pois so e atualizado quando uma vitima e de
//        fato encontrada.
//
//      pedido ESPURIO victim_req_i(idx=1) SUSTENTADO por 2 bordas
//        seguintes (cobrindo as rodadas (0,0)->(1,1)->(2,2)): ignorado o
//        tempo todo (FSM em AGE, so IDLE aceita pedido novo). Apos essas
//        2 bordas: RRPV[*][3]=(2,2), ainda AGE (busy=1,valid=0), e set1
//        (idx=1, alvo do pedido espurio) continua em (3,3) -- prova que
//        o pedido foi mesmo ignorado.
//
//      mais 2 bordas naturais (sem nenhum pedido novo): 1a aplica o
//        ultimo incremento (2,2)->(3,3); a 2a detecta o empate (via0/
//        via1 ambas em RRPV_MAX) e transiciona p/ FOUND, via0 vence por
//        menor indice. victim_way_reg<=0, busy=1, valid=1, way=0.
//
//      borda seguinte: FOUND->IDLE automatico. busy=0, valid=0, way
//        continua =0 (latched).
//
//      fill(way0,set3) (fill na vitima, completando o fluxo)
//        -> RRPV[0][3]=2 ; RRPV[1][3] continua=3 (so o aging tocou nela,
//           fill nao afeta outras vias)
//
// -----------------------------------------------------------------------
// ==== RACE hit-vs-aging (ressalva MEDIA da revisao rtl-analyst, Fase 3) ===
//
// Ver "NOTA DE RACE HIT-vs-AGING" no cabecalho de repl_srrip.v para a
// descricao completa do bug e da correcao escolhida (abordagem "a": mascara
// combinacional no priority-encoder de busca de vitima). Os 2 cenarios
// abaixo usam o set1 do dut principal (index=1, nunca tocado ate este ponto
// da sequencia, ainda no valor de reset RRPV_MAX) e controle ciclo-a-ciclo
// manual (sem a task do_victim_search) para injetar hit_en_i no EXATO ciclo
// em que a FSM (em S_AGE) decidiria found_c=1 usando o valor PRE-borda:
//
// Cenario 1 (empate, alternativa disponivel): leva set1 a (0,0) via hit,
//   envelhece 3 rodadas ate (3,3) (ambas as vias empatadas em RRPV_MAX).
//   Na borda de deteccao, hit_en_i mira via0 (a que venceria o desempate
//   por menor indice se nao fosse a mascara) -- resultado esperado (e
//   obtido): via0 e EXCLUIDA da candidatura, via1 (tambem em MAX, nao
//   afetada pelo hit) vence no lugar, sem custo de ciclo extra. via0
//   termina em RRPV=0 (do hit), NAO e escolhida vitima.
//
// Cenario 2 (via hit e a UNICA candidata): estado assimetrico (2,0) via
//   fill+hit, 1 rodada de aging leva a (3,1) -- so via0 em MAX. Na borda
//   seguinte, hit_en_i mira exatamente essa via0 -- resultado esperado (e
//   obtido): found_c fica FALSO (unica candidata mascarada, sem
//   alternativa), a FSM PERMANECE em S_AGE e aplica mais uma rodada de
//   aging (via0 segue sua trajetoria pos-hit normal: 0->1; via1 continua
//   envelhecendo normalmente: 1->2->3) ate encontrar via1 legitimamente
//   como vitima, sem jamais cravar via0 (a via recem-hit) como vitima.
// -----------------------------------------------------------------------
// ==== victim_req_i sustentado (ressalva MENOR #3, Fase 3) ================
//
// Contrato documentado no cabecalho de repl_srrip.v: victim_req_i deve ser
// pulsado por EXATAMENTE 1 ciclo com a FSM em S_IDLE. Nao ha protecao de
// hardware contra violacao desse contrato -- os 2 sub-testes abaixo (set2
// do dut principal, estado conhecido (2,2)) EXERCITAM a violacao e
// documentam/validam o comportamento resultante desta implementacao:
//
// Sub-teste 1 (sustentado durante AGE/FOUND, deassert ANTES do retorno a
//   IDLE): prova que S_AGE/S_FOUND simplesmente NAO leem victim_req_i --
//   o resultado da busca (via0, por empate) e IDENTICO ao de um pulso de 1
//   ciclo. Uso seguro, mesmo violando o contrato "a rigor".
//
// Sub-teste 2 (sustentado ATE o retorno a IDLE): demonstra o efeito
//   colateral documentado no cabecalho -- se victim_req_i AINDA estiver
//   alto no exato ciclo em que a FSM retorna a S_IDLE, esse nivel e
//   reinterpretado como um NOVO pedido, e a busca REINICIA sozinha (mesmo
//   set, mesma vitima ja em RRPV_MAX) sem nenhum novo pulso do integrador
//   -- comportamento nao protegido, documentado como consequencia de violar
//   o contrato de pulso, nao como recurso proposital de "busca continua".
// -----------------------------------------------------------------------
// ==== Config de generalizacao (dut_w4: SETS=2, WAYS=4) ===================
//
// 0) Pos-reset: RRPV[via][set] = 3 p/ as 4 vias x 2 sets.
//
// 1) Insercao em TODAS as 4 vias do set0:
//      fill(way0..3, set0) -> RRPV[0..3][0] = 2,2,2,2
//
// 2) Hit na via2: RRPV[2][0]=0 -> estado do set0 = (2,2,0,2)
//    (nenhuma via em RRPV_MAX=3 -- busca vai precisar de aging)
//
// 3) victim_search(idx=0): (2,2,0,2) nao tem via==3 -> AGE.
//      1a rodada de aging: incrementa todas -> (3,3,1,3).
//      reavaliacao (2o ciclo em AGE): via0==3 -> ENCONTRADA (menor indice
//      entre via0,via1,via3, que empatam em 3).
//      contagem de ciclos (mesma definicao do task do_victim_search):
//        borda A (IDLE->AGE, found=false) = cyc 1
//        borda B (AGE, found=false c/ (2,2,0,2), aplica incremento->(3,3,1,3)) = cyc 2
//        borda C (AGE, found=true c/ (3,3,1,3), via0) = cyc 3 -> valid=1
//      exp_cycles=3, exp_way=0.
//
//    Apos a busca (so consulta+marca): RRPV[*][0] = (3,3,1,3).
//    fill(way0,set0) completa o fluxo -> RRPV[*][0] = (2,3,1,3).
//
// 4) Independencia: set1 nunca foi tocado, continua em (3,3,3,3) ->
//    victim_search(idx=1) encontra DIRETO (1 ciclo), via=0 (menor
//    indice entre as 4, todas empatadas em 3). A busca no set1 nao
//    altera o set0 (permanece (2,3,1,3)) nem o proprio set1 (permanece
//    (3,3,3,3), busca so consulta+marca).
// -----------------------------------------------------------------------
//
// Cobertura EXATA deste testbench: 105 checagens autoverificaveis (cada
// chamada de task check_*/do_victim_search, e a checagem inline de
// contagem de bordas do aging sustentado, conta 1 checagem, contadas na
// ordem em que aparecem no bloco `initial`):
//
//   ---- config principal (dut, SETS=4 WAYS=2) ---- 40 checagens
//   check_derived_widths ............... 1
//   pos-reset (2 vias x 4 sets) ......... 8
//   insercao set0 (independencia) ....... 5
//   hit set0 (independencia) ............ 6
//   despejo direto set2 ................. 7
//   despejo com aging set3 (3 rodadas +
//     pedido espurio sustentado
//     ignorado durante busy) ........... 13
//
//   ---- RACE hit-vs-aging (ressalva MEDIA) ---- 20 checagens
//   cenario 1 (empate, alternativa disponivel) . 9
//   cenario 2 (via hit e a unica candidata) .... 11
//
//   ---- victim_req_i sustentado (ressalva MENOR #3) ---- 10 checagens
//   sub-teste 1 (deassert antes do retorno) ..... 4
//   sub-teste 2 (retrigger automatico) .......... 6
//
//   ---- config de generalizacao (dut_w4, SETS=2 WAYS=4) ---- 35 checagens
//   check_derived_widths_w4 ............. 1
//   pos-reset (4 vias x 2 sets) ......... 8
//   insercao 4 vias set0 ................ 4
//   hit via2 set0 ........................ 4
//   victim_search c/ aging (3 ciclos) .... 1
//   estado apos aging (4 vias) ........... 4
//   fill na vitima + estado (4 vias) ..... 4
//   victim_search direto set1 (1 ciclo) .. 1
//   independencia: set0 intacto (4 vias) . 4
//   independencia: set1 intacto (4 vias) . 4
//
//   TOTAL ................................ 105
// -----------------------------------------------------------------------
// =============================================================================

`timescale 1ns/1ps

module repl_srrip_tb;

    // =========================================================================
    // ---- DUT principal: SETS=4, WAYS=2, RRPV_BITS=2 ------------------------
    // =========================================================================
    localparam SETS       = 4;
    localparam WAYS       = 2;
    localparam RRPV_BITS  = 2;

    localparam INDEX_W    = 2; // $clog2(SETS)     -- calculado a mao
    localparam WAY_W      = 1; // $clog2(WAYS)
    localparam [RRPV_BITS-1:0] RRPV_MAX    = 2'd3; // 2^RRPV_BITS - 1
    localparam [RRPV_BITS-1:0] RRPV_INSERT = 2'd2; // RRPV_MAX - 1

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

    repl_srrip #(
        .SETS      (SETS),
        .WAYS      (WAYS),
        .RRPV_BITS (RRPV_BITS)
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

    // =========================================================================
    // ---- DUT de generalizacao: SETS=2, WAYS=4, RRPV_BITS=2 ------------------
    // =========================================================================
    localparam SETS_W4      = 2;
    localparam WAYS_W4      = 4;

    localparam INDEX_W_W4   = 1; // $clog2(2)  -- calculado a mao
    localparam WAY_W_W4     = 2; // $clog2(4)

    reg                     hit_en_i_w4;
    reg  [WAY_W_W4-1:0]     hit_way_i_w4;
    reg  [INDEX_W_W4-1:0]   hit_index_i_w4;

    reg                     fill_en_i_w4;
    reg  [WAY_W_W4-1:0]     fill_way_i_w4;
    reg  [INDEX_W_W4-1:0]   fill_index_i_w4;

    reg                     victim_req_i_w4;
    reg  [INDEX_W_W4-1:0]   victim_index_i_w4;
    wire                    victim_busy_o_w4;
    wire                    victim_valid_o_w4;
    wire [WAY_W_W4-1:0]     victim_way_o_w4;

    reg  [WAY_W_W4-1:0]     rd_way_i_w4;
    reg  [INDEX_W_W4-1:0]   rd_index_i_w4;
    wire [RRPV_BITS-1:0]    rd_rrpv_o_w4;

    repl_srrip #(
        .SETS      (SETS_W4),
        .WAYS      (WAYS_W4),
        .RRPV_BITS (RRPV_BITS)
    ) dut_w4 (
        .clk             (clk),
        .rst             (rst),
        .hit_en_i        (hit_en_i_w4),
        .hit_way_i       (hit_way_i_w4),
        .hit_index_i     (hit_index_i_w4),
        .fill_en_i       (fill_en_i_w4),
        .fill_way_i      (fill_way_i_w4),
        .fill_index_i    (fill_index_i_w4),
        .victim_req_i    (victim_req_i_w4),
        .victim_index_i  (victim_index_i_w4),
        .victim_busy_o   (victim_busy_o_w4),
        .victim_valid_o  (victim_valid_o_w4),
        .victim_way_o    (victim_way_o_w4),
        .rd_way_i        (rd_way_i_w4),
        .rd_index_i      (rd_index_i_w4),
        .rd_rrpv_o       (rd_rrpv_o_w4)
    );

    // ---- clock unico compartilhado pelas duas instancias (100 MHz simulado) --
    always #5 clk = ~clk;

    // =========================================================================
    // ---- tasks: config principal (dut) --------------------------------------
    // =========================================================================

    task check_derived_widths;
    begin
        if (dut.INDEX_W !== INDEX_W || dut.WAY_W !== WAY_W ||
            dut.RRPV_MAX !== RRPV_MAX || dut.RRPV_INSERT !== RRPV_INSERT) begin
            errors = errors + 1;
            $display("FALHA larguras derivadas (dut): esperado INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d RRPV_INSERT=%0d | obtido INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d RRPV_INSERT=%0d",
                       INDEX_W, WAY_W, RRPV_MAX, RRPV_INSERT,
                       dut.INDEX_W, dut.WAY_W, dut.RRPV_MAX, dut.RRPV_INSERT);
        end else begin
            $display("OK larguras derivadas (dut): INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d RRPV_INSERT=%0d",
                       dut.INDEX_W, dut.WAY_W, dut.RRPV_MAX, dut.RRPV_INSERT);
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

    // checa busy/valid/way da FSM de busca num instante especifico (usado no
    // rastreamento manual ciclo-a-ciclo do teste de aging + pedido espurio).
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

    // pulsa victim_req_i e aguarda victim_valid_o, contando quantas bordas de
    // clock (cyc) se passaram desde o pedido ate o resultado ficar disponivel
    // (cyc=1 = despejo direto, sem nenhuma rodada de aging). Ao final, deixa
    // a FSM retornar a IDLE (consome mais 1 borda) antes de devolver o
    // controle, para o proximo passo do TB comecar sempre com busy=0.
    task do_victim_search(input [511:0] label, input [INDEX_W-1:0] idx,
                           input [WAY_W-1:0] exp_way, input integer exp_cycles);
        integer cyc;
    begin
        @(negedge clk);
        victim_req_i   = 1'b1;
        victim_index_i = idx;
        @(negedge clk);
        victim_req_i = 1'b0;
        cyc = 1; // 1 borda de clock (a do pedido) ja ocorreu entre os 2 negedges acima
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
    // ---- tasks: config de generalizacao (dut_w4) ----------------------------
    // =========================================================================

    task check_derived_widths_w4;
    begin
        if (dut_w4.INDEX_W !== INDEX_W_W4 || dut_w4.WAY_W !== WAY_W_W4 ||
            dut_w4.RRPV_MAX !== RRPV_MAX || dut_w4.RRPV_INSERT !== RRPV_INSERT) begin
            errors = errors + 1;
            $display("FALHA larguras derivadas (dut_w4): esperado INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d RRPV_INSERT=%0d | obtido INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d RRPV_INSERT=%0d",
                       INDEX_W_W4, WAY_W_W4, RRPV_MAX, RRPV_INSERT,
                       dut_w4.INDEX_W, dut_w4.WAY_W, dut_w4.RRPV_MAX, dut_w4.RRPV_INSERT);
        end else begin
            $display("OK larguras derivadas (dut_w4): INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d RRPV_INSERT=%0d",
                       dut_w4.INDEX_W, dut_w4.WAY_W, dut_w4.RRPV_MAX, dut_w4.RRPV_INSERT);
        end
    end
    endtask

    task do_fill_w4(input [WAY_W_W4-1:0] way, input [INDEX_W_W4-1:0] idx);
    begin
        @(negedge clk);
        fill_en_i_w4    = 1'b1;
        fill_way_i_w4   = way;
        fill_index_i_w4 = idx;
        @(negedge clk);
        fill_en_i_w4 = 1'b0;
    end
    endtask

    task do_hit_w4(input [WAY_W_W4-1:0] way, input [INDEX_W_W4-1:0] idx);
    begin
        @(negedge clk);
        hit_en_i_w4    = 1'b1;
        hit_way_i_w4   = way;
        hit_index_i_w4 = idx;
        @(negedge clk);
        hit_en_i_w4 = 1'b0;
    end
    endtask

    task check_rrpv_w4(input [511:0] label, input [WAY_W_W4-1:0] way, input [INDEX_W_W4-1:0] idx,
                        input [RRPV_BITS-1:0] exp);
    begin
        rd_way_i_w4   = way;
        rd_index_i_w4 = idx;
        #1;
        if (rd_rrpv_o_w4 !== exp) begin
            errors = errors + 1;
            $display("FALHA rrpv_w4 [%0s] way=%0d set=%0d: esperado %0d obtido %0d",
                       label, way, idx, exp, rd_rrpv_o_w4);
        end else begin
            $display("OK rrpv_w4 [%0s] way=%0d set=%0d -> %0d", label, way, idx, rd_rrpv_o_w4);
        end
    end
    endtask

    task do_victim_search_w4(input [511:0] label, input [INDEX_W_W4-1:0] idx,
                              input [WAY_W_W4-1:0] exp_way, input integer exp_cycles);
        integer cyc;
    begin
        @(negedge clk);
        victim_req_i_w4   = 1'b1;
        victim_index_i_w4 = idx;
        @(negedge clk);
        victim_req_i_w4 = 1'b0;
        cyc = 1;
        while (victim_valid_o_w4 !== 1'b1 && cyc < 16) begin
            @(negedge clk);
            cyc = cyc + 1;
        end
        if (victim_valid_o_w4 !== 1'b1 || victim_way_o_w4 !== exp_way || cyc !== exp_cycles) begin
            errors = errors + 1;
            $display("FALHA victim_search_w4 [%0s] set=%0d: esperado way=%0d cycles=%0d | obtido valid=%0b way=%0d cycles=%0d",
                       label, idx, exp_way, exp_cycles, victim_valid_o_w4, victim_way_o_w4, cyc);
        end else begin
            $display("OK victim_search_w4 [%0s] set=%0d -> way=%0d cycles=%0d", label, idx, victim_way_o_w4, cyc);
        end
        @(negedge clk);
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

        hit_en_i_w4       = 1'b0; hit_way_i_w4      = {WAY_W_W4{1'b0}};  hit_index_i_w4    = {INDEX_W_W4{1'b0}};
        fill_en_i_w4      = 1'b0; fill_way_i_w4     = {WAY_W_W4{1'b0}};  fill_index_i_w4   = {INDEX_W_W4{1'b0}};
        victim_req_i_w4   = 1'b0; victim_index_i_w4 = {INDEX_W_W4{1'b0}};
        rd_way_i_w4       = {WAY_W_W4{1'b0}}; rd_index_i_w4  = {INDEX_W_W4{1'b0}};

        // libera reset sincrono apos algumas bordas de clock (reseta as
        // DUAS instancias, que compartilham clk/rst)
        @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        $display("==================================================================");
        $display("repl_srrip_tb: dut SETS=%0d WAYS=%0d RRPV_BITS=%0d | dut_w4 SETS=%0d WAYS=%0d RRPV_BITS=%0d",
                   SETS, WAYS, RRPV_BITS, SETS_W4, WAYS_W4, RRPV_BITS);
        $display("==================================================================");

        // ============ config principal (dut) ============
        check_derived_widths;

        $display("---- pos-reset (dut): todas as vias/sets em RRPV_MAX ----");
        check_rrpv("pos-reset way0/set0", 1'd0, 2'd0, RRPV_MAX);
        check_rrpv("pos-reset way1/set0", 1'd1, 2'd0, RRPV_MAX);
        check_rrpv("pos-reset way0/set1", 1'd0, 2'd1, RRPV_MAX);
        check_rrpv("pos-reset way1/set1", 1'd1, 2'd1, RRPV_MAX);
        check_rrpv("pos-reset way0/set2", 1'd0, 2'd2, RRPV_MAX);
        check_rrpv("pos-reset way1/set2", 1'd1, 2'd2, RRPV_MAX);
        check_rrpv("pos-reset way0/set3", 1'd0, 2'd3, RRPV_MAX);
        check_rrpv("pos-reset way1/set3", 1'd1, 2'd3, RRPV_MAX);

        $display("---- insercao (RRPV_INSERT=2) no set0 ----");
        do_fill(1'd0, 2'd0);
        check_rrpv("apos fill way0/set0", 1'd0, 2'd0, RRPV_INSERT);
        check_rrpv("way1/set0 ainda intocado", 1'd1, 2'd0, RRPV_MAX);
        do_fill(1'd1, 2'd0);
        check_rrpv("apos fill way1/set0", 1'd1, 2'd0, RRPV_INSERT);
        check_rrpv("set1 way0 intacto", 1'd0, 2'd1, RRPV_MAX);
        check_rrpv("set1 way1 intacto", 1'd1, 2'd1, RRPV_MAX);

        $display("---- hit (RRPV->0) no set0 ----");
        do_hit(1'd0, 2'd0);
        check_rrpv("apos hit way0/set0", 1'd0, 2'd0, 2'd0);
        check_rrpv("way1/set0 nao afetado pelo hit", 1'd1, 2'd0, RRPV_INSERT);
        do_hit(1'd1, 2'd0);
        check_rrpv("apos hit way1/set0", 1'd1, 2'd0, 2'd0);
        check_rrpv("way0/set0 continua 0", 1'd0, 2'd0, 2'd0);
        check_rrpv("set1 way0 continua intacto", 1'd0, 2'd1, RRPV_MAX);
        check_rrpv("set1 way1 continua intacto", 1'd1, 2'd1, RRPV_MAX);

        $display("---- despejo DIRETO no set2 (so a via1 fica em RRPV_MAX) ----");
        do_fill(1'd0, 2'd2); // baixa a via0 do set2 pra 2, deixando so a via1 em 3
        check_rrpv("set2 way0 apos fill", 1'd0, 2'd2, RRPV_INSERT);
        check_rrpv("set2 way1 continua em MAX", 1'd1, 2'd2, RRPV_MAX);
        do_victim_search("despejo direto set2", 2'd2, 1'd1, 1);
        check_rrpv("set2 way0 inalterado pela busca", 1'd0, 2'd2, RRPV_INSERT);
        check_rrpv("set2 way1 inalterado pela busca", 1'd1, 2'd2, RRPV_MAX);
        do_fill(1'd1, 2'd2); // fill na vitima encontrada, completando o fluxo
        check_rrpv("set2 way1 apos fill na vitima", 1'd1, 2'd2, RRPV_INSERT);
        check_rrpv("set2 way0 nao afetado pelo fill", 1'd0, 2'd2, RRPV_INSERT);

        $display("---- despejo COM AGING no set3 (via 3 rodadas, a partir de (0,0)) ----");
        // (0,0) precisa de 3 incrementos p/ chegar em RRPV_MAX(3): dá folga
        // suficiente pra sustentar um pedido espurio no MEIO da busca sem
        // arriscar coincidir com o ciclo exato em que a vitima e encontrada
        // (ver nota de timing no cabecalho: cada rodada de aging consome
        // exatamente 1 borda de clock; a deteccao usa os valores ja
        // assentados pela rodada ANTERIOR, entao so fica valida 1 borda
        // DEPOIS do ultimo incremento que leva alguma via a RRPV_MAX).
        do_hit(1'd0, 2'd3); // RRPV[0][3]=0
        do_hit(1'd1, 2'd3); // RRPV[1][3]=0
        check_rrpv("set3 way0 antes da busca", 1'd0, 2'd3, 2'd0);
        check_rrpv("set3 way1 antes da busca", 1'd1, 2'd3, 2'd0);

        // pulso do pedido REAL -> 1a borda: IDLE->AGE (nenhuma via em MAX)
        @(negedge clk);
        victim_req_i   = 1'b1;
        victim_index_i = 2'd3;
        @(negedge clk);
        victim_req_i = 1'b0;
        check_search_state("apos pedido real (entra em AGE)", 1'b1, 1'b0, 1'd1); // way=1 = stale do passo anterior (despejo direto do set2)

        // pedido ESPURIO em idx=1 (set1), SUSTENTADO por 2 bordas de clock
        // (cobrindo as rodadas de aging que levam (0,0)->(1,1)->(2,2)) --
        // deve ser ignorado o tempo todo, pois a FSM so aceita pedido novo
        // em IDLE, e o set3 ainda esta ocupado (busy=1) durante toda a
        // busca. NOTA: aqui assertamos victim_req_i JA NO TEMPO CORRENTE
        // (sem um @(negedge) de sincronizacao antes), pois o ponto de
        // partida (logo apos o #1 de check_search_state) ja esta bem
        // dentro da fase baixa do clock, com folga de sobra ate a proxima
        // borda de subida -- um @(negedge) extra aqui consumiria 1 borda
        // "de graca" (o aging e autonomo, roda mesmo sem pedido) e
        // desalinharia a contagem de rodadas pretendida.
        victim_req_i   = 1'b1;
        victim_index_i = 2'd1; // set1, NAO deveria ser afetado
        @(negedge clk); // rodada: (0,0)->(1,1)
        @(negedge clk); // rodada: (1,1)->(2,2)
        victim_req_i = 1'b0;
        check_search_state("apos 2 rodadas de aging c/ pedido espurio sustentado", 1'b1, 1'b0, 1'd1);
        check_rrpv("set3 way0 apos 2 rodadas", 1'd0, 2'd3, 2'd2);
        check_rrpv("set3 way1 apos 2 rodadas", 1'd1, 2'd3, 2'd2);
        check_rrpv("set1 way0 nao afetado pelo pedido espurio", 1'd0, 2'd1, RRPV_MAX);
        check_rrpv("set1 way1 nao afetado pelo pedido espurio", 1'd1, 2'd1, RRPV_MAX);

        // deixa a 3a rodada ((2,2)->(3,3)) e a deteccao final ocorrerem
        // naturalmente, aguardando victim_valid_o (sem novos pedidos) --
        // esperado: mais exatamente 2 bordas (1 p/ incrementar ate (3,3),
        // 1 p/ detectar usando esse valor ja assentado).
        begin : wait_aging_set3
            integer cyc2;
            cyc2 = 0;
            while (victim_valid_o !== 1'b1 && cyc2 < 16) begin
                @(negedge clk);
                cyc2 = cyc2 + 1;
            end
            if (cyc2 !== 2) begin
                errors = errors + 1;
                $display("FALHA aging set3: esperado 2 bordas restantes ate a deteccao, obtido %0d", cyc2);
            end else begin
                $display("OK aging set3: 2 bordas restantes ate a deteccao (cyc=%0d)", cyc2);
            end
        end
        check_search_state("vitima encontrada apos aging completo (empate, via0 vence)", 1'b1, 1'b1, 1'd0);

        // borda seguinte: FOUND->IDLE automatico
        @(negedge clk);
        check_search_state("retorno a IDLE", 1'b0, 1'b0, 1'd0);

        do_fill(1'd0, 2'd3); // fill na vitima encontrada, completando o fluxo
        check_rrpv("set3 way0 apos fill na vitima", 1'd0, 2'd3, RRPV_INSERT);
        check_rrpv("set3 way1 nao afetado pelo fill (fica em RRPV_MAX)", 1'd1, 2'd3, RRPV_MAX);

        // =====================================================================
        // ---- RACE hit-vs-aging (ressalva MEDIA da revisao rtl-analyst) --------
        // =====================================================================
        // Ver "NOTA DE RACE HIT-vs-AGING" no cabecalho de repl_srrip.v. Os 2
        // cenarios abaixo usam o set1 do dut principal (nunca tocado ate aqui
        // nesta sequencia -- ainda no valor de reset RRPV_MAX,RRPV_MAX) para
        // forcar, DE PROPOSITO, um hit_en_i no MESMO ciclo/via/set em que a
        // FSM (em S_AGE) determinaria found_c=1 usando o valor PRE-borda de
        // rrpv_mem -- exatamente a race descrita na revisao. Controle
        // ciclo-a-ciclo manual (sem a task do_victim_search) para poder
        // injetar hit_en_i no instante exato.
        $display("==================================================================");
        $display("---- RACE hit-vs-aging: cenario 1 (via hit tem alternativa/empate) ----");
        $display("==================================================================");
        // leva set1 a (0,0) via hit, forcando 3 rodadas de aging ate (3,3)
        // (mesma mecanica do teste de aging do set3 acima).
        do_hit(1'd0, 2'd1); // RRPV[0][1]=0
        do_hit(1'd1, 2'd1); // RRPV[1][1]=0
        check_rrpv("set1 way0 antes da busca (cenario 1)", 1'd0, 2'd1, 2'd0);
        check_rrpv("set1 way1 antes da busca (cenario 1)", 1'd1, 2'd1, 2'd0);

        // pedido real -> borda A: IDLE->AGE (found=false p/ (0,0))
        @(negedge clk);
        victim_req_i   = 1'b1;
        victim_index_i = 2'd1;
        @(negedge clk);
        victim_req_i = 1'b0;

        // bordas B e C (naturais, SEM hit ainda): (0,0)->(1,1)->(2,2)
        @(negedge clk); // borda B: aplica (0,0)->(1,1)
        @(negedge clk); // borda C: aplica (1,1)->(2,2)

        // borda D (natural, SEM hit ainda): aplica o ultimo incremento
        // (2,2)->(3,3). found_c em D ainda le (2,2) pre-borda -> false ->
        // so aging, sem qualquer interferencia do hit (que so sera
        // assertado DEPOIS desta borda).
        @(negedge clk); // borda D
        check_rrpv("set1 way0 apos borda D ((2,2)->(3,3))", 1'd0, 2'd1, RRPV_MAX);
        check_rrpv("set1 way1 apos borda D ((2,2)->(3,3))", 1'd1, 2'd1, RRPV_MAX);
        check_search_state("cenario1: ainda em AGE apos borda D (ambas em MAX)", 1'b1, 1'b0, 1'd0); // way=stale do teste do set3

        // AGORA (apos D, antes da borda de deteccao E), assert hit na
        // via0/set1 -- SEM a mascara de correcao, found_way_c seria via0
        // (menor indice, ambas empatadas em RRPV_MAX) e a FSM cravaria via0
        // como vitima na MESMA borda em que o hit a zera. COM a mascara,
        // via0 e excluida da candidatura e via1 (tambem em MAX, nao afetada
        // pelo hit) vence no lugar -- SEM custo de ciclo extra.
        hit_en_i    = 1'b1;
        hit_way_i   = 1'd0;
        hit_index_i = 2'd1;

        @(negedge clk); // borda E: found_c avaliado com (3,3) + mascara via0
        hit_en_i = 1'b0;

        check_search_state("cenario1: vitima=via1 (via0 preterida por estar sendo hit)", 1'b1, 1'b1, 1'd1);
        check_rrpv("cenario1: set1 way0 pos-hit (renasceu em 0, NAO foi escolhida vitima)", 1'd0, 2'd1, 2'd0);
        check_rrpv("cenario1: set1 way1 continua em RRPV_MAX (vitima legitima)", 1'd1, 2'd1, RRPV_MAX);

        @(negedge clk); // FOUND->IDLE
        check_search_state("cenario1: retorno a IDLE", 1'b0, 1'b0, 1'd1);

        $display("==================================================================");
        $display("---- RACE hit-vs-aging: cenario 2 (via hit e a UNICA candidata) --------");
        $display("==================================================================");
        // redefine o estado do set1 explicitamente para (2,0), independente
        // do estado residual do cenario 1 acima:
        do_fill(1'd0, 2'd1); // RRPV[0][1] = RRPV_INSERT = 2
        do_hit(1'd1, 2'd1);  // RRPV[1][1] = 0
        check_rrpv("set1 way0 antes da busca (cenario 2)", 1'd0, 2'd1, RRPV_INSERT);
        check_rrpv("set1 way1 antes da busca (cenario 2)", 1'd1, 2'd1, 2'd0);

        // pedido real -> borda A: IDLE->AGE (found=false p/ (2,0))
        @(negedge clk);
        victim_req_i   = 1'b1;
        victim_index_i = 2'd1;
        @(negedge clk);
        victim_req_i = 1'b0;

        // borda B (natural, SEM hit): aplica (2,0)->(3,1) -- via0 SOZINHA
        // alcanca RRPV_MAX; via1 ainda nao (1).
        @(negedge clk);
        check_rrpv("set1 way0 apos borda B (3, unica em MAX)", 1'd0, 2'd1, RRPV_MAX);
        check_rrpv("set1 way1 apos borda B (1, ainda nao em MAX)", 1'd1, 2'd1, 2'd1);

        // AGORA assert hit na via0/set1 -- a UNICA via em RRPV_MAX. Sem a
        // mascara, a borda seguinte cravaria via0 como vitima usando o
        // valor PRE-borda (MAX) no mesmo instante em que ela e zerada pelo
        // hit. Com a mascara, found_c fica FALSO nesta borda (via0
        // excluida, nenhuma outra via em MAX) -> FSM PERMANECE em S_AGE e
        // aplica mais uma rodada de aging (sem cravar nenhuma vitima ainda).
        hit_en_i    = 1'b1;
        hit_way_i   = 1'd0;
        hit_index_i = 2'd1;

        @(negedge clk); // borda C: found_c mascarado -> false -> aging extra
        hit_en_i = 1'b0;

        check_search_state("cenario2: ainda em AGE (via0 mascarada, sem alternativa)", 1'b1, 1'b0, 1'd1); // way=stale do cenario1
        check_rrpv("cenario2: set1 way0 pos-hit (0, prioridade hit sobre aging)", 1'd0, 2'd1, 2'd0);
        check_rrpv("cenario2: set1 way1 seguiu o aging normalmente (1->2)", 1'd1, 2'd1, 2'd2);

        // bordas naturais restantes (SEM hit): (0,2)->(1,3) e deteccao
        @(negedge clk); // borda D: aging (0,2)->(1,3)
        check_rrpv("cenario2: set1 way0 apos borda D", 1'd0, 2'd1, 2'd1);
        check_rrpv("cenario2: set1 way1 apos borda D (MAX, unica candidata legitima)", 1'd1, 2'd1, RRPV_MAX);

        @(negedge clk); // borda E: found_c=true lendo (1,3) -- via1 vence (via0 nao esta em MAX, sem mascara em jogo)
        check_search_state("cenario2: vitima=via1 (encontrada legitimamente, sem race)", 1'b1, 1'b1, 1'd1);

        @(negedge clk); // FOUND->IDLE
        check_search_state("cenario2: retorno a IDLE", 1'b0, 1'b0, 1'd1);

        // =====================================================================
        // ---- victim_req_i sustentado por varios ciclos (ressalva MENOR #3) ----
        // =====================================================================
        // Contrato documentado no cabecalho de repl_srrip.v: victim_req_i
        // deve ser pulsado por EXATAMENTE 1 ciclo com a FSM em IDLE. Os 2
        // sub-testes abaixo usam o set2 do dut principal (estado conhecido
        // (2,2) apos o teste de despejo direto acima) para EXERCITAR a
        // violacao desse contrato e documentar/validar o comportamento
        // resultante desta implementacao (nao ha protecao de hardware
        // contra a violacao -- ver nota no cabecalho do modulo).
        $display("==================================================================");
        $display("---- victim_req_i sustentado (ressalva MENOR #3) ----");
        $display("==================================================================");
        $display("---- sub-teste 1: sustentado durante AGE/FOUND, deassert ANTES do retorno a IDLE (inofensivo) ----");
        check_rrpv("set2 way0 antes do sub-teste 1", 1'd0, 2'd2, RRPV_INSERT);
        check_rrpv("set2 way1 antes do sub-teste 1", 1'd1, 2'd2, RRPV_INSERT);

        @(negedge clk);
        victim_req_i   = 1'b1;
        victim_index_i = 2'd2;
        // NAO deassert aqui (diferente de do_victim_search) -- mantido em 1
        // deliberadamente por varias bordas, para provar que S_AGE/S_FOUND
        // simplesmente NAO leem victim_req_i (nao muda o resultado da busca).
        @(negedge clk); // borda A: IDLE->AGE (found=false, (2,2))
        @(negedge clk); // borda B: AGE, aplica (2,2)->(3,3)
        @(negedge clk); // borda C: AGE, found=true lendo (3,3) -> FOUND, via0 (empate, menor indice)
        check_search_state("sub-teste1: vitima encontrada normalmente mesmo com req sustentado (via0)", 1'b1, 1'b1, 1'd0);
        victim_req_i = 1'b0; // deassert ANTES do retorno a IDLE -- uso seguro do sinal sustentado
        @(negedge clk); // borda D: FOUND->IDLE, sem retrigger (req ja baixo)
        check_search_state("sub-teste1: retorno limpo a IDLE (sem retrigger)", 1'b0, 1'b0, 1'd0);

        $display("---- sub-teste 2: sustentado ATE o retorno a IDLE -> retrigger automatico (NAO protegido) ----");
        do_fill(1'd0, 2'd2); // completa o fluxo do sub-teste 1 (fill na vitima via0) -> RRPV[0][2]=RRPV_INSERT
        check_rrpv("set2 way0 apos fill (sub-teste2 setup)", 1'd0, 2'd2, RRPV_INSERT);
        check_rrpv("set2 way1 ainda em MAX (sub-teste2 setup)", 1'd1, 2'd2, RRPV_MAX);

        @(negedge clk);
        victim_req_i   = 1'b1;
        victim_index_i = 2'd2;
        // SEM deassert -- mantido alto DE PROPOSITO ate apos o retorno a
        // IDLE, para demonstrar o retrigger automatico documentado no
        // cabecalho do modulo (contrato de pulso de 1 ciclo violado de
        // proposito, para tornar o comportamento observavel/testado).
        @(negedge clk); // borda A: IDLE, found=true de imediato (via1 ja em MAX) -> despejo direto
        check_search_state("sub-teste2: despejo direto imediato (via1 ja em MAX)", 1'b1, 1'b1, 1'd1);
        @(negedge clk); // borda B: FOUND->IDLE incondicional
        check_search_state("sub-teste2: 1 ciclo de IDLE visivel (busy=0) antes do retrigger", 1'b0, 1'b0, 1'd1);
        @(negedge clk); // borda C: req_i AINDA alto -> S_IDLE reinterpreta como NOVO pedido -> retrigger sozinho
        check_search_state("sub-teste2: busca reiniciada sozinha (req sustentado, nenhum novo pulso do TB)", 1'b1, 1'b1, 1'd1);
        victim_req_i = 1'b0; // agora sim, honra o contrato
        @(negedge clk); // borda D: FOUND->IDLE de vez
        check_search_state("sub-teste2: apos deassert, retorno estavel a IDLE", 1'b0, 1'b0, 1'd1);

        // ============ config de generalizacao (dut_w4, WAYS=4) ============
        $display("==================================================================");
        $display("---- dut_w4 (WAYS=4): prova de generalizacao alem de 2-way ----");
        $display("==================================================================");
        check_derived_widths_w4;

        $display("---- pos-reset (dut_w4): todas as 4 vias/2 sets em RRPV_MAX ----");
        check_rrpv_w4("pos-reset way0/set0", 2'd0, 1'd0, RRPV_MAX);
        check_rrpv_w4("pos-reset way1/set0", 2'd1, 1'd0, RRPV_MAX);
        check_rrpv_w4("pos-reset way2/set0", 2'd2, 1'd0, RRPV_MAX);
        check_rrpv_w4("pos-reset way3/set0", 2'd3, 1'd0, RRPV_MAX);
        check_rrpv_w4("pos-reset way0/set1", 2'd0, 1'd1, RRPV_MAX);
        check_rrpv_w4("pos-reset way1/set1", 2'd1, 1'd1, RRPV_MAX);
        check_rrpv_w4("pos-reset way2/set1", 2'd2, 1'd1, RRPV_MAX);
        check_rrpv_w4("pos-reset way3/set1", 2'd3, 1'd1, RRPV_MAX);

        $display("---- insercao nas 4 vias do set0 ----");
        do_fill_w4(2'd0, 1'd0);
        do_fill_w4(2'd1, 1'd0);
        do_fill_w4(2'd2, 1'd0);
        do_fill_w4(2'd3, 1'd0);
        check_rrpv_w4("set0 way0 apos fills", 2'd0, 1'd0, RRPV_INSERT);
        check_rrpv_w4("set0 way1 apos fills", 2'd1, 1'd0, RRPV_INSERT);
        check_rrpv_w4("set0 way2 apos fills", 2'd2, 1'd0, RRPV_INSERT);
        check_rrpv_w4("set0 way3 apos fills", 2'd3, 1'd0, RRPV_INSERT);

        $display("---- hit na via2 do set0 -> estado (2,2,0,2) ----");
        do_hit_w4(2'd2, 1'd0);
        check_rrpv_w4("set0 way0 apos hit via2", 2'd0, 1'd0, RRPV_INSERT);
        check_rrpv_w4("set0 way1 apos hit via2", 2'd1, 1'd0, RRPV_INSERT);
        check_rrpv_w4("set0 way2 apos hit via2", 2'd2, 1'd0, 2'd0);
        check_rrpv_w4("set0 way3 apos hit via2", 2'd3, 1'd0, RRPV_INSERT);

        $display("---- busca com AGING (nenhuma via em MAX, 4 vias) ----");
        // (2,2,0,2) -> 1a rodada de aging -> (3,3,1,3) -> via0 encontrada
        // (menor indice entre via0/via1/via3, empatadas em RRPV_MAX)
        do_victim_search_w4("aging 4-way set0", 1'd0, 2'd0, 3);
        check_rrpv_w4("set0 way0 apos aging (busca so marca)", 2'd0, 1'd0, RRPV_MAX);
        check_rrpv_w4("set0 way1 apos aging", 2'd1, 1'd0, RRPV_MAX);
        check_rrpv_w4("set0 way2 apos aging", 2'd2, 1'd0, 2'd1);
        check_rrpv_w4("set0 way3 apos aging", 2'd3, 1'd0, RRPV_MAX);

        do_fill_w4(2'd0, 1'd0); // fill na vitima encontrada (via0)
        check_rrpv_w4("set0 way0 apos fill na vitima", 2'd0, 1'd0, RRPV_INSERT);
        check_rrpv_w4("set0 way1 nao afetado pelo fill", 2'd1, 1'd0, RRPV_MAX);
        check_rrpv_w4("set0 way2 nao afetado pelo fill", 2'd2, 1'd0, 2'd1);
        check_rrpv_w4("set0 way3 nao afetado pelo fill", 2'd3, 1'd0, RRPV_MAX);

        $display("---- independencia: set1 nunca tocado -> despejo direto (via0) ----");
        do_victim_search_w4("despejo direto set1", 1'd1, 2'd0, 1);
        check_rrpv_w4("set0 way0 intacto apos busca no set1", 2'd0, 1'd0, RRPV_INSERT);
        check_rrpv_w4("set0 way1 intacto apos busca no set1", 2'd1, 1'd0, RRPV_MAX);
        check_rrpv_w4("set0 way2 intacto apos busca no set1", 2'd2, 1'd0, 2'd1);
        check_rrpv_w4("set0 way3 intacto apos busca no set1", 2'd3, 1'd0, RRPV_MAX);
        check_rrpv_w4("set1 way0 inalterado pela busca (so marca)", 2'd0, 1'd1, RRPV_MAX);
        check_rrpv_w4("set1 way1 inalterado pela busca", 2'd1, 1'd1, RRPV_MAX);
        check_rrpv_w4("set1 way2 inalterado pela busca", 2'd2, 1'd1, RRPV_MAX);
        check_rrpv_w4("set1 way3 inalterado pela busca", 2'd3, 1'd1, RRPV_MAX);

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
