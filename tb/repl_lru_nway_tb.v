// =============================================================================
// repl_lru_nway_tb.v
// Testbench autoverificavel para repl_lru_nway.v (Fase 7 - PI4 UNIPAMPA).
//
// Como compilar/simular no ModelSim (a partir de /home/miguel/verilog):
//
//   vlib work
//   vlog rtl/repl_lru_nway.v tb/repl_lru_nway_tb.v
//   vsim -c work.repl_lru_nway_tb -do "run -all; quit -f"
//
// (ou use o script pronto: `vsim -c -do sim/run_repl_lru_nway.do`)
//
// Duas instancias do DUT sao verificadas no MESMO testbench, cada uma com
// seu proprio conjunto de sinais/tasks (larguras WAY_W/INDEX_W diferem
// entre as duas, entao nao da pra compartilhar barramento):
//
//   PARTE A (dut_a): SETS=4, WAYS=2 -> reproduz, BIT A BIT, a MESMA
//     sequencia de acessos e os MESMOS resultados esperados do testbench
//     da Fase 2 (tb/repl_lru_tb.v), pra provar que a generalizacao
//     matricial e equivalente ao LRU de 1 bit legado quando WAYS==2 (ver
//     "RESET" no cabecalho de rtl/repl_lru_nway.v pra por que isso e
//     esperado bit a bit, nao so "parecido").
//
//   PARTE B (dut_b): SETS=2, WAYS=8 -> config real do L2 do Apendice B em
//     termos de associatividade (8-way; SETS reduzido pra 2 so pra manter
//     o trace pequeno e ainda cobrir independencia entre sets -- o
//     numero de sets nao afeta a logica de ordenacao dentro de um set,
//     que e o que estamos validando aqui). Sequencia de 12 acessos com
//     ORDEM TOTAL das 8 vias recalculada NA MAO a cada passo (ver ledger
//     completo no comentario antes do bloco `initial` da parte B).
// -----------------------------------------------------------------------
// =============================================================================

`timescale 1ns/1ps

module repl_lru_nway_tb;

    integer errors;

    // =====================================================================
    // PARTE A -- SETS=4, WAYS=2 (deve bater EXATAMENTE com repl_lru_tb.v)
    // =====================================================================
    localparam A_SETS = 4;
    localparam A_WAYS = 2;
    localparam A_INDEX_W = 2; // $clog2(4)
    localparam A_WAY_W   = 1; // $clog2(2)

    reg                    clk;
    reg                    rst;

    reg                    a_wr_en_i;
    reg  [A_INDEX_W-1:0]   a_wr_index_i;
    reg  [A_WAY_W-1:0]     a_wr_way_i;
    reg  [A_INDEX_W-1:0]   a_rd_index_i;
    wire [A_WAY_W-1:0]     a_rd_mru_way_o;
    wire [A_WAY_W-1:0]     a_rd_victim_way_o;

    repl_lru_nway #(
        .SETS (A_SETS),
        .WAYS (A_WAYS)
    ) dut_a (
        .clk             (clk),
        .rst             (rst),
        .wr_en_i         (a_wr_en_i),
        .wr_index_i      (a_wr_index_i),
        .wr_way_i        (a_wr_way_i),
        .rd_index_i      (a_rd_index_i),
        .rd_mru_way_o    (a_rd_mru_way_o),
        .rd_victim_way_o (a_rd_victim_way_o)
    );

    task a_do_update(input [A_INDEX_W-1:0] idx, input [A_WAY_W-1:0] way);
    begin
        @(negedge clk);
        a_wr_en_i    = 1'b1;
        a_wr_index_i = idx;
        a_wr_way_i   = way;
        @(negedge clk);
        a_wr_en_i = 1'b0;
    end
    endtask

    task a_check_victim(input [255:0] label, input [A_INDEX_W-1:0] idx,
                         input [A_WAY_W-1:0] exp_victim);
    begin
        a_rd_index_i = idx;
        #1;
        if (a_rd_victim_way_o !== exp_victim) begin
            errors = errors + 1;
            $display("FALHA [A] vitima [%0s] set=%0d: esperado=%0d obtido=%0d",
                       label, idx, exp_victim, a_rd_victim_way_o);
        end else begin
            $display("OK [A] vitima [%0s] set=%0d -> victim_way=%0d", label, idx, a_rd_victim_way_o);
        end
    end
    endtask

    task a_check_state(input [255:0] label, input [A_INDEX_W-1:0] idx,
                        input [A_WAY_W-1:0] exp_mru, input [A_WAY_W-1:0] exp_victim);
    begin
        a_rd_index_i = idx;
        #1;
        if (a_rd_mru_way_o !== exp_mru || a_rd_victim_way_o !== exp_victim) begin
            errors = errors + 1;
            $display("FALHA [A] estado [%0s] set=%0d: esperado mru=%0d victim=%0d | obtido mru=%0d victim=%0d",
                       label, idx, exp_mru, exp_victim, a_rd_mru_way_o, a_rd_victim_way_o);
        end else begin
            $display("OK [A] estado [%0s] set=%0d -> mru=%0d victim=%0d",
                       label, idx, a_rd_mru_way_o, a_rd_victim_way_o);
        end
    end
    endtask

    task run_part_a;
    begin
        $display("==================================================================");
        $display("PARTE A: repl_lru_nway com SETS=%0d WAYS=%0d (deve == repl_lru_tb.v)", A_SETS, A_WAYS);
        $display("==================================================================");

        a_wr_en_i    = 1'b0;
        a_wr_index_i = {A_INDEX_W{1'b0}};
        a_wr_way_i   = {A_WAY_W{1'b0}};
        a_rd_index_i = {A_INDEX_W{1'b0}};

        // 1) pos-reset: todos os sets com mru=0 (via0), vitima=1 (via1)
        //    -- mesma expectativa de repl_lru_tb.v (ver "RESET" no
        //    cabecalho do RTL: ordem inicial via0(MRU) > via1(LRU)).
        $display("---- pos-reset (todos os sets) ----");
        a_check_state("pos-reset set0", 2'd0, 1'd0, 1'd1);
        a_check_state("pos-reset set1", 2'd1, 1'd0, 1'd1);
        a_check_state("pos-reset set2", 2'd2, 1'd0, 1'd1);
        a_check_state("pos-reset set3", 2'd3, 1'd0, 1'd1);

        // 2) hits alternados no MESMO set (set0)
        $display("---- hits alternados no set0 ----");
        a_do_update(2'd0, 1'd0);
        a_check_state("hit via0 set0", 2'd0, 1'd0, 1'd1);
        a_do_update(2'd0, 1'd1);
        a_check_state("hit via1 set0", 2'd0, 1'd1, 1'd0);
        a_do_update(2'd0, 1'd0);
        a_check_state("hit via0 set0 (2)", 2'd0, 1'd0, 1'd1);
        a_do_update(2'd0, 1'd1);
        a_check_state("hit via1 set0 (2)", 2'd0, 1'd1, 1'd0);

        // 3) independencia: set1/set2/set3 nao foram tocados
        $display("---- independencia apos hits em set0 ----");
        a_check_state("set1 intacto", 2'd1, 1'd0, 1'd1);
        a_check_state("set2 intacto", 2'd2, 1'd0, 1'd1);
        a_check_state("set3 intacto", 2'd3, 1'd0, 1'd1);

        // 4) misses forcando eviction ALTERNADA no set1
        $display("---- misses com eviction alternada no set1 ----");
        a_check_victim("miss #1 (antes do fill)", 2'd1, 1'd1);
        a_do_update(2'd1, 1'd1);
        a_check_state("apos fill #1 set1", 2'd1, 1'd1, 1'd0);

        a_check_state("set0 estavel c/ misses set1", 2'd0, 1'd1, 1'd0);

        a_check_victim("miss #2 (antes do fill)", 2'd1, 1'd0);
        a_do_update(2'd1, 1'd0);
        a_check_state("apos fill #2 set1", 2'd1, 1'd0, 1'd1);

        a_check_victim("miss #3 (antes do fill)", 2'd1, 1'd1);
        a_do_update(2'd1, 1'd1);
        a_check_state("apos fill #3 set1", 2'd1, 1'd1, 1'd0);

        // 5) independencia final
        $display("---- independencia apos misses no set1 ----");
        a_check_state("set0 ainda estavel", 2'd0, 1'd1, 1'd0);
        a_check_state("set2 nunca tocado", 2'd2, 1'd0, 1'd1);
        a_check_state("set3 nunca tocado", 2'd3, 1'd0, 1'd1);

        // 6) toca um terceiro set (set3)
        $display("---- hit no set3 (independencia final) ----");
        a_do_update(2'd3, 1'd1);
        a_check_state("hit via1 set3", 2'd3, 1'd1, 1'd0);
        a_check_state("set2 continua intacto", 2'd2, 1'd0, 1'd1);

        // 7) foto final
        $display("---- foto final de todos os sets ----");
        a_check_state("final set0", 2'd0, 1'd1, 1'd0);
        a_check_state("final set1", 2'd1, 1'd1, 1'd0);
        a_check_state("final set2", 2'd2, 1'd0, 1'd1);
        a_check_state("final set3", 2'd3, 1'd1, 1'd0);
    end
    endtask

    // =====================================================================
    // PARTE B -- SETS=2, WAYS=8 (config de associatividade real do L2)
    // =====================================================================
    localparam B_SETS = 2;
    localparam B_WAYS = 8;
    localparam B_INDEX_W = 1; // $clog2(2)
    localparam B_WAY_W   = 3; // $clog2(8)

    reg                    b_wr_en_i;
    reg  [B_INDEX_W-1:0]   b_wr_index_i;
    reg  [B_WAY_W-1:0]     b_wr_way_i;
    reg  [B_INDEX_W-1:0]   b_rd_index_i;
    wire [B_WAY_W-1:0]     b_rd_mru_way_o;
    wire [B_WAY_W-1:0]     b_rd_victim_way_o;

    repl_lru_nway #(
        .SETS (B_SETS),
        .WAYS (B_WAYS)
    ) dut_b (
        .clk             (clk),
        .rst             (rst),
        .wr_en_i         (b_wr_en_i),
        .wr_index_i      (b_wr_index_i),
        .wr_way_i        (b_wr_way_i),
        .rd_index_i      (b_rd_index_i),
        .rd_mru_way_o    (b_rd_mru_way_o),
        .rd_victim_way_o (b_rd_victim_way_o)
    );

    task b_do_update(input [B_INDEX_W-1:0] idx, input [B_WAY_W-1:0] way);
    begin
        @(negedge clk);
        b_wr_en_i    = 1'b1;
        b_wr_index_i = idx;
        b_wr_way_i   = way;
        @(negedge clk);
        b_wr_en_i = 1'b0;
    end
    endtask

    task b_check_victim(input [255:0] label, input [B_INDEX_W-1:0] idx,
                         input [B_WAY_W-1:0] exp_victim);
    begin
        b_rd_index_i = idx;
        #1;
        if (b_rd_victim_way_o !== exp_victim) begin
            errors = errors + 1;
            $display("FALHA [B] vitima [%0s] set=%0d: esperado=%0d obtido=%0d",
                       label, idx, exp_victim, b_rd_victim_way_o);
        end else begin
            $display("OK [B] vitima [%0s] set=%0d -> victim_way=%0d", label, idx, b_rd_victim_way_o);
        end
    end
    endtask

    task b_check_state(input [255:0] label, input [B_INDEX_W-1:0] idx,
                        input [B_WAY_W-1:0] exp_mru, input [B_WAY_W-1:0] exp_victim);
    begin
        b_rd_index_i = idx;
        #1;
        if (b_rd_mru_way_o !== exp_mru || b_rd_victim_way_o !== exp_victim) begin
            errors = errors + 1;
            $display("FALHA [B] estado [%0s] set=%0d: esperado mru=%0d victim=%0d | obtido mru=%0d victim=%0d",
                       label, idx, exp_mru, exp_victim, b_rd_mru_way_o, b_rd_victim_way_o);
        end else begin
            $display("OK [B] estado [%0s] set=%0d -> mru=%0d victim=%0d",
                       label, idx, b_rd_mru_way_o, b_rd_victim_way_o);
        end
    end
    endtask

    // -------------------------------------------------------------------
    // LEDGER calculado NA MAO (ordem de recencia MRU->LRU por set, antes
    // de escrever qualquer linha de codigo do bloco `initial` abaixo).
    // Cada acesso(set,via) move `via` para a frente da lista do set;
    // MRU = primeiro elemento, victim = ultimo elemento.
    //
    //  pos-reset set0 = set1 = [0,1,2,3,4,5,6,7]           mru=0  victim=7
    //
    //  B1 acesso(set0,3)  -> set0=[3,0,1,2,4,5,6,7]        mru=3  victim=7
    //  B2 acesso(set0,7)  -> set0=[7,3,0,1,2,4,5,6]        mru=7  victim=6
    //  B3 acesso(set0,6)  -> set0=[6,7,3,0,1,2,4,5]        mru=6  victim=5
    //  B4 acesso(set0,0)  -> set0=[0,6,7,3,1,2,4,5]        mru=0  victim=5
    //     -- checa set1 intacto: ainda [0,1,2,3,4,5,6,7]   mru=0  victim=7
    //  B5 acesso(set1,2)  -> set1=[2,0,1,3,4,5,6,7]        mru=2  victim=7
    //     -- checa set0 intacto: ainda [0,6,7,3,1,2,4,5]   mru=0  victim=5
    //  B6 acesso(set0,5)  -> set0=[5,0,6,7,3,1,2,4]        mru=5  victim=4
    //  B7 acesso(set0,4)  -> set0=[4,5,0,6,7,3,1,2]        mru=4  victim=2
    //  B8 acesso(set0,2)  -> set0=[2,4,5,0,6,7,3,1]        mru=2  victim=1
    //  B9 acesso(set0,1)  -> set0=[1,2,4,5,0,6,7,3]        mru=1  victim=3
    //     (todas as 8 vias do set0 ja foram tocadas ao menos uma vez)
    //  B10 acesso(set0,7) -> set0=[7,1,2,4,5,0,6,3]        mru=7  victim=3
    //  B11 acesso(set0,3) -> set0=[3,7,1,2,4,5,0,6]        mru=3  victim=6
    //  B12 acesso(set0,0) -> set0=[0,3,7,1,2,4,5,6]        mru=0  victim=6
    //     -- checa set1 intacto: ainda [2,0,1,3,4,5,6,7]   mru=2  victim=7
    //
    //  foto final: set0=[0,3,7,1,2,4,5,6] mru=0 victim=6
    //              set1=[2,0,1,3,4,5,6,7] mru=2 victim=7
    // -------------------------------------------------------------------
    task run_part_b;
    begin
        $display("==================================================================");
        $display("PARTE B: repl_lru_nway com SETS=%0d WAYS=%0d (config real do L2)", B_SETS, B_WAYS);
        $display("==================================================================");

        b_wr_en_i    = 1'b0;
        b_wr_index_i = {B_INDEX_W{1'b0}};
        b_wr_way_i   = {B_WAY_W{1'b0}};
        b_rd_index_i = {B_INDEX_W{1'b0}};

        // pos-reset: ordem total 0(MRU) > 1 > ... > 7(LRU) em ambos os sets
        $display("---- pos-reset (todos os sets) ----");
        b_check_state("pos-reset set0", 1'd0, 3'd0, 3'd7);
        b_check_state("pos-reset set1", 1'd1, 3'd0, 3'd7);

        $display("---- sequencia B1..B4 (set0) ----");
        b_do_update(1'd0, 3'd3); // B1
        b_check_state("B1", 1'd0, 3'd3, 3'd7);

        // consulta a vitima ANTES do fill (simula a decisao de despejo de
        // um MISS real: cache_datapath.v pulsa miss_o, o integrador
        // consulta rd_victim_way_o com rd_index_i=set, faz o fill, e so
        // DEPOIS pulsa wr_en_i com a via recem-preenchida -- mesmo padrao
        // de uso documentado em repl_lru.v e exercitado em repl_lru_tb.v).
        b_check_victim("B2 antes do fill (vitima pos B1)", 1'd0, 3'd7);
        b_do_update(1'd0, 3'd7); // B2 (fill na via vitima que acabou de ser consultada)
        b_check_state("B2", 1'd0, 3'd7, 3'd6);
        b_do_update(1'd0, 3'd6); // B3
        b_check_state("B3", 1'd0, 3'd6, 3'd5);
        b_do_update(1'd0, 3'd0); // B4
        b_check_state("B4", 1'd0, 3'd0, 3'd5);

        $display("---- independencia: set1 intacto apos B1..B4 ----");
        b_check_state("set1 intacto (pos B4)", 1'd1, 3'd0, 3'd7);

        $display("---- B5 (set1) ----");
        b_do_update(1'd1, 3'd2); // B5
        b_check_state("B5", 1'd1, 3'd2, 3'd7);

        $display("---- independencia: set0 intacto apos B5 ----");
        b_check_state("set0 intacto (pos B5)", 1'd0, 3'd0, 3'd5);

        $display("---- sequencia B6..B9 (set0, completa as 8 vias) ----");
        b_do_update(1'd0, 3'd5); // B6
        b_check_state("B6", 1'd0, 3'd5, 3'd4);
        b_do_update(1'd0, 3'd4); // B7
        b_check_state("B7", 1'd0, 3'd4, 3'd2);
        b_do_update(1'd0, 3'd2); // B8
        b_check_state("B8", 1'd0, 3'd2, 3'd1);
        b_do_update(1'd0, 3'd1); // B9
        b_check_state("B9", 1'd0, 3'd1, 3'd3);

        $display("---- sequencia B10..B12 (set0, reordenacao geral) ----");
        b_do_update(1'd0, 3'd7); // B10
        b_check_state("B10", 1'd0, 3'd7, 3'd3);
        b_do_update(1'd0, 3'd3); // B11
        b_check_state("B11", 1'd0, 3'd3, 3'd6);
        b_do_update(1'd0, 3'd0); // B12
        b_check_state("B12", 1'd0, 3'd0, 3'd6);

        $display("---- independencia final: set1 intacto ----");
        b_check_state("set1 final", 1'd1, 3'd2, 3'd7);

        $display("---- foto final ----");
        b_check_state("final set0", 1'd0, 3'd0, 3'd6);
        b_check_state("final set1", 1'd1, 3'd2, 3'd7);
    end
    endtask

    // ---- geracao de clock (compartilhada pelas 2 partes) -----------------
    always #5 clk = ~clk;

    initial begin
        errors = 0;
        clk    = 1'b0;
        rst    = 1'b1;

        a_wr_en_i    = 1'b0;
        a_wr_index_i = {A_INDEX_W{1'b0}};
        a_wr_way_i   = {A_WAY_W{1'b0}};
        a_rd_index_i = {A_INDEX_W{1'b0}};
        b_wr_en_i    = 1'b0;
        b_wr_index_i = {B_INDEX_W{1'b0}};
        b_wr_way_i   = {B_WAY_W{1'b0}};
        b_rd_index_i = {B_INDEX_W{1'b0}};

        // libera reset sincrono (comum aos dois DUTs) apos algumas bordas
        @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        run_part_a;
        run_part_b;

        $display("==================================================================");
        if (errors == 0)
            $display("RESULTADO: PASS (0 erros)");
        else
            $display("RESULTADO: FAIL (%0d erro(s))", errors);
        $display("==================================================================");

        $finish;
    end

endmodule
