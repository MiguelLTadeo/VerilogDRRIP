// =============================================================================
// cache_datapath_tb.v
// Testbench autoverificavel para cache_datapath.v (Fase 6 - PI4 UNIPAMPA).
//
// Como compilar/simular no ModelSim (a partir de /home/miguel/verilog):
//
//   vlib work
//   vlog rtl/cache_addr.v rtl/cache_datapath.v tb/cache_datapath_tb.v
//   vsim -c work.cache_datapath_tb -do "run -all; quit -f"
//
// (ou use o script pronto: `vsim -c -do sim/run_cache_datapath.do`)
//
// NOTA: rtl/cache_addr.v (Fase 1) e compilado e instanciado neste TB
// SOMENTE como referencia para o cross-check automatico das larguras
// derivadas (ver check_derived_widths abaixo, e instancia addr_ref mais
// abaixo) -- nao participa do datapath sob teste em nenhum outro aspecto
// (ver DECISAO DE PROJETO #1 em rtl/cache_datapath.v sobre por que
// cache_datapath.v NAO instancia cache_addr.v para o storage de verdade).
//
// Config de validacao sob teste (ver plano-cache.md, mesma config das
// Fases 1-5):
//   ADDR_W=8, BLK_B=4, SETS=4, WAYS=2 -> OFFSET_W=2 INDEX_W=2 TAG_W=4 WAY_W=1
//
// -----------------------------------------------------------------------
// IMPORTANTE: este testbench NAO instancia nenhum modulo repl_* (repl_lru/
// repl_srrip/repl_brrip). Como o plano pede, a interface de substituicao e
// PLUGAVEL e o cache_datapath e agnostico a politica (ver DECISAO DE
// PROJETO #2 no cabecalho de rtl/cache_datapath.v); este TB atua como um
// "stub" manual de politica, dirigindo victim_way_i/victim_valid_i
// diretamente, o que permite testar tanto o caso "resposta imediata" (como
// seria com repl_lru, combinacional) quanto o caso "resposta com atraso de
// N ciclos" (como seria com repl_srrip/repl_brrip, FSM de aging) sem
// depender de nenhum deles. A integracao real com um repl_* de verdade
// fica para a Fase 8 (measure_tb), conforme o plano.
//
// -----------------------------------------------------------------------
// Enderecos e dados usados no roteiro (todos no MESMO set, index=1, para
// forcar contencao/eviction entre as 2 vias -- WAYS=2):
//
//   addr A = {tag=4'h1, idx=2'b01, off=2'b00} = 8'b0001_01_00 = 8'h14
//   addr B = {tag=4'h2, idx=2'b01, off=2'b00} = 8'b0010_01_00 = 8'h24
//   addr C = {tag=4'h3, idx=2'b01, off=2'b00} = 8'b0011_01_00 = 8'h34
//   addr D = {tag=4'h4, idx=2'b01, off=2'b00} = 8'b0100_01_00 = 8'h44
//
//   DATA_A   = 32'hAAAA_0001 (bloco buscado da memoria no fill de A)
//   DATA_A_W = 32'hDEAD_BEEF (valor escrito em HIT de escrita sobre A)
//   DATA_B   = 32'h1234_5678 (bloco buscado da memoria no fill de B)
//   DATA_C   = 32'hCAFE_F00D (bloco buscado da memoria no fill de C)
//   DATA_D   = 32'h5555_0004 (bloco buscado da memoria no fill de D)
//
// -----------------------------------------------------------------------
// Roteiro e valores ESPERADOS calculados na mao (index=1 em TODO passo):
//
//  1) miss A (cache vazia, via0 livre)      -> miss_o, index=1
//     fill via0, wait=0 (resposta imediata) -> fill_done, way=0,
//       rdata=DATA_A, wb_req=0 (via0 estava invalida)
//     estado: way0={tag=1,valid=1,dirty=0,data=DATA_A}
//
//  2) hit A (leitura)                       -> hit, way=0, rdata=DATA_A
//
//  3) hit A (escrita DATA_A_W)              -> hit, way=0, sem rdata_valid
//     estado: way0={tag=1,valid=1,dirty=1,data=DATA_A_W}
//
//  4) hit A (leitura, confirma escrita)     -> hit, way=0, rdata=DATA_A_W
//
//  5) miss B (via0 ocupada c/ tag1, via1 livre) -> miss_o, index=1
//     fill via1, wait=0                     -> fill_done, way=1,
//       rdata=DATA_B, wb_req=0 (via1 estava invalida)
//     estado: way1={tag=2,valid=1,dirty=0,data=DATA_B}
//     (agora as 2 vias do set1 estao ocupadas: way0=tag1 SUJA, way1=tag2 limpa)
//
//  6) miss C (nenhuma via livre; tag3 nao bate com tag1 nem tag2) -> miss_o
//     politica (stub) escolhe via0 (a suja) como vitima, com atraso de 2
//     ciclos (simula latencia multi-ciclo tipo RRIP) -- durante a espera,
//     confere ready_o=0/sem pulsos, e injeta um req_i "espurio" (que deve
//     ser IGNORADO, pois S_WAIT_VICTIM nao le req_i).
//     fill via0                              -> fill_done, way=0,
//       rdata=DATA_C, WB_REQ=1 (via0 estava valida E suja),
//       wb_addr=endereco de A (0x14), wb_data=DATA_A_W
//     estado: way0={tag=3,valid=1,dirty=0,data=DATA_C}; way1 inalterado
//
//  7) hit C (leitura)                       -> hit, way=0, rdata=DATA_C
//  8) hit B (leitura, via1 intacta)         -> hit, way=1, rdata=DATA_B
//
//  9) miss D (nenhuma via livre; tag4 novo) -> miss_o
//     politica escolhe via1 (LIMPA, nunca escrita) como vitima, atraso de
//     1 ciclo.
//     fill via1                              -> fill_done, way=1,
//       rdata=DATA_D, WB_REQ=0 (via1 estava valida mas LIMPA -- sem write-back)
//     estado: way1={tag=4,valid=1,dirty=0,data=DATA_D}; way0 inalterado
//
// 10) hit D (leitura)                       -> hit, way=1, rdata=DATA_D
// 11) hit C (leitura, via0 intacta)         -> hit, way=0, rdata=DATA_C
// -----------------------------------------------------------------------
//
// Passos 12-15 usam DOIS OUTROS sets (index=0 e index=3, os EXTREMOS do
// espaco de 4 sets) para exercitar o fatiamento de endereco PROPRIO de
// cache_datapath.v (offset_c/index_c/tag_c -- ver DECISAO DE PROJETO #1
// no cabecalho do RTL: esta e uma logica DUPLICADA da de cache_addr.v, e
// os passos 1-11 acima nunca a exercitaram fora de index=1):
//
//   addr E = {tag=4'h5, idx=2'b00, off=2'b00} = 8'b0101_00_00 = 8'h50 (set0)
//   addr F = {tag=4'h6, idx=2'b11, off=2'b00} = 8'b0110_11_00 = 8'h6C (set3)
//   DATA_E = 32'hE0E0_E0E0 (bloco buscado no fill de E)
//   DATA_F = 32'hF0F0_F0F0 (bloco buscado no fill de F)
//
// 12) miss E (set0, via0 livre)             -> fill via0, index=0, rdata=DATA_E
// 13) hit E (leitura, confirma set0)        -> hit, way=0, index=0, rdata=DATA_E
// 14) miss F (set3, via0 livre)             -> fill via0, index=3, rdata=DATA_F
// 15) hit F (leitura, confirma set3)        -> hit, way=0, index=3, rdata=DATA_F
//     -> independencia: sets 0 e 3 nao colidem entre si nem com o set1
//        (re-checado logo em seguida: C ainda em set1/via0, B ainda em
//        set1/via1, D ainda em set1/via1 -- ver passo 16).
// 16) re-confirma set1 intacto apos tocar set0/set3: hit C (way0) e re-fill
//     D->via1 nao se aplicam mais (D ja foi sobrescrito no passo 9); apenas
//     hit C (way0,index=1) e checado, provando que mexer em sets 0/3 nao
//     vazou para o set1.
//
// Passo 17 exercita o CONTRATO de req_i (pulso de 1 ciclo, ver comentario
// detalhado na porta req_i em rtl/cache_datapath.v): req_i e mantido em
// nivel alto por 3 ciclos consecutivos sobre o MESMO endereco de HIT (E,
// set0) -- comportamento DETERMINISTICO esperado desta implementacao (SEM
// guard de hardware, por decisao documentada): cada um dos 3 ciclos em que
// req_i=1 e amostrado em S_IDLE conta como uma transacao INDEPENDENTE,
// entao hit_o deve pulsar EXATAMENTE 3 vezes (nem mais, nem menos) -- a
// contagem e sempre proporcional ao numero de ciclos em que req_i esteve
// alto, nunca duplicada/perdida por conta propria do hardware.
// -----------------------------------------------------------------------
// =============================================================================

`timescale 1ns/1ps

module cache_datapath_tb;

    // ---- parametros da config de validacao ---------------------------------
    localparam ADDR_W = 8;
    localparam BLK_B  = 4;
    localparam SETS   = 4;
    localparam WAYS   = 2;

    localparam OFFSET_W = 2; // $clog2(BLK_B)  -- calculado a mao
    localparam INDEX_W  = 2; // $clog2(SETS)
    localparam TAG_W    = 4; // ADDR_W-INDEX_W-OFFSET_W
    localparam WAY_W    = 1; // $clog2(WAYS)

    // ---- enderecos/dados do roteiro (ver cabecalho) -------------------------
    localparam [ADDR_W-1:0] ADDR_A = 8'h14;
    localparam [ADDR_W-1:0] ADDR_B = 8'h24;
    localparam [ADDR_W-1:0] ADDR_C = 8'h34;
    localparam [ADDR_W-1:0] ADDR_D = 8'h44;
    localparam [INDEX_W-1:0] IDX1  = 2'd1; // set comum a A/B/C/D

    localparam [BLK_B*8-1:0] DATA_A   = 32'hAAAA_0001;
    localparam [BLK_B*8-1:0] DATA_A_W = 32'hDEAD_BEEF;
    localparam [BLK_B*8-1:0] DATA_B   = 32'h1234_5678;
    localparam [BLK_B*8-1:0] DATA_C   = 32'hCAFE_F00D;
    localparam [BLK_B*8-1:0] DATA_D   = 32'h5555_0004;

    // ---- enderecos/dados para variacao de INDEX (passos 12-15, ver cabecalho) --
    localparam [ADDR_W-1:0] ADDR_E = 8'h50; // tag=5, index=0 (extremo inferior)
    localparam [ADDR_W-1:0] ADDR_F = 8'h6C; // tag=6, index=3 (extremo superior)
    localparam [INDEX_W-1:0] IDX0  = 2'd0;
    localparam [INDEX_W-1:0] IDX3  = 2'd3;

    localparam [BLK_B*8-1:0] DATA_E = 32'hE0E0_E0E0;
    localparam [BLK_B*8-1:0] DATA_F = 32'hF0F0_F0F0;

    // ---- sinais de interface com o DUT --------------------------------------
    reg                   clk;
    reg                   rst;

    reg                   req_i;
    reg                   we_i;
    reg  [ADDR_W-1:0]     addr_i;
    reg  [BLK_B*8-1:0]    wdata_i;
    wire                  ready_o;

    wire                  rdata_valid_o;
    wire [BLK_B*8-1:0]    rdata_o;

    wire                  hit_o;
    wire                  miss_o;
    wire                  fill_done_o;
    wire [INDEX_W-1:0]    access_index_o;
    wire [WAY_W-1:0]      access_way_o;

    reg                   victim_valid_i;
    reg  [WAY_W-1:0]      victim_way_i;

    reg  [BLK_B*8-1:0]    fill_data_i;

    wire                  wb_req_o;
    wire [ADDR_W-1:0]     wb_addr_o;
    wire [BLK_B*8-1:0]    wb_data_o;

    integer errors;

    // ---- instancia do DUT -----------------------------------------------------
    cache_datapath #(
        .ADDR_W (ADDR_W),
        .BLK_B  (BLK_B),
        .SETS   (SETS),
        .WAYS   (WAYS)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .req_i           (req_i),
        .we_i            (we_i),
        .addr_i          (addr_i),
        .wdata_i         (wdata_i),
        .ready_o         (ready_o),
        .rdata_valid_o   (rdata_valid_o),
        .rdata_o         (rdata_o),
        .hit_o           (hit_o),
        .miss_o          (miss_o),
        .fill_done_o     (fill_done_o),
        .access_index_o  (access_index_o),
        .access_way_o    (access_way_o),
        .victim_valid_i  (victim_valid_i),
        .victim_way_i    (victim_way_i),
        .fill_data_i     (fill_data_i),
        .wb_req_o        (wb_req_o),
        .wb_addr_o       (wb_addr_o),
        .wb_data_o       (wb_data_o)
    );

    // ---- instancia de REFERENCIA de cache_addr.v (Fase 1) ---------------------
    // usada SOMENTE para o cross-check automatico de check_derived_widths
    // abaixo -- NAO participa do datapath sob teste. Todas as portas de
    // dado/escrita/leitura sao amarradas a constantes (nunca acionadas);
    // clk/rst sao compartilhados com o resto do TB so por conveniencia (o
    // reset sincrono deste modulo e inofensivo, so zera seu proprio storage
    // interno, que nunca e lido). RRPV_BITS fica no valor padrao do modulo
    // (nao influencia OFFSET_W/INDEX_W/TAG_W/WAY_W, que so dependem de
    // ADDR_W/BLK_B/SETS/WAYS).
    cache_addr #(
        .ADDR_W (ADDR_W),
        .BLK_B  (BLK_B),
        .SETS   (SETS),
        .WAYS   (WAYS)
    ) addr_ref (
        .clk         (clk),
        .rst         (rst),
        .addr_i      ({ADDR_W{1'b0}}),
        .tag_o       (),
        .index_o     (),
        .offset_o    (),
        .wr_en_i     (1'b0),
        .wr_way_i    ({WAY_W{1'b0}}),
        .wr_index_i  ({INDEX_W{1'b0}}),
        .wr_valid_i  (1'b0),
        .wr_tag_i    ({TAG_W{1'b0}}),
        .wr_data_i   ({(BLK_B*8){1'b0}}),
        .rd_way_i    ({WAY_W{1'b0}}),
        .rd_index_i  ({INDEX_W{1'b0}}),
        .rd_valid_o  (),
        .rd_tag_o    (),
        .rd_data_o   ()
    );

    // ---- geracao de clock (100 MHz simulado, so existe no TB) ----------------
    always #5 clk = ~clk;

    // ---- checagem da propria config derivada (localparam do DUT) --------------
    // cross-check DUPLO: (1) contra os valores calculados a mao (OFFSET_W/
    // INDEX_W/TAG_W/WAY_W localparams deste TB) e (2) contra os MESMOS
    // localparams derivados dentro de rtl/cache_addr.v (addr_ref acima) --
    // esta segunda comparacao pega automaticamente qualquer DERIVA futura
    // entre as duas formulas duplicadas (cache_addr.v e cache_datapath.v
    // usam a MESMA formula por construcao, ver DECISAO DE PROJETO #1 no
    // cabecalho do RTL, mas nada IMPEDE as duas de divergirem se alguem
    // editar so um dos dois arquivos no futuro -- este teste torna essa
    // divergencia um FALHA de teste automatico, nao um bug silencioso).
    task check_derived_widths;
    begin
        if (dut.OFFSET_W !== OFFSET_W || dut.INDEX_W !== INDEX_W ||
            dut.TAG_W !== TAG_W || dut.WAY_W !== WAY_W) begin
            errors = errors + 1;
            $display("FALHA larguras derivadas (dut vs esperado a mao): esperado OFFSET_W=%0d INDEX_W=%0d TAG_W=%0d WAY_W=%0d | obtido OFFSET_W=%0d INDEX_W=%0d TAG_W=%0d WAY_W=%0d",
                       OFFSET_W, INDEX_W, TAG_W, WAY_W,
                       dut.OFFSET_W, dut.INDEX_W, dut.TAG_W, dut.WAY_W);
        end else begin
            $display("OK larguras derivadas (dut vs esperado a mao): OFFSET_W=%0d INDEX_W=%0d TAG_W=%0d WAY_W=%0d",
                       dut.OFFSET_W, dut.INDEX_W, dut.TAG_W, dut.WAY_W);
        end

        if (dut.OFFSET_W !== addr_ref.OFFSET_W || dut.INDEX_W !== addr_ref.INDEX_W ||
            dut.TAG_W !== addr_ref.TAG_W || dut.WAY_W !== addr_ref.WAY_W) begin
            errors = errors + 1;
            $display("FALHA cross-check cache_datapath.v vs cache_addr.v: dut OFFSET_W=%0d INDEX_W=%0d TAG_W=%0d WAY_W=%0d | cache_addr.v OFFSET_W=%0d INDEX_W=%0d TAG_W=%0d WAY_W=%0d -- as DUAS formulas divergiram, corrigir a deriva!",
                       dut.OFFSET_W, dut.INDEX_W, dut.TAG_W, dut.WAY_W,
                       addr_ref.OFFSET_W, addr_ref.INDEX_W, addr_ref.TAG_W, addr_ref.WAY_W);
        end else begin
            $display("OK cross-check cache_datapath.v vs cache_addr.v: formulas de largura derivada IDENTICAS (OFFSET_W=%0d INDEX_W=%0d TAG_W=%0d WAY_W=%0d)",
                       addr_ref.OFFSET_W, addr_ref.INDEX_W, addr_ref.TAG_W, addr_ref.WAY_W);
        end
    end
    endtask

    task check_reset;
    begin
        if (ready_o !== 1'b1 || hit_o !== 1'b0 || miss_o !== 1'b0 || fill_done_o !== 1'b0) begin
            errors = errors + 1;
            $display("FALHA pos-reset: esperado ready=1 hit=0 miss=0 fill=0 | obtido ready=%0b hit=%0b miss=%0b fill=%0b",
                       ready_o, hit_o, miss_o, fill_done_o);
        end else begin
            $display("OK pos-reset: ready=1, sem pulsos pendentes");
        end
    end
    endtask

    // ---- emite 1 requisicao (pulso de req_i por exatamente 1 ciclo) -----------
    // retorna com o TB posicionado logo APOS a borda de clock que processou
    // a requisicao -- hit_o/miss_o/access_*_o ja estao validos p/ checagem
    // imediatamente apos a chamada (ver nota de timing no cabecalho do TB).
    task do_req(input [ADDR_W-1:0] addr, input we, input [BLK_B*8-1:0] wdata);
    begin
        @(negedge clk);
        req_i   = 1'b1;
        we_i    = we;
        addr_i  = addr;
        wdata_i = wdata;
        @(negedge clk);
        req_i   = 1'b0;
        we_i    = 1'b0;
        addr_i  = {ADDR_W{1'b0}};
        wdata_i = {(BLK_B*8){1'b0}};
    end
    endtask

    // ---- checagem de um MISS recem detectado (miss_o pulsando) ---------------
    task check_miss(input [255:0] label, input [INDEX_W-1:0] exp_index);
    begin
        if (hit_o !== 1'b0 || miss_o !== 1'b1 || fill_done_o !== 1'b0 ||
            access_index_o !== exp_index || ready_o !== 1'b0) begin
            errors = errors + 1;
            $display("FALHA miss [%0s]: esperado hit=0 miss=1 fill=0 index=%0d ready=0 | obtido hit=%0b miss=%0b fill=%0b index=%0d ready=%0b",
                       label, exp_index, hit_o, miss_o, fill_done_o, access_index_o, ready_o);
        end else begin
            $display("OK miss [%0s]: index=%0d (ready_o corretamente baixo, aguardando via vitima)",
                       label, access_index_o);
        end
    end
    endtask

    // ---- checagem de um HIT de leitura ----------------------------------------
    task check_hit_read(input [255:0] label, input [WAY_W-1:0] exp_way,
                         input [INDEX_W-1:0] exp_index, input [BLK_B*8-1:0] exp_data);
    begin
        if (hit_o !== 1'b1 || miss_o !== 1'b0 || fill_done_o !== 1'b0 ||
            access_way_o !== exp_way || access_index_o !== exp_index ||
            rdata_valid_o !== 1'b1 || rdata_o !== exp_data || ready_o !== 1'b1) begin
            errors = errors + 1;
            $display("FALHA hit leitura [%0s]: esperado way=%0d index=%0d rdata=%h | obtido hit=%0b way=%0d index=%0d rvalid=%0b rdata=%h ready=%0b",
                       label, exp_way, exp_index, exp_data,
                       hit_o, access_way_o, access_index_o, rdata_valid_o, rdata_o, ready_o);
        end else begin
            $display("OK hit leitura [%0s]: way=%0d index=%0d rdata=%h",
                       label, access_way_o, access_index_o, rdata_o);
        end
    end
    endtask

    // ---- checagem de um HIT de escrita (sem rdata_valid) -----------------------
    task check_hit_write(input [255:0] label, input [WAY_W-1:0] exp_way, input [INDEX_W-1:0] exp_index);
    begin
        if (hit_o !== 1'b1 || miss_o !== 1'b0 || fill_done_o !== 1'b0 ||
            access_way_o !== exp_way || access_index_o !== exp_index ||
            rdata_valid_o !== 1'b0 || ready_o !== 1'b1) begin
            errors = errors + 1;
            $display("FALHA hit escrita [%0s]: esperado way=%0d index=%0d rvalid=0 | obtido hit=%0b way=%0d index=%0d rvalid=%0b ready=%0b",
                       label, exp_way, exp_index, hit_o, access_way_o, access_index_o, rdata_valid_o, ready_o);
        end else begin
            $display("OK hit escrita [%0s]: way=%0d index=%0d", label, access_way_o, access_index_o);
        end
    end
    endtask

    // ---- checagem de um ciclo de ESPERA (S_WAIT_VICTIM, victim_valid_i=0) -----
    task check_idle_wait(input [255:0] label);
    begin
        if (ready_o !== 1'b0 || hit_o !== 1'b0 || miss_o !== 1'b0 || fill_done_o !== 1'b0) begin
            errors = errors + 1;
            $display("FALHA espera [%0s]: esperado ready=0 sem pulsos | obtido ready=%0b hit=%0b miss=%0b fill=%0b",
                       label, ready_o, hit_o, miss_o, fill_done_o);
        end else begin
            $display("OK espera [%0s]: ready=0, sem pulsos espurios (via vitima ainda nao respondida)", label);
        end
    end
    endtask

    // ---- fornece a via vitima (stub de politica) e aguarda o fill -------------
    // wait_cycles=0 simula uma politica de resposta imediata (ex.: repl_lru,
    // combinacional); wait_cycles>0 simula uma politica de resposta
    // multi-ciclo (ex.: repl_srrip/repl_brrip, FSM de aging). Retorna com o
    // TB posicionado logo apos a borda que consumiu victim_valid_i -- todas
    // as saidas do fill (fill_done_o/access_*_o/rdata_*/wb_*) ja validas.
    task supply_victim(input [WAY_W-1:0] way, input [BLK_B*8-1:0] fdata, input integer wait_cycles);
        integer c;
    begin
        victim_way_i   = way;
        fill_data_i    = fdata;
        victim_valid_i = 1'b0;
        for (c = 0; c < wait_cycles; c = c + 1) begin
            @(negedge clk);
        end
        victim_valid_i = 1'b1;
        @(negedge clk);
        victim_valid_i = 1'b0;
    end
    endtask

    // ---- checagem de um FILL concluido (miss resolvido) ------------------------
    task check_fill(input [255:0] label, input [WAY_W-1:0] exp_way, input [INDEX_W-1:0] exp_index,
                     input [BLK_B*8-1:0] exp_rdata,
                     input exp_wbreq, input [ADDR_W-1:0] exp_wbaddr, input [BLK_B*8-1:0] exp_wbdata);
    begin
        if (fill_done_o !== 1'b1 || hit_o !== 1'b0 || miss_o !== 1'b0 ||
            access_way_o !== exp_way || access_index_o !== exp_index ||
            rdata_valid_o !== 1'b1 || rdata_o !== exp_rdata || ready_o !== 1'b1) begin
            errors = errors + 1;
            $display("FALHA fill [%0s]: esperado way=%0d index=%0d rdata=%h | obtido fill=%0b way=%0d index=%0d rvalid=%0b rdata=%h ready=%0b",
                       label, exp_way, exp_index, exp_rdata,
                       fill_done_o, access_way_o, access_index_o, rdata_valid_o, rdata_o, ready_o);
        end else begin
            $display("OK fill [%0s]: way=%0d index=%0d rdata=%h", label, access_way_o, access_index_o, rdata_o);
        end

        if (wb_req_o !== exp_wbreq) begin
            errors = errors + 1;
            $display("FALHA write-back [%0s]: esperado wb_req=%0b | obtido wb_req=%0b",
                       label, exp_wbreq, wb_req_o);
        end else if (exp_wbreq && (wb_addr_o !== exp_wbaddr || wb_data_o !== exp_wbdata)) begin
            errors = errors + 1;
            $display("FALHA write-back [%0s]: esperado wb_addr=%h wb_data=%h | obtido wb_addr=%h wb_data=%h",
                       label, exp_wbaddr, exp_wbdata, wb_addr_o, wb_data_o);
        end else if (exp_wbreq) begin
            $display("OK write-back [%0s]: wb_req=1 (wb_addr=%h wb_data=%h)",
                       label, wb_addr_o, wb_data_o);
        end else begin
            $display("OK write-back [%0s]: wb_req=0 (sem eviction suja)", label);
        end
    end
    endtask

    initial begin
        errors  = 0;
        clk     = 1'b0;
        rst     = 1'b1;
        req_i   = 1'b0;
        we_i    = 1'b0;
        addr_i  = {ADDR_W{1'b0}};
        wdata_i = {(BLK_B*8){1'b0}};
        victim_valid_i = 1'b0;
        victim_way_i   = {WAY_W{1'b0}};
        fill_data_i    = {(BLK_B*8){1'b0}};

        // libera reset sincrono apos algumas bordas de clock
        @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        $display("==================================================================");
        $display("cache_datapath_tb: config ADDR_W=%0d BLK_B=%0d SETS=%0d WAYS=%0d",
                   ADDR_W, BLK_B, SETS, WAYS);
        $display("==================================================================");

        check_derived_widths;
        check_reset;

        // 1) miss compulsorio de A (cache vazia, via0 livre) --------------------
        $display("---- 1) miss compulsorio A (via0 livre) ----");
        do_req(ADDR_A, 1'b0, {(BLK_B*8){1'b0}});
        check_miss("A", IDX1);
        supply_victim(1'd0, DATA_A, 0); // resposta imediata (tipo LRU)
        check_fill("A", 1'd0, IDX1, DATA_A, 1'b0, {ADDR_W{1'b0}}, {(BLK_B*8){1'b0}});

        // 2) hit de leitura em A -------------------------------------------------
        $display("---- 2) hit leitura A ----");
        do_req(ADDR_A, 1'b0, {(BLK_B*8){1'b0}});
        check_hit_read("A", 1'd0, IDX1, DATA_A);

        // 3) hit de escrita em A (marca dirty, write-back) ------------------------
        $display("---- 3) hit escrita A ----");
        do_req(ADDR_A, 1'b1, DATA_A_W);
        check_hit_write("A", 1'd0, IDX1);

        // 4) hit de leitura em A confirma a escrita -------------------------------
        $display("---- 4) hit leitura A (confirma escrita) ----");
        do_req(ADDR_A, 1'b0, {(BLK_B*8){1'b0}});
        check_hit_read("A pos-escrita", 1'd0, IDX1, DATA_A_W);

        // 5) miss compulsorio de B (via0 ocupada, via1 livre) ----------------------
        $display("---- 5) miss compulsorio B (via1 livre) ----");
        do_req(ADDR_B, 1'b0, {(BLK_B*8){1'b0}});
        check_miss("B", IDX1);
        supply_victim(1'd1, DATA_B, 0); // resposta imediata
        check_fill("B", 1'd1, IDX1, DATA_B, 1'b0, {ADDR_W{1'b0}}, {(BLK_B*8){1'b0}});

        // 6) miss de C: SEM via livre -> evict via0 (SUJA) -> write-back -----------
        $display("---- 6) miss C (sem via livre, evict via0 SUJA -> write-back) ----");
        do_req(ADDR_C, 1'b0, {(BLK_B*8){1'b0}});
        check_miss("C", IDX1);

        // simula politica multi-ciclo (2 ciclos de espera, tipo RRIP com aging) e
        // confere ready_o=0/sem pulsos espurios durante a espera
        victim_way_i   = 1'd0;
        fill_data_i    = DATA_C;
        victim_valid_i = 1'b0;
        @(negedge clk);
        check_idle_wait("espera 1/2, sem req_i espurio");

        // injeta um req_i ESPURIO durante a espera -- deve ser IGNORADO, pois
        // S_WAIT_VICTIM nunca le req_i (contrato: o integrador so deve
        // apresentar req_i quando ready_o=1)
        req_i  = 1'b1;
        we_i   = 1'b0;
        addr_i = ADDR_B;
        @(negedge clk);
        check_idle_wait("espera 2/2 (req_i espurio)");
        req_i  = 1'b0;
        addr_i = {ADDR_W{1'b0}};

        victim_valid_i = 1'b1;
        @(negedge clk);
        victim_valid_i = 1'b0;
        check_fill("C", 1'd0, IDX1, DATA_C, 1'b1, ADDR_A, DATA_A_W);

        // 7) hit de leitura em C (via0 recem-preenchida) ----------------------------
        $display("---- 7) hit leitura C ----");
        do_req(ADDR_C, 1'b0, {(BLK_B*8){1'b0}});
        check_hit_read("C", 1'd0, IDX1, DATA_C);

        // 8) hit de leitura em B (via1 intacta, nao afetada pela eviction de A) -----
        $display("---- 8) hit leitura B (via1 intacta) ----");
        do_req(ADDR_B, 1'b0, {(BLK_B*8){1'b0}});
        check_hit_read("B", 1'd1, IDX1, DATA_B);

        // 9) miss de D: SEM via livre -> evict via1 (LIMPA) -> SEM write-back -------
        $display("---- 9) miss D (sem via livre, evict via1 LIMPA -> sem write-back) ----");
        do_req(ADDR_D, 1'b0, {(BLK_B*8){1'b0}});
        check_miss("D", IDX1);
        supply_victim(1'd1, DATA_D, 1); // resposta com 1 ciclo de atraso
        check_fill("D", 1'd1, IDX1, DATA_D, 1'b0, {ADDR_W{1'b0}}, {(BLK_B*8){1'b0}});

        // 10) hit de leitura em D ----------------------------------------------------
        $display("---- 10) hit leitura D ----");
        do_req(ADDR_D, 1'b0, {(BLK_B*8){1'b0}});
        check_hit_read("D", 1'd1, IDX1, DATA_D);

        // 11) hit de leitura em C (via0 intacta, nao afetada pela eviction de B) ----
        $display("---- 11) hit leitura C (via0 intacta) ----");
        do_req(ADDR_C, 1'b0, {(BLK_B*8){1'b0}});
        check_hit_read("C final", 1'd0, IDX1, DATA_C);

        // ---- 12-16) VARIACAO DE INDEX: exercita offset_c/index_c/tag_c em -----
        //      outros sets alem do IDX1 usado ate aqui (ver nota no cabecalho
        //      do TB) -- prova que o fatiamento de endereco PROPRIO de
        //      cache_datapath.v (duplicado de cache_addr.v, ver DECISAO DE
        //      PROJETO #1 no RTL) funciona nos EXTREMOS do espaco de sets
        //      (index=0 e index=3) e que sets diferentes nao colidem no
        //      storage.
        $display("---- 12) miss compulsorio E (set0, via0 livre) ----");
        do_req(ADDR_E, 1'b0, {(BLK_B*8){1'b0}});
        check_miss("E", IDX0);
        supply_victim(1'd0, DATA_E, 0);
        check_fill("E", 1'd0, IDX0, DATA_E, 1'b0, {ADDR_W{1'b0}}, {(BLK_B*8){1'b0}});

        $display("---- 13) hit leitura E (confirma set0) ----");
        do_req(ADDR_E, 1'b0, {(BLK_B*8){1'b0}});
        check_hit_read("E", 1'd0, IDX0, DATA_E);

        $display("---- 14) miss compulsorio F (set3, via0 livre) ----");
        do_req(ADDR_F, 1'b0, {(BLK_B*8){1'b0}});
        check_miss("F", IDX3);
        supply_victim(1'd0, DATA_F, 0);
        check_fill("F", 1'd0, IDX3, DATA_F, 1'b0, {ADDR_W{1'b0}}, {(BLK_B*8){1'b0}});

        $display("---- 15) hit leitura F (confirma set3) ----");
        do_req(ADDR_F, 1'b0, {(BLK_B*8){1'b0}});
        check_hit_read("F", 1'd0, IDX3, DATA_F);

        $display("---- 16) independencia: set1 (C) intacto apos tocar set0/set3 ----");
        do_req(ADDR_C, 1'b0, {(BLK_B*8){1'b0}});
        check_hit_read("C apos set0/set3", 1'd0, IDX1, DATA_C);
        // e set0/set3 tambem continuam intactos entre si (nao colidiram)
        do_req(ADDR_E, 1'b0, {(BLK_B*8){1'b0}});
        check_hit_read("E apos F", 1'd0, IDX0, DATA_E);
        do_req(ADDR_F, 1'b0, {(BLK_B*8){1'b0}});
        check_hit_read("F apos E", 1'd0, IDX3, DATA_F);

        // ---- 17) CONTRATO de req_i: nivel sustentado por 3 ciclos -------------
        //      (ver comentario detalhado na porta req_i em
        //      rtl/cache_datapath.v e nota no cabecalho deste TB). req_i e
        //      mantido em 1 (endereco E, que ja esta em HIT em way0/set0)
        //      por 3 bordas de clock consecutivas SEM ser derrubado entre
        //      elas -- viola o contrato de "pulso de 1 ciclo", mas o
        //      comportamento resultante e DETERMINISTICO e DOCUMENTADO: cada
        //      ciclo em que req_i=1 e amostrado em S_IDLE conta como uma
        //      transacao INDEPENDENTE. Esperado: EXATAMENTE 3 pulsos de
        //      hit_o (proporcional aos 3 ciclos, nem mais nem menos) -- sem
        //      guard de hardware (decisao deliberada, documentada no RTL).
        $display("---- 17) req_i sustentado por 3 ciclos (contrato violado, contagem 3x) ----");
        @(negedge clk);
        req_i   = 1'b1;
        we_i    = 1'b0;
        addr_i  = ADDR_E;
        wdata_i = {(BLK_B*8){1'b0}};
        @(negedge clk); // 1a borda com req_i=1 processada -> hit #1 visivel agora
        check_hit_read("E sustentado 1/3", 1'd0, IDX0, DATA_E);
        // req_i permanece em 1 (nao alterado) -------------------------------
        @(negedge clk); // 2a borda com req_i=1 processada -> hit #2 visivel agora
        check_hit_read("E sustentado 2/3", 1'd0, IDX0, DATA_E);
        // req_i permanece em 1 (nao alterado) -------------------------------
        @(negedge clk); // 3a borda com req_i=1 processada -> hit #3 visivel agora
        check_hit_read("E sustentado 3/3", 1'd0, IDX0, DATA_E);
        // agora derruba req_i -- proximo ciclo NAO deve gerar hit/miss algum
        req_i   = 1'b0;
        addr_i  = {ADDR_W{1'b0}};
        @(negedge clk);
        if (hit_o !== 1'b0 || miss_o !== 1'b0) begin
            errors = errors + 1;
            $display("FALHA req_i sustentado: apos derrubar req_i, esperado hit=0 miss=0 | obtido hit=%0b miss=%0b",
                       hit_o, miss_o);
        end else begin
            $display("OK req_i sustentado: apos derrubar req_i, sem pulso espurio (contagem final = exatamente 3 hits, um por ciclo sustentado)");
        end

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
