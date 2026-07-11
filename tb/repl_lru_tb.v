// =============================================================================
// repl_lru_tb.v
// Testbench autoverificavel para repl_lru.v (Fase 2 - PI4 UNIPAMPA).
//
// Como compilar/simular no ModelSim (a partir de /home/miguel/verilog):
//
//   vlib work
//   vlog rtl/repl_lru.v tb/repl_lru_tb.v
//   vsim -c work.repl_lru_tb -do "run -all; quit -f"
//
// (ou use o script pronto: `vsim -c -do sim/run_repl_lru.do`)
//
// Config de validacao sob teste (ver plano-cache.md, mesma config da Fase 1):
//   SETS=4, WAYS=2  ->  INDEX_W=2, WAY_W=1
//
// -----------------------------------------------------------------------
// Valores esperados CALCULADOS NA MAO antes de escrever o codigo (o
// estado de cada set e o par (mru_way, victim_way); victim_way = ~mru_way
// porque WAYS==2 -- so ha 2 vias possiveis, 0 e 1):
//
//  #  acao                                    set  mru_way  victim_way
//  ------------------------------------------------------------------
//  0  pos-reset (TODOS os sets)                *      0         1
//
//  -- hits alternados no MESMO set (set 0) -----------------------------
//  1  hit via0 set0 -> update(set0,way0)        0      0         1     (ja era MRU, sem mudanca)
//  2  hit via1 set0 -> update(set0,way1)        0      1         0
//  3  hit via0 set0 -> update(set0,way0)        0      0         1
//  4  hit via1 set0 -> update(set0,way1)        0      1         0
//     apos os hits: set1/set2/set3 permanecem em (0,1) -- independencia
//
//  -- misses forcando eviction ALTERNADA no set 1 -----------------------
//  5  miss set1: consulta vitima ANTES do fill  1      0         1     (nada mudou ainda, e leitura)
//     -> despeja via1 (vitima), fill na via1, update(set1,way1)
//  6  estado apos fill                          1      1         0
//     -> set0 continua em (1,0), independente do que aconteceu no set1
//  7  miss set1: consulta vitima ANTES do fill  1      1         0     (vitima agora e via0)
//     -> despeja via0, fill na via0, update(set1,way0)
//  8  estado apos fill                          1      0         1
//  9  miss set1: consulta vitima ANTES do fill  1      0         1     (vitima volta a ser via1)
//     -> despeja via1, fill na via1, update(set1,way1)
// 10  estado apos fill                          1      1         0
//     -> set2/set3 permanecem em (0,1): nunca foram tocados -- independencia
//     -> set0 continua em (1,0): nao foi afetado pelas misses do set1
//
//  -- toca um terceiro set (set 3) p/ reforcar independencia ------------
// 11  hit via1 set3 -> update(set3,way1)        3      1         0
//     -> set2 continua em (0,1): nao foi afetado
//
//  -- foto final de TODOS os sets ---------------------------------------
//     set0=(1,0)  set1=(1,0)  set2=(0,1) [nunca tocado]  set3=(1,0)
// -----------------------------------------------------------------------
//
// Cobertura EXATA deste testbench: 28 checagens autoverificaveis (cada
// chamada de task check_* abaixo conta 1 checagem, contadas na ordem em
// que aparecem no bloco `initial`):
//   check_derived_widths ............ 1  (larguras derivadas do DUT)
//   check_state (pos-reset)  ........ 4  (todos os sets em (0,1))
//   check_state (hits set0) ......... 4  (passos 1-4)
//   check_state (independencia) ..... 3  (set1/set2/set3 apos hits em set0)
//   check_victim/check_state (set1).. 7  (passos 5-10: 3x query vitima +
//                                         3x estado apos fill + 1x estado
//                                         do set0 intercalado no meio da
//                                         sequencia, provando independencia
//                                         enquanto o set1 ainda esta sendo
//                                         atualizado)
//   check_state (independencia) ..... 3  (set0 estavel + set2/set3 intactos)
//   check_state (set3 + independencia) 2 (passo 11 + set2 intacto)
//   check_state (foto final) ........ 4  (set0..set3)
//   TOTAL ............................ 28
// -----------------------------------------------------------------------
// =============================================================================

`timescale 1ns/1ps

module repl_lru_tb;

    // ---- parametros da config de validacao (mesma da Fase 1) ---------------
    localparam SETS = 4;
    localparam WAYS = 2;

    localparam INDEX_W = 2; // $clog2(SETS) -- valor esperado calculado a mao
    localparam WAY_W   = 1; // $clog2(WAYS)

    // ---- sinais de interface com o DUT --------------------------------------
    reg                  clk;
    reg                  rst;

    reg                  wr_en_i;
    reg  [INDEX_W-1:0]   wr_index_i;
    reg  [WAY_W-1:0]     wr_way_i;

    reg  [INDEX_W-1:0]   rd_index_i;
    wire [WAY_W-1:0]     rd_mru_way_o;
    wire [WAY_W-1:0]     rd_victim_way_o;

    integer errors;

    // ---- instancia do DUT -----------------------------------------------------
    repl_lru #(
        .SETS (SETS),
        .WAYS (WAYS)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .wr_en_i         (wr_en_i),
        .wr_index_i      (wr_index_i),
        .wr_way_i        (wr_way_i),
        .rd_index_i      (rd_index_i),
        .rd_mru_way_o    (rd_mru_way_o),
        .rd_victim_way_o (rd_victim_way_o)
    );

    // ---- geracao de clock (100 MHz simulado, so existe no TB) ----------------
    always #5 clk = ~clk;

    // ---- checagem da propria config derivada (localparam do DUT) --------------
    task check_derived_widths;
    begin
        if (dut.INDEX_W !== INDEX_W || dut.WAY_W !== WAY_W) begin
            errors = errors + 1;
            $display("FALHA larguras derivadas: esperado INDEX_W=%0d WAY_W=%0d obtido INDEX_W=%0d WAY_W=%0d",
                       INDEX_W, WAY_W, dut.INDEX_W, dut.WAY_W);
        end else begin
            $display("OK larguras derivadas: INDEX_W=%0d WAY_W=%0d", dut.INDEX_W, dut.WAY_W);
        end
    end
    endtask

    // ---- atualizacao do estado MRU (via porta sincrona do DUT) -----------------
    // usada tanto para simular um HIT quanto para simular o fill que segue
    // uma eviction em MISS -- em hardware e a mesma acao: "marca esta via
    // deste set como MRU".
    task do_update(input [INDEX_W-1:0] idx, input [WAY_W-1:0] way);
    begin
        @(negedge clk);
        wr_en_i    = 1'b1;
        wr_index_i = idx;
        wr_way_i   = way;
        @(negedge clk);
        wr_en_i = 1'b0;
    end
    endtask

    // ---- checagem so da via vitima (simula a consulta feita ANTES do
    //      fill, no momento em que a logica de hit/miss decide onde
    //      despejar em caso de MISS) --------------------------------------
    task check_victim(input [255:0] label, input [INDEX_W-1:0] idx,
                       input [WAY_W-1:0] exp_victim);
    begin
        rd_index_i = idx;
        #1;
        if (rd_victim_way_o !== exp_victim) begin
            errors = errors + 1;
            $display("FALHA vitima [%0s] set=%0d: esperado victim_way=%0d obtido victim_way=%0d",
                       label, idx, exp_victim, rd_victim_way_o);
        end else begin
            $display("OK vitima [%0s] set=%0d -> victim_way=%0d", label, idx, rd_victim_way_o);
        end
    end
    endtask

    // ---- checagem do estado completo (mru_way e victim_way) de um set ---------
    task check_state(input [255:0] label, input [INDEX_W-1:0] idx,
                      input [WAY_W-1:0] exp_mru, input [WAY_W-1:0] exp_victim);
    begin
        rd_index_i = idx;
        #1;
        if (rd_mru_way_o !== exp_mru || rd_victim_way_o !== exp_victim) begin
            errors = errors + 1;
            $display("FALHA estado [%0s] set=%0d: esperado mru=%0d victim=%0d | obtido mru=%0d victim=%0d",
                       label, idx, exp_mru, exp_victim, rd_mru_way_o, rd_victim_way_o);
        end else begin
            $display("OK estado [%0s] set=%0d -> mru=%0d victim=%0d",
                       label, idx, rd_mru_way_o, rd_victim_way_o);
        end
    end
    endtask

    initial begin
        errors     = 0;
        clk        = 1'b0;
        rst        = 1'b1;
        wr_en_i    = 1'b0;
        wr_index_i = {INDEX_W{1'b0}};
        wr_way_i   = {WAY_W{1'b0}};
        rd_index_i = {INDEX_W{1'b0}};

        // libera reset sincrono apos algumas bordas de clock
        @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        $display("==================================================================");
        $display("repl_lru_tb: config SETS=%0d WAYS=%0d", SETS, WAYS);
        $display("==================================================================");

        // 0) larguras derivadas
        check_derived_widths;

        // 1) pos-reset: todos os sets com mru=0 (via0), vitima=1 (via1)
        $display("---- pos-reset (todos os sets) ----");
        check_state("pos-reset set0", 2'd0, 1'd0, 1'd1);
        check_state("pos-reset set1", 2'd1, 1'd0, 1'd1);
        check_state("pos-reset set2", 2'd2, 1'd0, 1'd1);
        check_state("pos-reset set3", 2'd3, 1'd0, 1'd1);

        // 2) hits alternados no MESMO set (set0)
        $display("---- hits alternados no set0 ----");
        do_update(2'd0, 1'd0); // hit via0 (ja era MRU)
        check_state("hit via0 set0", 2'd0, 1'd0, 1'd1);
        do_update(2'd0, 1'd1); // hit via1
        check_state("hit via1 set0", 2'd0, 1'd1, 1'd0);
        do_update(2'd0, 1'd0); // hit via0
        check_state("hit via0 set0 (2)", 2'd0, 1'd0, 1'd1);
        do_update(2'd0, 1'd1); // hit via1
        check_state("hit via1 set0 (2)", 2'd0, 1'd1, 1'd0);

        // 3) independencia: set1/set2/set3 nao foram tocados pelos hits em set0
        $display("---- independencia apos hits em set0 ----");
        check_state("set1 intacto", 2'd1, 1'd0, 1'd1);
        check_state("set2 intacto", 2'd2, 1'd0, 1'd1);
        check_state("set3 intacto", 2'd3, 1'd0, 1'd1);

        // 4) misses forcando eviction ALTERNADA no set1
        $display("---- misses com eviction alternada no set1 ----");
        check_victim("miss #1 (antes do fill)", 2'd1, 1'd1); // vitima = via1 (estado de reset)
        do_update(2'd1, 1'd1);                                // fill na via1 -> vira MRU
        check_state("apos fill #1 set1", 2'd1, 1'd1, 1'd0);

        check_state("set0 estavel c/ misses set1", 2'd0, 1'd1, 1'd0);

        check_victim("miss #2 (antes do fill)", 2'd1, 1'd0); // vitima agora = via0
        do_update(2'd1, 1'd0);                                // fill na via0 -> vira MRU
        check_state("apos fill #2 set1", 2'd1, 1'd0, 1'd1);

        check_victim("miss #3 (antes do fill)", 2'd1, 1'd1); // vitima volta a ser via1
        do_update(2'd1, 1'd1);                                // fill na via1 -> vira MRU
        check_state("apos fill #3 set1", 2'd1, 1'd1, 1'd0);

        // 5) independencia final: set0 nao mudou; set2/set3 nunca tocados
        $display("---- independencia apos misses no set1 ----");
        check_state("set0 ainda estavel", 2'd0, 1'd1, 1'd0);
        check_state("set2 nunca tocado", 2'd2, 1'd0, 1'd1);
        check_state("set3 nunca tocado", 2'd3, 1'd0, 1'd1);

        // 6) toca um terceiro set (set3) e confere que set2 continua intacto
        $display("---- hit no set3 (independencia final) ----");
        do_update(2'd3, 1'd1); // hit via1 set3
        check_state("hit via1 set3", 2'd3, 1'd1, 1'd0);
        check_state("set2 continua intacto", 2'd2, 1'd0, 1'd1);

        // 7) foto final de todos os sets
        $display("---- foto final de todos os sets ----");
        check_state("final set0", 2'd0, 1'd1, 1'd0);
        check_state("final set1", 2'd1, 1'd1, 1'd0);
        check_state("final set2", 2'd2, 1'd0, 1'd1);
        check_state("final set3", 2'd3, 1'd1, 1'd0);

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
