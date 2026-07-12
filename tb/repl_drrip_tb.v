// =============================================================================
// repl_drrip_tb.v
// Testbench autoverificavel para repl_drrip.v (Fase 8 PARTE 1 - PI4 UNIPAMPA).
//
// Como compilar/simular no ModelSim (a partir de /home/miguel/verilog):
//
//   vlib work
//   vlog rtl/psel_dueling.v rtl/repl_drrip.v tb/repl_drrip_tb.v
//   vsim -c work.repl_drrip_tb -do "run -all; quit -f"
//
// (ou use o script pronto: `vsim -c -do sim/run_repl_drrip.do`)
//
// -----------------------------------------------------------------------
// Config do DUT: config de ENTREGA do Apendice B (L1, ver plano-cache.md) --
// SETS=64, WAYS=2, RRPV_BITS=2 -> INDEX_W=6, WAY_W=1, RRPV_MAX=3,
// RRPV_INSERT_MID=2 (=RRPV_MAX-1), RRPV_INSERT_FAR=3 (=RRPV_MAX).
//
//   BRRIP_THROTTLE_BITS=2 -> periodo de throttle = 4 insercoes
//   BRRIP-governadas (DELIBERADAMENTE reduzido do default de fabrica do
//   modulo (5 bits/1/32), mesmo espirito/justificativa de
//   tb/repl_brrip_tb.v: mantem a sequencia RARO/COMUM pequena e 100%
//   rastreavel na mao).
//
//   PSEL_BITS=6 -> faixa 0..63, PSEL_RESET=32 (=2^5, MSB=1). Reduzido do
//   default de fabrica (10 bits/faixa 0..1023) pela MESMA razao de
//   tb/psel_dueling_tb.v: com 10 bits seriam necessarios centenas de misses
//   so para atravessar a metade da faixa -- inviavel de rastrear na mao
//   neste testbench. Com 6 bits, poucos misses (usados propositalmente
//   nas secoes 5/7 abaixo) already cruzam o MSB e produzem uma demonstracao
//   clara e hand-tracable da troca de politica dos seguidores.
//
//   SDM_SEL_BITS=4 (default de fabrica do modulo) -> 1/16 de cada lado para
//   SETS=64 (ver "ESQUEMA DE MAPEAMENTO" no cabecalho de rtl/repl_drrip.v):
//     SDM-SRRIP = indices com os 4 bits baixos = 0000 -> {0,16,32,48}
//     SDM-BRRIP = indices com os 4 bits baixos = 1111 -> {15,31,47,63}
//     SEGUIDORES = os demais 56 indices (ex.: 1, 2, ...).
//   Sets usados neste testbench:
//     index0  (SDM-SRRIP, representante principal)
//     index16 (SDM-SRRIP, representante SECUNDARIO -- prova que o
//              mapeamento e por PADRAO de bits, nao hardcoded a 1 indice)
//     index15 (SDM-BRRIP, representante principal)
//     index31 (SDM-BRRIP, representante SECUNDARIO)
//     index1  (SEGUIDOR, representante principal)
//     index2  (SEGUIDOR, representante SECUNDARIO)
//
// -----------------------------------------------------------------------
// Valores esperados CALCULADOS NA MAO antes de escrever o codigo (script
// LINEAR -- cada secao consome o estado deixado pela anterior; nao ha
// resets no meio, por isso o rastreio de throttle_ctr/psel_o abaixo e
// SEQUENCIAL, secao apos secao).
//
// ==== Secao 1: pos-reset ==================================================
//   rrpv_mem[*][*] = RRPV_MAX=3 em toda parte (spot-check index0/1/15/16).
//   throttle_ctr = 0.
//   psel_o = PSEL_RESET = 2^(PSEL_BITS-1) = 2^5 = 32 (100000).
//   follower_use_brrip_o = ~psel_o[5] = ~1 = 0 (seguidores usam SRRIP).
//
// ==== Secao 2: invariante SDM-SRRIP (index0) sempre insere MID ===========
//   fill(way0,set0), fill(way1,set0): papel SDM-SRRIP -> SEMPRE
//   RRPV_INSERT_MID=2, independente de qualquer estado de PSEL (que aqui
//   ainda esta no reset, MSB=1/SRRIP -- sera testado de novo em estado
//   BRRIP-favoravel na secao 9). throttle_ctr NAO avanca (insercao
//   SRRIP-governada nao consome o throttle). psel_o inalterado (fill nao
//   mexe no PSEL, so victim_req_i mexe).
//   Estado apos secao 2: rrpv[0][0]=2, rrpv[1][0]=2. throttle_ctr=0. psel=32.
//
// ==== Secao 3: throttle bimodal no SDM-BRRIP (index15), periodo=4 ========
//   5 fills diretos alternando via, numerados globalmente n=1..5 (1a vez
//   que o throttle_ctr avanca nesta simulacao, ja que a secao 2 foi
//   SRRIP-governada):
//     n=1 fill(way0,set15): ctr_antes=0 -> RARO  -> rrpv[0][15]=MID(2), ctr->1
//     n=2 fill(way1,set15): ctr_antes=1 -> COMUM -> rrpv[1][15]=FAR(3), ctr->2
//     n=3 fill(way0,set15): ctr_antes=2 -> COMUM -> rrpv[0][15]=FAR(3), ctr->3
//     n=4 fill(way1,set15): ctr_antes=3 -> COMUM -> rrpv[1][15]=FAR(3), ctr->0 (wrap)
//     n=5 fill(way0,set15): ctr_antes=0 -> RARO  -> rrpv[0][15]=MID(2), ctr->1
//   Estado apos secao 3: rrpv[0][15]=2, rrpv[1][15]=3. throttle_ctr=1. psel=32
//   (fill nao mexe no PSEL).
//
// ==== Secao 4: seguidor (index1) sob regime SRRIP (psel=32,MSB=1) ========
//   follower_use_brrip_o=0 (SRRIP) -> fill(way0,set1) usa regra SRRIP ->
//   rrpv[0][1]=MID(2). throttle_ctr NAO avanca (permanece 1).
//
// ==== Secao 5: 4 misses no SDM-SRRIP (index0) empurram PSEL para baixo ===
//   Cada victim_req_i ACEITO em index0 (papel SDM-SRRIP) decrementa psel_o
//   em 1 (miss_srrip_i do PSEL interno). Nenhum fill_en_i e pulsado nesta
//   secao (fill so viria depois de um fill real do integrador -- aqui
//   testamos SO o efeito do miss no PSEL/roteamento, como o handshake
//   permite: victim_req->busca->valid e o suficiente, sem fill, para o
//   proximo victim_req no MESMO set ser aceito de novo -- comportamento
//   seguro e determinista, ver nota "CONTRATO DE SEQUENCIAMENTO" em
//   repl_srrip.v: essa nota cobre a RACE fill-vs-novo-victim_req, nao o
//   caso, mais simples, de repetir buscas sem NENHUM fill entre elas, que
//   e inofensivo pois nada muda no array entre uma busca e a proxima).
//
//   Estado de rrpv em index0 entrando nesta secao: (2,2) (secao 2, tie).
//   1a busca (miss #1): found_c falso sobre (2,2) (RRPV_MAX=3) -> AGE.
//     cyc1: IDLE->AGE, found=false sobre (2,2).
//     cyc2: aplica (2,2)->(3,3).
//     cyc3: found=true sobre (3,3) -> FOUND, way0 (empate, menor indice).
//     exp_cycles=3, exp_way=0. psel: 32->31 (decremento, aceito no cyc1).
//     follower_use_brrip_o: ~31[5] = ~0 = 1 -> FLIPOU para BRRIP!
//       (31 = 011111, bit5=0). A partir daqui os seguidores usam BRRIP.
//   2a..4a buscas (miss #2,#3,#4): rrpv de index0 ja esta em (3,3) apos a
//     1a busca (aging nao e desfeito por uma busca) -> despejo DIRETO
//     (cyc1, way0) em cada uma das 3 buscas seguintes (found_c ja
//     verdadeiro no proprio S_IDLE, sem aging). psel: 31->30->29->28.
//   Estado apos secao 5: rrpv[0][0]=3, rrpv[1][0]=3 (achado pela FSM, mas
//   NAO alterado pela busca em si -- busca so consulta+marca). psel=28
//   (011100, bit5=0) -> follower_use_brrip_o=1 (BRRIP) durante toda a secao
//   a partir do primeiro miss.
//
// ==== Secao 6: seguidor (index1) sob regime BRRIP (psel=28) ==============
//   follower_use_brrip_o=1 -> fill(way1,set1) usa a MESMA regra/contador
//   BRRIP do SDM-BRRIP (throttle_ctr continua de onde a secao 3 deixou,
//   =1): ctr_antes=1 -> COMUM -> rrpv[1][1]=FAR(3), ctr->2. Prova que o
//   seguidor consome o MESMO contador global (nao um contador separado).
//   Estado apos secao 6: rrpv[0][1]=2(secao4), rrpv[1][1]=3. throttle_ctr=2.
//
// ==== Secao 7: 4 misses no SDM-BRRIP (index15) empurram PSEL de volta ====
//   Estado de rrpv em index15 entrando: (2,3) (secao 3: way0=MID=2,
//   way1=FAR=3). way1 ja esta em RRPV_MAX -> TODAS as 4 buscas desta secao
//   sao despejo DIRETO (cyc1, way1, found_c ja verdadeiro em S_IDLE, sem
//   necessidade de aging, e sem fill entre elas o estado nunca muda).
//   psel (miss_brrip incrementa): 28->29->30->31->32.
//   follower_use_brrip_o = ~psel[5]: em 28,29,30,31 (todos <32, bit5=0)
//     -> 1 (BRRIP) ainda; em 32 (100000, bit5=1) -> 0 (SRRIP) -- FLIPA DE
//     VOLTA exatamente no 4o miss desta secao (round-trip completo ate o
//     valor de reset).
//   Estado apos secao 7: rrpv[0][15]=2, rrpv[1][15]=3 (inalterado pelas
//   buscas). psel=32. throttle_ctr=2 (inalterado, secao so fez buscas).
//
// ==== Secao 8: seguidor (index1) de volta ao regime SRRIP (psel=32) ======
//   follower_use_brrip_o=0 -> fill(way0,set1) usa regra SRRIP ->
//   rrpv[0][1]=MID(2) (mesmo valor numerico da secao 4, mas agora
//   discriminado corretamente: se estivesse ERRADO usando BRRIP, o
//   throttle_ctr=2 -> ctr_antes=2 -> COMUM -> daria FAR(3), diferente de
//   MID(2) -- o teste discrimina os 2 casos). throttle_ctr NAO avanca
//   (permanece 2, prova que foi SRRIP-governado, nao BRRIP).
//
// ==== Secao 9: robustez dos invariantes SDM apos o round-trip de PSEL ====
//   fill(way0,set0) [SDM-SRRIP, index0]: SEMPRE MID, mesmo com PSEL tendo
//     passado por um ciclo completo BRRIP->SRRIP -> rrpv[0][0]=MID(2).
//     throttle_ctr inalterado (permanece 2).
//   fill(way0,set15) [SDM-BRRIP, index15]: SEMPRE throttle, independente
//     do PSEL -> ctr_antes=2 -> COMUM -> rrpv[0][15]=FAR(3), ctr->3.
//
// ==== Secao 10: hit->0 e aging identicos em QUALQUER papel (invariante #4) =
//   Usa 3 sets FRESCOS (nunca tocados antes -> ainda em RRPV_MAX de
//   reset), 1 de cada papel, incluindo os representantes SECUNDARIOS
//   (index16 SDM-SRRIP, index31 SDM-BRRIP, index2 seguidor) para provar
//   que o mapeamento por padrao de bits nao e hardcoded a index0/15/1:
//     index16 (SDM-SRRIP secundario), index31 (SDM-BRRIP secundario),
//     index2 (seguidor secundario).
//   Para cada um: hit(way0), hit(way1) -> RRPV vira (0,0); depois
//   victim_search encontra vitima com aging identico (mesma FSM,
//   independente do papel):
//     cyc1: IDLE->AGE, found=false sobre (0,0).
//     cyc2: aplica (0,0)->(1,1).
//     cyc3: aplica (1,1)->(2,2).
//     cyc4: aplica (2,2)->(3,3).
//     cyc5: found=true sobre (3,3) -> FOUND, way0 (empate).
//   exp_cycles=5, exp_way=0 -- IDENTICO para os 3 sets, comprovando que
//   busca/aging/hit sao agnosticos ao papel do set.
//   Efeito colateral no PSEL (as buscas em index16/index31 SAO misses SDM
//   de verdade): index16 e SDM-SRRIP -> decrementa (32->31); index31 e
//   SDM-BRRIP -> incrementa (31->32); index2 e seguidor -> nao mexe.
//   psel_o final = 32 (round-trip completo de novo).
// -----------------------------------------------------------------------
//
// Cobertura deste testbench: cada chamada de check_*/do_victim_search
// conta 1 checagem, na ordem em que aparecem no bloco `initial`. Total
// exato reportado em runtime pelo proprio testbench (contagem `errors`);
// ver $display de resumo ao final.
// =============================================================================

`timescale 1ns/1ps

module repl_drrip_tb;

    localparam SETS               = 64;
    localparam WAYS               = 2;
    localparam RRPV_BITS          = 2;
    localparam BRRIP_THROTTLE_BITS = 2; // periodo=4 -- ver justificativa no cabecalho
    localparam PSEL_BITS          = 6;  // faixa 0..63, reset=32 -- ver justificativa no cabecalho
    localparam SDM_SEL_BITS       = 4;  // 1/16 de cada lado para SETS=64

    localparam INDEX_W = 6; // $clog2(SETS)  -- calculado a mao
    localparam WAY_W   = 1; // $clog2(WAYS)
    localparam [RRPV_BITS-1:0] RRPV_MAX        = 2'd3; // 2^RRPV_BITS - 1
    localparam [RRPV_BITS-1:0] RRPV_INSERT_MID = 2'd2; // RRPV_MAX - 1
    localparam [RRPV_BITS-1:0] RRPV_INSERT_FAR = 2'd3; // RRPV_MAX
    localparam [PSEL_BITS-1:0] PSEL_RESET      = 6'd32; // 2^(PSEL_BITS-1)

    // sets de teste (ver cabecalho para o mapeamento SDM_SEL_BITS=4)
    localparam [INDEX_W-1:0] SET_SDM_SRRIP_A = 6'd0;
    localparam [INDEX_W-1:0] SET_SDM_SRRIP_B = 6'd16;
    localparam [INDEX_W-1:0] SET_SDM_BRRIP_A = 6'd15;
    localparam [INDEX_W-1:0] SET_SDM_BRRIP_B = 6'd31;
    localparam [INDEX_W-1:0] SET_FOLLOWER_A  = 6'd1;
    localparam [INDEX_W-1:0] SET_FOLLOWER_B  = 6'd2;

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

    wire [PSEL_BITS-1:0] psel_o;
    wire                 follower_use_brrip_o;
    wire                 rd_is_sdm_srrip_o;
    wire                 rd_is_sdm_brrip_o;

    integer errors;

    repl_drrip #(
        .SETS                (SETS),
        .WAYS                (WAYS),
        .RRPV_BITS           (RRPV_BITS),
        .BRRIP_THROTTLE_BITS (BRRIP_THROTTLE_BITS),
        .PSEL_BITS           (PSEL_BITS),
        .SDM_SEL_BITS        (SDM_SEL_BITS)
    ) dut (
        .clk                   (clk),
        .rst                   (rst),
        .hit_en_i              (hit_en_i),
        .hit_way_i             (hit_way_i),
        .hit_index_i           (hit_index_i),
        .fill_en_i             (fill_en_i),
        .fill_way_i            (fill_way_i),
        .fill_index_i          (fill_index_i),
        .victim_req_i          (victim_req_i),
        .victim_index_i        (victim_index_i),
        .victim_busy_o         (victim_busy_o),
        .victim_valid_o        (victim_valid_o),
        .victim_way_o          (victim_way_o),
        .rd_way_i              (rd_way_i),
        .rd_index_i            (rd_index_i),
        .rd_rrpv_o             (rd_rrpv_o),
        .psel_o                (psel_o),
        .follower_use_brrip_o  (follower_use_brrip_o),
        .rd_is_sdm_srrip_o     (rd_is_sdm_srrip_o),
        .rd_is_sdm_brrip_o     (rd_is_sdm_brrip_o)
    );

    // ---- clock (100 MHz simulado) --------------------------------------
    always #5 clk = ~clk;

    // =========================================================================
    // ---- tasks ---------------------------------------------------------------
    // =========================================================================

    task check_derived_widths;
    begin
        if (dut.INDEX_W !== INDEX_W || dut.WAY_W !== WAY_W ||
            dut.RRPV_MAX !== RRPV_MAX || dut.RRPV_INSERT_MID !== RRPV_INSERT_MID ||
            dut.RRPV_INSERT_FAR !== RRPV_INSERT_FAR) begin
            errors = errors + 1;
            $display("FALHA larguras derivadas: esperado INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d MID=%0d FAR=%0d | obtido INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d MID=%0d FAR=%0d",
                       INDEX_W, WAY_W, RRPV_MAX, RRPV_INSERT_MID, RRPV_INSERT_FAR,
                       dut.INDEX_W, dut.WAY_W, dut.RRPV_MAX, dut.RRPV_INSERT_MID, dut.RRPV_INSERT_FAR);
        end else begin
            $display("OK larguras derivadas: INDEX_W=%0d WAY_W=%0d RRPV_MAX=%0d MID=%0d FAR=%0d",
                       dut.INDEX_W, dut.WAY_W, dut.RRPV_MAX, dut.RRPV_INSERT_MID, dut.RRPV_INSERT_FAR);
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

    task check_psel(input [511:0] label, input [PSEL_BITS-1:0] exp);
    begin
        #1;
        if (psel_o !== exp) begin
            errors = errors + 1;
            $display("FALHA psel_o [%0s]: esperado %0d obtido %0d", label, exp, psel_o);
        end else begin
            $display("OK psel_o [%0s] -> %0d", label, psel_o);
        end
    end
    endtask

    task check_follower_policy(input [511:0] label, input exp_use_brrip);
    begin
        #1;
        if (follower_use_brrip_o !== exp_use_brrip) begin
            errors = errors + 1;
            $display("FALHA follower_use_brrip_o [%0s]: esperado %0b obtido %0b",
                       label, exp_use_brrip, follower_use_brrip_o);
        end else begin
            $display("OK follower_use_brrip_o [%0s] -> %0b", label, follower_use_brrip_o);
        end
    end
    endtask

    task check_role(input [511:0] label, input [INDEX_W-1:0] idx,
                     input exp_srrip, input exp_brrip);
    begin
        rd_index_i = idx;
        #1;
        if (rd_is_sdm_srrip_o !== exp_srrip || rd_is_sdm_brrip_o !== exp_brrip) begin
            errors = errors + 1;
            $display("FALHA papel [%0s] set=%0d: esperado sdm_srrip=%0b sdm_brrip=%0b | obtido sdm_srrip=%0b sdm_brrip=%0b",
                       label, idx, exp_srrip, exp_brrip, rd_is_sdm_srrip_o, rd_is_sdm_brrip_o);
        end else begin
            $display("OK papel [%0s] set=%0d -> sdm_srrip=%0b sdm_brrip=%0b",
                       label, idx, rd_is_sdm_srrip_o, rd_is_sdm_brrip_o);
        end
    end
    endtask

    // pulsa victim_req_i e aguarda victim_valid_o, contando bordas de clock
    // (cyc=1 = despejo direto, sem nenhuma rodada de aging) -- mesma
    // convencao de repl_srrip_tb.v/repl_brrip_tb.v.
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
        $display("repl_drrip_tb: SETS=%0d WAYS=%0d RRPV_BITS=%0d BRRIP_THROTTLE_BITS=%0d PSEL_BITS=%0d SDM_SEL_BITS=%0d",
                   SETS, WAYS, RRPV_BITS, BRRIP_THROTTLE_BITS, PSEL_BITS, SDM_SEL_BITS);
        $display("==================================================================");

        check_derived_widths;

        // =====================================================================
        $display("---- Secao 1: pos-reset ----");
        // =====================================================================
        check_rrpv("pos-reset set0/way0",  1'd0, SET_SDM_SRRIP_A, RRPV_MAX);
        check_rrpv("pos-reset set0/way1",  1'd1, SET_SDM_SRRIP_A, RRPV_MAX);
        check_rrpv("pos-reset set15/way0", 1'd0, SET_SDM_BRRIP_A, RRPV_MAX);
        check_rrpv("pos-reset set15/way1", 1'd1, SET_SDM_BRRIP_A, RRPV_MAX);
        check_rrpv("pos-reset set1/way0",  1'd0, SET_FOLLOWER_A,  RRPV_MAX);
        check_rrpv("pos-reset set16/way0", 1'd0, SET_SDM_SRRIP_B, RRPV_MAX);
        check_throttle_ctr("pos-reset", 2'd0);
        check_psel("pos-reset", PSEL_RESET);
        check_follower_policy("pos-reset (SRRIP favorecido pelo reset)", 1'b0);

        // mapeamento de papel (combinacional, independe de reset -- checado
        // aqui so por conveniencia de sequencia) para os 6 sets de teste:
        check_role("set0 (SDM-SRRIP A)",  SET_SDM_SRRIP_A, 1'b1, 1'b0);
        check_role("set16 (SDM-SRRIP B)", SET_SDM_SRRIP_B, 1'b1, 1'b0);
        check_role("set15 (SDM-BRRIP A)", SET_SDM_BRRIP_A, 1'b0, 1'b1);
        check_role("set31 (SDM-BRRIP B)", SET_SDM_BRRIP_B, 1'b0, 1'b1);
        check_role("set1 (seguidor A)",   SET_FOLLOWER_A,  1'b0, 1'b0);
        check_role("set2 (seguidor B)",   SET_FOLLOWER_B,  1'b0, 1'b0);

        // =====================================================================
        $display("---- Secao 2: invariante SDM-SRRIP (set0) sempre insere MID ----");
        // =====================================================================
        do_fill(1'd0, SET_SDM_SRRIP_A);
        check_rrpv("sec2 set0/way0 (SRRIP sempre MID)", 1'd0, SET_SDM_SRRIP_A, RRPV_INSERT_MID);
        do_fill(1'd1, SET_SDM_SRRIP_A);
        check_rrpv("sec2 set0/way1 (SRRIP sempre MID)", 1'd1, SET_SDM_SRRIP_A, RRPV_INSERT_MID);
        check_throttle_ctr("sec2 (fills SRRIP nao avancam throttle)", 2'd0);
        check_psel("sec2 (fill nao mexe no psel)", PSEL_RESET);

        // =====================================================================
        $display("---- Secao 3: throttle bimodal no SDM-BRRIP (set15), periodo=4 ----");
        // =====================================================================
        do_fill(1'd0, SET_SDM_BRRIP_A); // n=1: ctr_antes=0 -> RARO
        check_rrpv("sec3 n=1 set15/way0 (RARO)", 1'd0, SET_SDM_BRRIP_A, RRPV_INSERT_MID);
        do_fill(1'd1, SET_SDM_BRRIP_A); // n=2: ctr_antes=1 -> COMUM
        check_rrpv("sec3 n=2 set15/way1 (COMUM)", 1'd1, SET_SDM_BRRIP_A, RRPV_INSERT_FAR);
        do_fill(1'd0, SET_SDM_BRRIP_A); // n=3: ctr_antes=2 -> COMUM
        check_rrpv("sec3 n=3 set15/way0 (COMUM)", 1'd0, SET_SDM_BRRIP_A, RRPV_INSERT_FAR);
        do_fill(1'd1, SET_SDM_BRRIP_A); // n=4: ctr_antes=3 -> COMUM (ultimo antes do wrap)
        check_rrpv("sec3 n=4 set15/way1 (COMUM)", 1'd1, SET_SDM_BRRIP_A, RRPV_INSERT_FAR);
        do_fill(1'd0, SET_SDM_BRRIP_A); // n=5: ctr_antes=0 (wrap) -> RARO
        check_rrpv("sec3 n=5 set15/way0 (RARO, wraparound)", 1'd0, SET_SDM_BRRIP_A, RRPV_INSERT_MID);
        check_throttle_ctr("sec3 (5 fills BRRIP, ctr=5 mod 4=1)", 2'd1);
        check_psel("sec3 (fill nao mexe no psel)", PSEL_RESET);

        // =====================================================================
        $display("---- Secao 4: seguidor (set1) sob regime SRRIP (psel=32) ----");
        // =====================================================================
        check_follower_policy("antes da secao4 (ainda SRRIP)", 1'b0);
        do_fill(1'd0, SET_FOLLOWER_A);
        check_rrpv("sec4 set1/way0 (seguidor usando SRRIP)", 1'd0, SET_FOLLOWER_A, RRPV_INSERT_MID);
        check_throttle_ctr("sec4 (fill SRRIP-seguidor nao avanca throttle)", 2'd1);

        // =====================================================================
        $display("---- Secao 5: 4 misses no SDM-SRRIP (set0) empurram PSEL para baixo ----");
        // =====================================================================
        do_victim_search("sec5 miss#1 set0 (aging (2,2)->(3,3))", SET_SDM_SRRIP_A, 1'd0, 3);
        check_psel("sec5 apos miss#1 (32->31, decremento)", 6'd31);
        check_follower_policy("sec5 apos miss#1 (FLIP para BRRIP, MSB de 31 e 0)", 1'b1);

        do_victim_search("sec5 miss#2 set0 (despejo direto, (3,3) ja no MAX)", SET_SDM_SRRIP_A, 1'd0, 1);
        check_psel("sec5 apos miss#2 (31->30)", 6'd30);

        do_victim_search("sec5 miss#3 set0 (despejo direto)", SET_SDM_SRRIP_A, 1'd0, 1);
        check_psel("sec5 apos miss#3 (30->29)", 6'd29);

        do_victim_search("sec5 miss#4 set0 (despejo direto)", SET_SDM_SRRIP_A, 1'd0, 1);
        check_psel("sec5 apos miss#4 (29->28)", 6'd28);
        check_follower_policy("sec5 fim (ainda BRRIP, MSB de 28 e 0)", 1'b1);

        // =====================================================================
        $display("---- Secao 6: seguidor (set1) sob regime BRRIP (psel=28) ----");
        // =====================================================================
        do_fill(1'd1, SET_FOLLOWER_A); // ctr_antes=1 (continuando de onde a sec3 deixou) -> COMUM
        check_rrpv("sec6 set1/way1 (seguidor usando BRRIP, COMUM)", 1'd1, SET_FOLLOWER_A, RRPV_INSERT_FAR);
        check_throttle_ctr("sec6 (fill BRRIP-seguidor AVANCA o throttle global)", 2'd2);
        check_rrpv("sec6 set1/way0 residual da sec4 continua MID (nao afetado)", 1'd0, SET_FOLLOWER_A, RRPV_INSERT_MID);

        // =====================================================================
        $display("---- Secao 7: 4 misses no SDM-BRRIP (set15) empurram PSEL de volta ----");
        // =====================================================================
        do_victim_search("sec7 miss#1 set15 (despejo direto, way1 ja em FAR)", SET_SDM_BRRIP_A, 1'd1, 1);
        check_psel("sec7 apos miss#1 (28->29, incremento)", 6'd29);
        check_follower_policy("sec7 apos miss#1 (ainda BRRIP, MSB de 29 e 0)", 1'b1);

        do_victim_search("sec7 miss#2 set15 (despejo direto)", SET_SDM_BRRIP_A, 1'd1, 1);
        check_psel("sec7 apos miss#2 (29->30)", 6'd30);

        do_victim_search("sec7 miss#3 set15 (despejo direto)", SET_SDM_BRRIP_A, 1'd1, 1);
        check_psel("sec7 apos miss#3 (30->31)", 6'd31);
        check_follower_policy("sec7 apos miss#3 (ainda BRRIP, MSB de 31 e 0)", 1'b1);

        do_victim_search("sec7 miss#4 set15 (despejo direto)", SET_SDM_BRRIP_A, 1'd1, 1);
        check_psel("sec7 apos miss#4 (31->32, round-trip completo)", PSEL_RESET);
        check_follower_policy("sec7 fim (FLIP de volta para SRRIP, MSB de 32 e 1)", 1'b0);

        // =====================================================================
        $display("---- Secao 8: seguidor (set1) de volta ao regime SRRIP (psel=32) ----");
        // =====================================================================
        do_fill(1'd0, SET_FOLLOWER_A); // se fosse (erradamente) BRRIP: ctr_antes=2 -> COMUM -> FAR(3)
        check_rrpv("sec8 set1/way0 (seguidor volta a SRRIP, MID != FAR)", 1'd0, SET_FOLLOWER_A, RRPV_INSERT_MID);
        check_throttle_ctr("sec8 (fill SRRIP-seguidor nao avanca throttle)", 2'd2);

        // =====================================================================
        $display("---- Secao 9: robustez dos invariantes SDM apos round-trip do PSEL ----");
        // =====================================================================
        do_fill(1'd0, SET_SDM_SRRIP_A); // SDM-SRRIP: sempre MID, mesmo apos PSEL ter passado por BRRIP
        check_rrpv("sec9 set0/way0 (SDM-SRRIP imune ao historico do PSEL)", 1'd0, SET_SDM_SRRIP_A, RRPV_INSERT_MID);
        check_throttle_ctr("sec9 apos fill SRRIP (inalterado)", 2'd2);

        do_fill(1'd0, SET_SDM_BRRIP_A); // SDM-BRRIP: sempre throttle, ctr_antes=2 -> COMUM
        check_rrpv("sec9 set15/way0 (SDM-BRRIP imune ao PSEL, so o throttle manda)", 1'd0, SET_SDM_BRRIP_A, RRPV_INSERT_FAR);
        check_throttle_ctr("sec9 apos fill BRRIP (2->3)", 2'd3);

        // =====================================================================
        $display("---- Secao 10: hit->0 e aging identicos em QUALQUER papel (sets frescos) ----");
        // =====================================================================
        // set16 (SDM-SRRIP secundario, nunca tocado ate aqui)
        check_rrpv("sec10 set16/way0 pre-hit (ainda RRPV_MAX de reset)", 1'd0, SET_SDM_SRRIP_B, RRPV_MAX);
        do_hit(1'd0, SET_SDM_SRRIP_B);
        do_hit(1'd1, SET_SDM_SRRIP_B);
        check_rrpv("sec10 set16/way0 pos-hit", 1'd0, SET_SDM_SRRIP_B, 2'd0);
        check_rrpv("sec10 set16/way1 pos-hit", 1'd1, SET_SDM_SRRIP_B, 2'd0);
        do_victim_search("sec10 set16 (SDM-SRRIP): aging (0,0)->(3,3), 3 rodadas", SET_SDM_SRRIP_B, 1'd0, 5);
        check_psel("sec10 apos miss set16 (32->31, e SDM-SRRIP -> decrementa)", 6'd31);

        // set31 (SDM-BRRIP secundario, nunca tocado ate aqui)
        check_rrpv("sec10 set31/way0 pre-hit (ainda RRPV_MAX de reset)", 1'd0, SET_SDM_BRRIP_B, RRPV_MAX);
        do_hit(1'd0, SET_SDM_BRRIP_B);
        do_hit(1'd1, SET_SDM_BRRIP_B);
        check_rrpv("sec10 set31/way0 pos-hit", 1'd0, SET_SDM_BRRIP_B, 2'd0);
        check_rrpv("sec10 set31/way1 pos-hit", 1'd1, SET_SDM_BRRIP_B, 2'd0);
        do_victim_search("sec10 set31 (SDM-BRRIP): aging identico ao set16", SET_SDM_BRRIP_B, 1'd0, 5);
        check_psel("sec10 apos miss set31 (31->32, SDM-BRRIP incrementa)", PSEL_RESET);

        // set2 (seguidor secundario, nunca tocado ate aqui)
        check_rrpv("sec10 set2/way0 pre-hit (ainda RRPV_MAX de reset)", 1'd0, SET_FOLLOWER_B, RRPV_MAX);
        do_hit(1'd0, SET_FOLLOWER_B);
        do_hit(1'd1, SET_FOLLOWER_B);
        check_rrpv("sec10 set2/way0 pos-hit", 1'd0, SET_FOLLOWER_B, 2'd0);
        check_rrpv("sec10 set2/way1 pos-hit", 1'd1, SET_FOLLOWER_B, 2'd0);
        do_victim_search("sec10 set2 (seguidor): aging identico aos SDMs", SET_FOLLOWER_B, 1'd0, 5);
        check_psel("sec10 apos miss set2 (seguidor nao mexe no psel, continua 32)", PSEL_RESET);

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
