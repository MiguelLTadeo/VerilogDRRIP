// =============================================================================
// cache_addr_tb.v
// Testbench autoverificavel para cache_addr.v (Fase 1 - PI4 UNIPAMPA).
//
// Como compilar/simular no ModelSim (a partir de /home/miguel/verilog):
//
//   vlib work
//   vlog rtl/cache_addr.v tb/cache_addr_tb.v
//   vsim -c work.cache_addr_tb -do "run -all; quit -f"
//
// (ou use o script pronto: `vsim -c -do sim/run_cache_addr.do`)
//
// Config de validacao sob teste (ver plano-cache.md, Fase 1):
//   ADDR_W=8, BLK_B=4, SETS=4, WAYS=2, RRPV_BITS=2
//   -> OFFSET_W=2, INDEX_W=2, TAG_W=4, WAY_W=1
//
// -----------------------------------------------------------------------
// Valores esperados CALCULADOS NA MAO antes de escrever o codigo:
//
// addr_i = { tag[3:0] (bits 7:4) | index[1:0] (bits 3:2) | offset[1:0] (bits 1:0) }
//
//   addr       binario        tag   index  offset
//   0x00   0000_0000          0x0     0      0     (caso de borda: endereco 0)
//   0xFF   1111_1111          0xF     3      3     (caso de borda: endereco maximo)
//   0x55   0101_0101          0x5     1      1     (padrao alternado 0101)
//   0xAA   1010_1010          0xA     2      2     (padrao alternado 1010)
//   0x04   0000_0100          0x0     1      0     (fronteira index sem tocar tag)
//   0x03   0000_0011          0x0     0      3     (offset maximo, set 0)
//   0x1B   0001_1011          0x1     2      3
//   0xC7   1100_0111          0xC     1      3
//
// Sequencia do storage (tag/valid/data por via), com pos-condicoes
// calculadas na mao:
//
//   1) Pos-reset: valid_mem[way][set] = 0 para TODAS as posicoes.
//   2) write(way=0,set=0, v=1, tag=0xA, data=DEADBEEF)
//        -> read(way=0,set=0) = {v=1, tag=0xA, data=DEADBEEF}
//        -> read(way=1,set=0) continua invalido (via independente)
//   3) write(way=1,set=0, v=1, tag=0x3, data=11223344)
//        -> read(way=1,set=0) = {v=1, tag=0x3, data=11223344}
//        -> read(way=0,set=0) inalterado {v=1, tag=0xA, data=DEADBEEF}
//   4) write(way=0,set=3, v=1, tag=0xF, data=CAFEBABE)
//        -> read(way=0,set=3) = {v=1, tag=0xF, data=CAFEBABE}
//        -> read(way=0,set=0) inalterado (set independente)
//   5) invalidate(way=0,set=0): write(v=0,tag=0,data=0)
//        -> read(way=0,set=0) = {v=0, ...}
//   6) hit/miss basico (comparacao feita AQUI no TB, nao no DUT --
//      cache_addr so decodifica endereco + guarda storage; a comparacao
//      tag/valid completa entre vias e trabalho de fase futura):
//        addr=0xFC -> decode tag=0xF,index=3 ; via0/set3 tem v=1,tag=0xF
//                     => HIT (tag bate, valid=1)
//        addr=0x0C -> decode tag=0x0,index=3 ; via0/set3 tem v=1,tag=0xF
//                     => MISS (tag nao bate)
//        addr=0x58 -> decode tag=0x5,index=2 ; via1/set2 nunca escrito
//                     => MISS (linha invalida)
// -----------------------------------------------------------------------
//
// Cobertura EXATA deste testbench: 22 checagens autoverificaveis (cada
// chamada de task abaixo conta 1 checagem, contadas na ordem em que
// aparecem no bloco `initial`):
//   check_derived_widths ........... 1  (larguras derivadas do DUT)
//   check_decode .................... 8  (decodificacao TAG/INDEX/OFFSET)
//   check_read ...................... 10 (leitura do storage por via/set,
//                                         incluindo pos-reset, apos escrita
//                                         e apos invalidacao)
//   check_hitmiss .................... 3  (hit/miss "na mao" feito no TB)
//   TOTAL ........................... 22
// -----------------------------------------------------------------------
// =============================================================================

`timescale 1ns/1ps

module cache_addr_tb;

    // ---- parametros da config de validacao (Fase 1) ----------------------
    localparam ADDR_W    = 8;
    localparam BLK_B      = 4;
    localparam SETS       = 4;
    localparam WAYS        = 2;
    localparam RRPV_BITS   = 2;

    localparam OFFSET_W = 2; // $clog2(BLK_B)  -- valor esperado calculado a mao
    localparam INDEX_W  = 2; // $clog2(SETS)
    localparam TAG_W    = 4; // ADDR_W - INDEX_W - OFFSET_W
    localparam WAY_W    = 1; // $clog2(WAYS)

    // ---- sinais de interface com o DUT ------------------------------------
    reg                     clk;
    reg                     rst;

    reg  [ADDR_W-1:0]       addr_i;
    wire [TAG_W-1:0]        tag_o;
    wire [INDEX_W-1:0]      index_o;
    wire [OFFSET_W-1:0]     offset_o;

    reg                     wr_en_i;
    reg  [WAY_W-1:0]        wr_way_i;
    reg  [INDEX_W-1:0]      wr_index_i;
    reg                     wr_valid_i;
    reg  [TAG_W-1:0]        wr_tag_i;
    reg  [BLK_B*8-1:0]      wr_data_i;

    reg  [WAY_W-1:0]        rd_way_i;
    reg  [INDEX_W-1:0]      rd_index_i;
    wire                    rd_valid_o;
    wire [TAG_W-1:0]        rd_tag_o;
    wire [BLK_B*8-1:0]      rd_data_o;

    integer errors;

    // ---- instancia do DUT --------------------------------------------------
    cache_addr #(
        .ADDR_W    (ADDR_W),
        .BLK_B      (BLK_B),
        .SETS       (SETS),
        .WAYS        (WAYS),
        .RRPV_BITS   (RRPV_BITS)
    ) dut (
        .clk        (clk),
        .rst        (rst),
        .addr_i     (addr_i),
        .tag_o      (tag_o),
        .index_o    (index_o),
        .offset_o   (offset_o),
        .wr_en_i    (wr_en_i),
        .wr_way_i   (wr_way_i),
        .wr_index_i (wr_index_i),
        .wr_valid_i (wr_valid_i),
        .wr_tag_i   (wr_tag_i),
        .wr_data_i  (wr_data_i),
        .rd_way_i   (rd_way_i),
        .rd_index_i (rd_index_i),
        .rd_valid_o (rd_valid_o),
        .rd_tag_o   (rd_tag_o),
        .rd_data_o  (rd_data_o)
    );

    // ---- geracao de clock (100 MHz simulado, so existe no TB) --------------
    always #5 clk = ~clk;

    // ---- checagem da propria config derivada (localparam do DUT) -----------
    // confere que $clog2 no DUT bateu com o que calculamos na mao.
    task check_derived_widths;
    begin
        if (dut.OFFSET_W !== OFFSET_W || dut.INDEX_W !== INDEX_W ||
            dut.TAG_W !== TAG_W || dut.WAY_W !== WAY_W) begin
            errors = errors + 1;
            $display("FALHA larguras derivadas: esperado OFFSET_W=%0d INDEX_W=%0d TAG_W=%0d WAY_W=%0d obtido OFFSET_W=%0d INDEX_W=%0d TAG_W=%0d WAY_W=%0d",
                       OFFSET_W, INDEX_W, TAG_W, WAY_W,
                       dut.OFFSET_W, dut.INDEX_W, dut.TAG_W, dut.WAY_W);
        end else begin
            $display("OK larguras derivadas: OFFSET_W=%0d INDEX_W=%0d TAG_W=%0d WAY_W=%0d",
                       dut.OFFSET_W, dut.INDEX_W, dut.TAG_W, dut.WAY_W);
        end
    end
    endtask

    // ---- checagem de decodificacao de endereco ------------------------------
    task check_decode(input [ADDR_W-1:0] a,
                       input [TAG_W-1:0] exp_tag,
                       input [INDEX_W-1:0] exp_idx,
                       input [OFFSET_W-1:0] exp_off);
    begin
        addr_i = a;
        #1;
        if (tag_o !== exp_tag || index_o !== exp_idx || offset_o !== exp_off) begin
            errors = errors + 1;
            $display("FALHA decode addr=0x%0h: esperado tag=0x%0h idx=%0d off=%0d | obtido tag=0x%0h idx=%0d off=%0d",
                       a, exp_tag, exp_idx, exp_off, tag_o, index_o, offset_o);
        end else begin
            $display("OK decode addr=0x%0h -> tag=0x%0h idx=%0d off=%0d", a, tag_o, index_o, offset_o);
        end
    end
    endtask

    // ---- escrita no storage (via porta sincrona do DUT) ---------------------
    task do_write(input [WAY_W-1:0] w, input [INDEX_W-1:0] idx,
                  input v, input [TAG_W-1:0] t, input [BLK_B*8-1:0] d);
    begin
        @(negedge clk);
        wr_en_i    = 1'b1;
        wr_way_i   = w;
        wr_index_i = idx;
        wr_valid_i = v;
        wr_tag_i   = t;
        wr_data_i  = d;
        @(negedge clk);
        wr_en_i = 1'b0;
    end
    endtask

    // ---- checagem de leitura do storage ---------------------------------------
    task check_read(input [255:0] label,
                     input [WAY_W-1:0] w, input [INDEX_W-1:0] idx,
                     input exp_v, input [TAG_W-1:0] exp_t, input [BLK_B*8-1:0] exp_d);
    begin
        rd_way_i   = w;
        rd_index_i = idx;
        #1;
        if (rd_valid_o !== exp_v ||
            (exp_v && (rd_tag_o !== exp_t || rd_data_o !== exp_d))) begin
            errors = errors + 1;
            $display("FALHA storage [%0s] way=%0d set=%0d: esperado v=%0b tag=0x%0h data=0x%0h | obtido v=%0b tag=0x%0h data=0x%0h",
                       label, w, idx, exp_v, exp_t, exp_d, rd_valid_o, rd_tag_o, rd_data_o);
        end else begin
            $display("OK storage [%0s] way=%0d set=%0d -> v=%0b tag=0x%0h data=0x%0h",
                       label, w, idx, rd_valid_o, rd_tag_o, rd_data_o);
        end
    end
    endtask

    // ---- checagem de hit/miss "na mao" (comparacao feita no TB) --------------
    task check_hitmiss(input [255:0] label,
                        input [ADDR_W-1:0] a, input [WAY_W-1:0] w,
                        input exp_hit);
        reg observed_hit;
    begin
        addr_i     = a;
        rd_way_i   = w;
        rd_index_i = a[OFFSET_W + INDEX_W - 1 : OFFSET_W]; // index_o do endereco
        #1;
        observed_hit = rd_valid_o && (rd_tag_o == tag_o);
        if (observed_hit !== exp_hit) begin
            errors = errors + 1;
            $display("FALHA hit/miss [%0s] addr=0x%0h way=%0d: esperado %0s obtido %0s",
                       label, a, w, exp_hit ? "HIT" : "MISS", observed_hit ? "HIT" : "MISS");
        end else begin
            $display("OK hit/miss [%0s] addr=0x%0h way=%0d -> %0s",
                       label, a, w, observed_hit ? "HIT" : "MISS");
        end
    end
    endtask

    initial begin
        errors     = 0;
        clk        = 1'b0;
        rst        = 1'b1;
        addr_i     = {ADDR_W{1'b0}};
        wr_en_i    = 1'b0;
        wr_way_i   = {WAY_W{1'b0}};
        wr_index_i = {INDEX_W{1'b0}};
        wr_valid_i = 1'b0;
        wr_tag_i   = {TAG_W{1'b0}};
        wr_data_i  = {(BLK_B*8){1'b0}};
        rd_way_i   = {WAY_W{1'b0}};
        rd_index_i = {INDEX_W{1'b0}};

        // libera reset sincrono apos algumas bordas de clock
        @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        $display("==================================================================");
        $display("cache_addr_tb: config ADDR_W=%0d BLK_B=%0d SETS=%0d WAYS=%0d RRPV_BITS=%0d",
                   ADDR_W, BLK_B, SETS, WAYS, RRPV_BITS);
        $display("==================================================================");

        // 0) larguras derivadas
        check_derived_widths;

        // 1) decodificacao de endereco (casos de borda + padroes)
        $display("---- decodificacao de endereco ----");
        check_decode(8'h00, 4'h0, 2'd0, 2'd0); // endereco 0
        check_decode(8'hFF, 4'hF, 2'd3, 2'd3); // endereco maximo
        check_decode(8'h55, 4'h5, 2'd1, 2'd1);
        check_decode(8'hAA, 4'hA, 2'd2, 2'd2);
        check_decode(8'h04, 4'h0, 2'd1, 2'd0);
        check_decode(8'h03, 4'h0, 2'd0, 2'd3);
        check_decode(8'h1B, 4'h1, 2'd2, 2'd3);
        check_decode(8'hC7, 4'hC, 2'd1, 2'd3);

        // 2) storage pos-reset: tudo invalido
        $display("---- storage pos-reset (tudo invalido) ----");
        check_read("pos-reset way0/set0", 1'd0, 2'd0, 1'b0, 4'h0, 32'h0);
        check_read("pos-reset way1/set3", 1'd1, 2'd3, 1'b0, 4'h0, 32'h0);
        check_read("pos-reset way0/set2", 1'd0, 2'd2, 1'b0, 4'h0, 32'h0);

        // 3) escreve way0/set0 e confere independencia entre vias
        $display("---- write way0/set0 ----");
        do_write(1'd0, 2'd0, 1'b1, 4'hA, 32'hDEAD_BEEF);
        check_read("way0/set0 apos write", 1'd0, 2'd0, 1'b1, 4'hA, 32'hDEAD_BEEF);
        check_read("way1/set0 nao afetado", 1'd1, 2'd0, 1'b0, 4'h0, 32'h0);

        // 4) escreve way1/set0 (mesmo set, via diferente)
        $display("---- write way1/set0 (mesmo set, via diferente) ----");
        do_write(1'd1, 2'd0, 1'b1, 4'h3, 32'h1122_3344);
        check_read("way1/set0 apos write", 1'd1, 2'd0, 1'b1, 4'h3, 32'h1122_3344);
        check_read("way0/set0 inalterado", 1'd0, 2'd0, 1'b1, 4'hA, 32'hDEAD_BEEF);

        // 5) escreve way0/set3 (mesma via, set diferente)
        $display("---- write way0/set3 (mesma via, set diferente) ----");
        do_write(1'd0, 2'd3, 1'b1, 4'hF, 32'hCAFE_BABE);
        check_read("way0/set3 apos write", 1'd0, 2'd3, 1'b1, 4'hF, 32'hCAFE_BABE);
        check_read("way0/set0 ainda inalterado", 1'd0, 2'd0, 1'b1, 4'hA, 32'hDEAD_BEEF);

        // 6) invalida way0/set0 (simula eviction)
        $display("---- invalidate way0/set0 ----");
        do_write(1'd0, 2'd0, 1'b0, 4'h0, 32'h0);
        check_read("way0/set0 invalidado", 1'd0, 2'd0, 1'b0, 4'h0, 32'h0);

        // 7) hit/miss basico (comparacao feita no TB, DUT so decodifica+guarda)
        $display("---- hit/miss basico (comparacao no TB) ----");
        check_hitmiss("hit tag bate",       8'hFC, 1'd0, 1'b1); // way0/set3 tag=0xF == decode tag=0xF
        check_hitmiss("miss tag nao bate",  8'h0C, 1'd0, 1'b0); // way0/set3 tag=0xF != decode tag=0x0
        check_hitmiss("miss linha invalida",8'h58, 1'd1, 1'b0); // way1/set2 nunca escrito

        // ---- resumo final --------------------------------------------------
        $display("==================================================================");
        if (errors == 0)
            $display("RESULTADO: PASS (0 erros)");
        else
            $display("RESULTADO: FAIL (%0d erro(s))", errors);
        $display("==================================================================");

        $finish;
    end

endmodule
