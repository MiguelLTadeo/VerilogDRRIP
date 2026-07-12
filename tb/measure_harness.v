// =============================================================================
// measure_harness.v
// PI4 UNIPAMPA - simulador de cache RTL (Fase 8 PARTE 2 do plano de medicao)
//
// Responsabilidade deste modulo:
//   Harness de MEDICAO de hit rate: le um trace de enderecos de um ARQUIVO
//   texto, aplica cada acesso em cache_datapath.v (Fase 6) respeitando o
//   protocolo valid/ready documentado la, conta hits/misses observando
//   hit_o/miss_o, e ao final imprime o hit rate (%). E um modulo de
//   TESTBENCH (usa $fopen/$fscanf/$feof, `initial`) -- NAO e RTL
//   sintetizavel, por isso vive em tb/, nao em rtl/ (mesma distincao ja
//   estabelecida no projeto entre DUT e testbench).
//
// -----------------------------------------------------------------------
// POR QUE UM MODULO GENERICO + WRAPPERS FINOS (em vez de 1 arquivo por
// combinacao config x politica)
// -----------------------------------------------------------------------
//   Verilog nao tem uma forma limpa e portavel de sobrescrever parameters
//   de um MODULO DE TOPO de simulacao a partir da linha de comando do
//   ModelSim sem depender de flags especificas de ferramenta (-g/-G) que
//   nao teriam paralelo direto em outra toolchain, alem de string
//   parameters (o caminho do trace) serem mais fragis de passar por esse
//   canal (aspas/escaping dependente de shell). A solucao adotada aqui:
//   este arquivo define um modulo REUTILIZAVEL (measure_harness, com
//   parameters e SEM portas -- e sua propria "top-level" de simulacao,
//   gera o proprio clk/rst) que recebe TUDO (config da cache, politica,
//   caminho do trace, valores esperados para autoverificacao opcional) via
//   parameter #() normal. Cada combinacao config x politica ganha um
//   arquivo de "wrapper" TRIVIAL (ex. tb/measure_val_lru_tb.v) que so
//   instancia measure_harness com os parameters daquela combinacao -- o
//   MESMO padrao ja sugerido pelo coordenador desta fase, e consistente
//   com o estilo do projeto de 1 modulo top por cenario de simulacao (ver
//   sim/*.do, 1 script por cenario).
//
// -----------------------------------------------------------------------
// FORMATO DO TRACE (arquivo texto simples)
// -----------------------------------------------------------------------
//   1 acesso por linha: "<CMD> <ENDERECO_HEX>", separados por espaco.
//     CMD = "R" (leitura) ou "W" (escrita) -- qualquer caractere que NAO
//           seja exatamente "W" e tratado como leitura (fail-safe: um
//           trace todo minusculo "r"/typo nunca vira escrita por acidente).
//     ENDERECO_HEX = endereco em hexadecimal, SEM prefixo "0x", largura
//           ADDR_W bits (zero-extendido automaticamente por $fscanf se o
//           trace tiver menos digitos que o necessario).
//   Linhas em branco entre entradas sao toleradas (o proprio $fscanf com
//   "%s" pula qualquer whitespace, inclusive quebras de linha, procurando
//   o proximo token). NAO ha suporte a comentarios (#...) neste formato --
//   escolha deliberada de simplicidade: o foco do projeto e hit RATE, nao
//   um parser de trace robusto; a Fase 9 (traces reais extraidos via
//   valgrind/lackey) pode gerar o arquivo ja limpo, sem comentarios.
//   Escolhido "R/W + endereco" (em vez de so o endereco cru assumindo
//   sempre leitura) porque cache_datapath.v ja implementa write-back/
//   write-allocate de verdade (Fase 6) -- vale exercitar o campo we_i
//   tambem no harness de medicao, mesmo o CONTEUDO escrito nao importando
//   pro hit rate (ver nota de wdata_i/fill_data_i abaixo).
//
// -----------------------------------------------------------------------
// SIMPLIFICACAO DELIBERADA: conteudo de dado (wdata_i/fill_data_i) e FIXO
// -----------------------------------------------------------------------
//   cache_datapath.v decide hit/miss por TAG/VALID, nunca pelo CONTEUDO do
//   bloco (ver o proprio RTL: hit_c/hit_way_c comparam so tag_mem/
//   valid_mem). Por isso este harness amarra wdata_i (dado de uma escrita)
//   e fill_data_i (bloco "vindo da memoria" num fill) em CONSTANTES fixas
//   (zero) -- o conteudo nunca influencia hit/miss/hit-rate, so a
//   PRESENCA/tag da linha influencia. Documentado explicitamente aqui
//   (e nos wrappers) para nao ser confundido com um bug/omissao.
//
// -----------------------------------------------------------------------
// PROTOCOLO valid/ready RESPEITADO (ver cabecalho de cache_datapath.v)
// -----------------------------------------------------------------------
//   A task issue_access (abaixo) NUNCA pulsa req_i sem antes confirmar
//   ready_o==1 numa borda de negedge -- exatamente o uso "legitimo e
//   esperado" que o proprio cabeçalho de cache_datapath.v descreve (nunca
//   reemite/mantem req_i alto sem trocar de transacao, nunca envia um novo
//   pedido enquanto o anterior ainda esta pendente em S_WAIT_VICTIM). Isso
//   automaticamente absorve a latencia variavel de um MISS (1 ciclo para
//   hit, 1+N ciclos para miss, N dependendo de quantos ciclos a politica
//   plugada leva para responder victim_valid_i/victim_valid_o) sem
//   nenhuma logica especial no loop principal: o proximo issue_access so
//   avanca quando ready_o volta a 1, o que so acontece depois do
//   fill_done_o do acesso anterior.
//
// -----------------------------------------------------------------------
// GLUE LOGIC de politica (LRU vs DRRIP) -- fios continuos, sem FSM propria
// -----------------------------------------------------------------------
//   Nenhuma logica sequencial adicional e necessaria aqui alem da
//   instancia do modulo de politica escolhido: tanto repl_lru_nway.v
//   quanto repl_drrip.v ja foram desenhados (Fases 6/7/8-parte1) para se
//   encaixar na interface PLUGAVEL de cache_datapath.v via fios diretos
//   (ver DECISAO DE PROJETO #2 em cache_datapath.v):
//     LRU:   victim_valid_i amarrado fixo em 1'b1 (resposta combinacional
//            sempre disponivel); victim_way_i = rd_victim_way_o do LRU
//            consultando rd_index_i=access_index_o; wr_en_i do LRU pulsa
//            em (hit_o | fill_done_o), com wr_way_i/wr_index_i =
//            access_way_o/access_index_o (LRU trata hit e fill como a
//            MESMA acao, "esta via virou MRU").
//     DRRIP: victim_req_i do repl_drrip = miss_o do datapath (o proprio
//            cabecalho de cache_datapath.v documenta miss_o como pulso de
//            1 ciclo EQUIVALENTE ao contrato de victim_req_i, desenhado de
//            proposito para bater); victim_valid_o/victim_way_o do
//            repl_drrip -> victim_valid_i/victim_way_i do datapath;
//            hit_o->hit_en_i, fill_done_o->fill_en_i, ambos com
//            way_i/index_i = access_way_o/access_index_o.
//   Selecao entre os dois via `generate if (USE_DRRIP)`, resolvido em
//   tempo de elaboracao (parameter, nao sinal de runtime) -- so 1 dos 2
//   modulos de politica e efetivamente instanciado por rodada de
//   simulacao, sem necessidade de mux em runtime.
// =============================================================================

`timescale 1ns/1ps

module measure_harness #(
    // ---- config da cache sob medicao (Apendice B / config de validacao) ----
    parameter ADDR_W = 8,
    parameter BLK_B  = 4,
    parameter SETS   = 4,
    parameter WAYS   = 2,

    // ---- selecao de politica: 0=LRU (repl_lru_nway.v), 1=DRRIP (repl_drrip.v) --
    parameter USE_DRRIP = 0,

    // ---- parametros exclusivos do DRRIP (ignorados quando USE_DRRIP=0) -----
    parameter RRPV_BITS           = 2,
    parameter BRRIP_THROTTLE_BITS = 5,
    parameter PSEL_BITS           = 10,
    parameter SDM_SEL_BITS        = 4,

    // ---- caminho do arquivo de trace (relativo ao cwd do vsim, que e a
    //      raiz do projeto /home/miguel/verilog por convencao, ver .do) -----
    parameter TRACE_FILE = "tb/traces/none.txt",

    // ---- autoverificacao OPCIONAL (usada pelo trace de VALIDACAO do
    //      proprio harness, onde o hit rate e calculado a mao -- ver
    //      tb/measure_val_lru_tb.v/tb/measure_val_drrip_tb.v). Valor -1
    //      (default) desliga a checagem correspondente -- usado pelos
    //      wrappers de config de ENTREGA (L1/L2), onde so se espera que a
    //      simulacao RODE sem erro, sem um valor de referencia calculado a
    //      mao (Fase 9 fara essa comparacao de verdade com benchmarks). --
    parameter integer EXPECTED_ACCESSES = -1,
    parameter integer EXPECTED_HITS     = -1
)();

    // ---- larguras derivadas: MESMA formula de cache_addr.v/
    //      cache_datapath.v/repl_*.v, nunca hardcoded. -----------------------
    localparam INDEX_W = $clog2(SETS);
    localparam WAY_W   = (WAYS > 1) ? $clog2(WAYS) : 1;

    reg clk;
    reg rst;

    // ---- interface com cache_datapath.v -------------------------------------
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

    wire                  victim_valid_i;
    wire [WAY_W-1:0]      victim_way_i;

    wire [BLK_B*8-1:0]    fill_data_i;

    wire                  wb_req_o;
    wire [ADDR_W-1:0]     wb_addr_o;
    wire [BLK_B*8-1:0]    wb_data_o;

    // conteudo de dado FIXO/deterministico -- ver nota "SIMPLIFICACAO
    // DELIBERADA" no cabecalho: hit/miss nunca depende de conteudo.
    assign fill_data_i = {(BLK_B*8){1'b0}};

    cache_datapath #(
        .ADDR_W (ADDR_W),
        .BLK_B  (BLK_B),
        .SETS   (SETS),
        .WAYS   (WAYS)
    ) u_dut (
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

    // ---- saidas de debug do DRRIP promovidas ao ESCOPO DE TOPO deste modulo
    //      (fora do bloco generate): permite que o bloco `initial` mais
    //      abaixo as leia com uma referencia SIMPLES, sem depender de nome
    //      hierarquico dentro de um bloco `generate` -- referencia
    //      hierarquica a um escopo `generate` que nao foi ELABORADO (ex.
    //      `g_drrip.sinal` quando USE_DRRIP=0, caso em que o bloco g_drrip
    //      simplesmente NAO EXISTE) e erro de ELABORACAO, nao passivel de
    //      ser evitado so por um `if` em tempo de EXECUCAO -- por isso os
    //      sinais de debug moram aqui, sempre presentes independente da
    //      politica escolhida (na config LRU ficam simplesmente sem
    //      nenhum driver, o que e inofensivo: so sao exibidos quando
    //      USE_DRRIP==1, ver bloco `initial` abaixo).
    wire [PSEL_BITS-1:0] dbg_psel_o;
    wire                 dbg_follower_use_brrip_o;

    // -------------------------------------------------------------------
    // GLUE de politica -- ver "GLUE LOGIC de politica" no cabecalho.
    // Apenas 1 dos 2 ramos abaixo e efetivamente elaborado (USE_DRRIP e
    // parameter, resolvido em tempo de elaboracao).
    // -------------------------------------------------------------------
    generate
        if (USE_DRRIP) begin : g_drrip
            wire                 drrip_victim_valid_o;
            wire [WAY_W-1:0]     drrip_victim_way_o;
            wire                 drrip_victim_busy_o;

            repl_drrip #(
                .SETS                (SETS),
                .WAYS                (WAYS),
                .RRPV_BITS           (RRPV_BITS),
                .BRRIP_THROTTLE_BITS (BRRIP_THROTTLE_BITS),
                .PSEL_BITS           (PSEL_BITS),
                .SDM_SEL_BITS        (SDM_SEL_BITS)
            ) u_pol (
                .clk                   (clk),
                .rst                   (rst),
                .hit_en_i              (hit_o),
                .hit_way_i             (access_way_o),
                .hit_index_i           (access_index_o),
                .fill_en_i             (fill_done_o),
                .fill_way_i            (access_way_o),
                .fill_index_i          (access_index_o),
                .victim_req_i          (miss_o),          // ver cabecalho: miss_o == victim_req_i por construcao
                .victim_index_i        (access_index_o),
                .victim_busy_o         (drrip_victim_busy_o),
                .victim_valid_o        (drrip_victim_valid_o),
                .victim_way_o          (drrip_victim_way_o),
                .rd_way_i              ({WAY_W{1'b0}}),   // porta de debug, nao usada pelo harness
                .rd_index_i            ({INDEX_W{1'b0}}),
                .rd_rrpv_o             (),
                .psel_o                (dbg_psel_o),
                .follower_use_brrip_o  (dbg_follower_use_brrip_o),
                .rd_is_sdm_srrip_o     (),
                .rd_is_sdm_brrip_o     ()
            );

            assign victim_valid_i = drrip_victim_valid_o;
            assign victim_way_i   = drrip_victim_way_o;
        end else begin : g_lru
            wire [WAY_W-1:0] lru_victim_way_o;

            repl_lru_nway #(
                .SETS (SETS),
                .WAYS (WAYS)
            ) u_pol (
                .clk            (clk),
                .rst            (rst),
                .wr_en_i        (hit_o | fill_done_o), // LRU trata hit e fill como a mesma acao (MRU)
                .wr_way_i       (access_way_o),
                .wr_index_i     (access_index_o),
                .rd_index_i     (access_index_o),
                .rd_mru_way_o   (),
                .rd_victim_way_o(lru_victim_way_o)
            );

            assign victim_valid_i = 1'b1; // resposta LRU e combinacional, sempre disponivel
            assign victim_way_i   = lru_victim_way_o;
        end
    endgenerate

    // ---- clock (100 MHz simulado) --------------------------------------
    always #5 clk = ~clk;

    // =========================================================================
    // ---- leitura do trace + contagem de hit/miss ------------------------------
    // =========================================================================
    integer fd;
    integer rc;
    reg [7:0]         cmd_byte;
    reg [ADDR_W-1:0]  addr_val;

    integer total_accesses;
    integer hits;
    integer misses;
    integer harness_errors;

    real hit_rate_pct;

    // ---- emite 1 acesso, respeitando ready_o, e classifica hit/miss ---------
    task issue_access(input [7:0] cmd, input [ADDR_W-1:0] addr);
    begin
        // espera o DUT estar pronto (S_IDLE) -- protocolo valid/ready, ver
        // cabecalho. Nunca reemite req_i sem confirmar ready_o==1 antes.
        while (ready_o !== 1'b1) begin
            @(negedge clk);
        end

        req_i   = 1'b1;
        we_i    = (cmd == "W") ? 1'b1 : 1'b0; // qualquer coisa != "W" e leitura (fail-safe)
        addr_i  = addr;
        wdata_i = {(BLK_B*8){1'b0}}; // conteudo fixo, ver "SIMPLIFICACAO DELIBERADA"
        @(negedge clk); // pulso de 1 ciclo, mesmo idioma de cache_datapath_tb.v/do_req
        req_i   = 1'b0;
        we_i    = 1'b0;

        // hit_o/miss_o ja estao validos aqui (registrados na borda que
        // acabou de passar -- DECISAO DE PROJETO #3 em cache_datapath.v).
        total_accesses = total_accesses + 1;
        if (hit_o) begin
            hits = hits + 1;
        end else if (miss_o) begin
            misses = misses + 1;
        end else begin
            harness_errors = harness_errors + 1;
            $display("ERRO HARNESS: nem hit_o nem miss_o pulsou apos req aceito (addr=%h) -- bug no harness ou no DUT", addr);
        end
    end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        req_i   = 1'b0;
        we_i    = 1'b0;
        addr_i  = {ADDR_W{1'b0}};
        wdata_i = {(BLK_B*8){1'b0}};

        total_accesses  = 0;
        hits            = 0;
        misses          = 0;
        harness_errors  = 0;

        @(negedge clk);
        @(negedge clk);
        rst = 1'b0;
        @(negedge clk);

        $display("==================================================================");
        $display("measure_harness: trace='%0s'", TRACE_FILE);
        $display("  config: ADDR_W=%0d BLK_B=%0d SETS=%0d WAYS=%0d policy=%0s",
                   ADDR_W, BLK_B, SETS, WAYS, USE_DRRIP ? "DRRIP" : "LRU");
        $display("==================================================================");

        fd = $fopen(TRACE_FILE, "r");
        if (fd == 0) begin
            $display("ERRO FATAL: nao foi possivel abrir o trace '%0s'", TRACE_FILE);
            harness_errors = harness_errors + 1;
        end else begin
            while (!$feof(fd)) begin
                rc = $fscanf(fd, "%s %h", cmd_byte, addr_val);
                if (rc == 2) begin
                    issue_access(cmd_byte, addr_val);
                end
            end
            $fclose(fd);
        end

        hit_rate_pct = (total_accesses > 0) ? (100.0 * hits / total_accesses) : 0.0;

        $display("------------------------------------------------------------------");
        $display("  acessos totais = %0d", total_accesses);
        $display("  hits           = %0d", hits);
        $display("  misses         = %0d", misses);
        $display("  HIT RATE       = %0.3f %%", hit_rate_pct);
        if (USE_DRRIP) begin
            $display("  PSEL final (debug)            = %0d", dbg_psel_o);
            $display("  follower_use_brrip_o final     = %0b", dbg_follower_use_brrip_o);
        end
        $display("------------------------------------------------------------------");

        // ---- autoverificacao opcional (config de VALIDACAO do harness) ----
        if (EXPECTED_ACCESSES >= 0) begin
            if (total_accesses !== EXPECTED_ACCESSES) begin
                harness_errors = harness_errors + 1;
                $display("FALHA: esperado %0d acessos, obtido %0d", EXPECTED_ACCESSES, total_accesses);
            end else begin
                $display("OK: total de acessos bate com o esperado (%0d)", total_accesses);
            end
        end
        if (EXPECTED_HITS >= 0) begin
            if (hits !== EXPECTED_HITS) begin
                harness_errors = harness_errors + 1;
                $display("FALHA: esperado %0d hits, obtido %0d", EXPECTED_HITS, hits);
            end else begin
                $display("OK: total de hits bate com o esperado (%0d)", hits);
            end
        end

        $display("==================================================================");
        if (harness_errors == 0)
            $display("RESULTADO: PASS (0 erros)");
        else
            $display("RESULTADO: FAIL (%0d erro(s))", harness_errors);
        $display("==================================================================");

        $finish;
    end

endmodule
