// =============================================================================
// cache_addr.v
// PI4 UNIPAMPA - simulador de cache RTL (Fase 1 do plano de validacao)
//
// Responsabilidade deste modulo:
//   1) Decodificar um endereco de ADDR_W bits em TAG / INDEX / OFFSET. As
//      larguras de cada campo sao SEMPRE derivadas via localparam a partir
//      dos parameters (nunca hardcoded), para que a config pequena de
//      validacao (ADDR_W=8, BLK_B=4, SETS=4, WAYS=2) escale ate a config
//      final de FPGA (4KB, blocos de 32B, 2-way, 64 sets) so trocando os
//      valores dos parameters na instanciacao.
//   2) Prover o storage por via (tag / valid / data), indexado por
//      [way][set], com uma porta de escrita sincrona (reset sincrono
//      explicito) e uma porta de leitura combinacional. Este storage e a
//      base sobre a qual os modulos de fase seguinte (repl_lru,
//      repl_srrip, repl_brrip, psel_dueling) vao operar.
//
// Explicitamente FORA de escopo nesta fase (fica para modulos futuros):
//   - Comparacao tag/valid entre TODAS as vias para decidir hit/miss e
//     selecionar a via de destino em caso de miss. Este modulo so expõe
//     o endereco decodificado (tag_o) e uma porta de leitura de storage
//     para UMA via/set por vez; a logica de comparacao fica no modulo
//     de hit/miss (fase futura). O testbench faz essa comparacao "na
//     mao" apenas para validar que o storage guarda/devolve os dados
//     corretos.
//   - Armazenamento do RRPV (bits de re-referencia do RRIP). O parametro
//     RRPV_BITS e aceito aqui somente para manter a assinatura do modulo
//     alinhada com a config global do projeto; repl_srrip/repl_brrip
//     (fase 3/4) que vao de fato instanciar o storage de RRPV.
// =============================================================================

module cache_addr #(
    parameter ADDR_W    = 8, // largura do endereco de memoria (bits)
    parameter BLK_B      = 4, // bytes por bloco/linha de cache
    parameter SETS       = 4, // numero de conjuntos (sets)
    parameter WAYS       = 2, // associatividade (vias por set)
    parameter RRPV_BITS  = 2  // reservado p/ storage de RRPV (fase 3/4)
)(
    clk, rst,
    addr_i, tag_o, index_o, offset_o,
    wr_en_i, wr_way_i, wr_index_i, wr_valid_i, wr_tag_i, wr_data_i,
    rd_way_i, rd_index_i, rd_valid_o, rd_tag_o, rd_data_o
);

    // ---- larguras derivadas: NUNCA hardcoded, sempre calculadas a partir
    //      dos parameters acima, para permitir escalar a cache trocando
    //      so os parameters na instanciacao. Declaradas aqui, logo no
    //      inicio do corpo do modulo -- estilo de porta Verilog-1995/2001
    //      NAO-ANSI (a lista de parametros #(...) so aceita `parameter` de
    //      verdade nesta sintaxe, compativel com o Quartus II 13.0sp1/
    //      Cyclone III alvo do projeto) -- porque precisam estar
    //      disponiveis ANTES da declaracao das portas abaixo, que usam
    //      TAG_W/INDEX_W/OFFSET_W/WAY_W para dimensionar seus barramentos;
    //      ordem textual valida em Verilog, ja que a declaracao de porta
    //      vem DEPOIS destes localparams no corpo do modulo. --------------
    localparam OFFSET_W = $clog2(BLK_B);               // bits de offset dentro do bloco
    localparam INDEX_W  = $clog2(SETS);                // bits de indice do set
    localparam TAG_W    = ADDR_W - INDEX_W - OFFSET_W; // bits restantes = tag
    localparam WAY_W    = (WAYS > 1) ? $clog2(WAYS) : 1; // bits p/ selecionar a via

    input  wire                     clk;
    input  wire                     rst;        // reset SINCRONO, ativo alto

    // ---- decodificacao de endereco (puramente combinacional) --------------
    // addr_i = { TAG (MSBs) | INDEX | OFFSET (LSBs) }
    input  wire [ADDR_W-1:0]        addr_i;
    output wire [TAG_W-1:0]         tag_o;
    output wire [INDEX_W-1:0]       index_o;
    output wire [OFFSET_W-1:0]      offset_o;

    // ---- porta de escrita do storage por via (sincrona) --------------------
    // usada pelos modulos de fase futura para alocar/atualizar uma linha
    // (fill em miss, invalidacao, etc.)
    input  wire                     wr_en_i;
    input  wire [WAY_W-1:0]         wr_way_i;
    input  wire [INDEX_W-1:0]       wr_index_i;
    input  wire                     wr_valid_i;
    input  wire [TAG_W-1:0]         wr_tag_i;
    input  wire [BLK_B*8-1:0]       wr_data_i;

    // ---- porta de leitura do storage por via (combinacional) ---------------
    // usada pelos modulos de fase futura para consultar uma via/set ao
    // testar hit/miss (a comparacao em si fica fora deste modulo).
    input  wire [WAY_W-1:0]         rd_way_i;
    input  wire [INDEX_W-1:0]       rd_index_i;
    output wire                     rd_valid_o;
    output wire [TAG_W-1:0]         rd_tag_o;
    output wire [BLK_B*8-1:0]       rd_data_o;

    // -------------------------------------------------------------------
    // Storage por via: um array de registradores para cada campo,
    // indexado [via][set]. A porta de leitura abaixo e COMBINACIONAL
    // (rd_valid_o/rd_tag_o/rd_data_o saem via assign, sem registrar
    // rd_way_i/rd_index_i em clk). Leitura combinacional de memoria nao
    // e o padrao que o Quartus reconhece para inferir blocos M9K do
    // Cyclone III -- o inferenciador de RAM do Quartus so mapeia para
    // M9K quando a leitura e SINCRONA (endereco registrado, dado sai um
    // ciclo depois). Nesta fase de VALIDACAO (config pequena, 4 sets x 2
    // vias) o resultado esperado da sintese e LEs/MLAB (registrador +
    // mux), tanto pela leitura combinacional quanto pelo tamanho minusculo
    // do array. NOTA IMPORTANTE: antes da sintese fisica da config final
    // (4KB / 64 sets / 2 vias / blocos de 32B), sera necessario decidir
    // se a porta de leitura passa a ser registrada (rd_way_i/rd_index_i
    // amostrados em clk, dado valido no ciclo seguinte) para permitir a
    // inferencia de M9K pelo Quartus; essa decisao de timing/latencia
    // fica FORA de escopo desta fase e deve ser revisitada nas fases de
    // integracao/sintese final do projeto.
    // -------------------------------------------------------------------
    reg [TAG_W-1:0]   tag_mem   [0:WAYS-1][0:SETS-1];
    reg               valid_mem [0:WAYS-1][0:SETS-1];
    reg [BLK_B*8-1:0] data_mem  [0:WAYS-1][0:SETS-1];

    // indices de varredura usados so para o reset sincrono de todo o
    // array de valid/tag/data (limites estaticos definidos pelos
    // parameters -> sintetizavel, o synthesizer desenrola o laco).
    integer w_rst, s_rst;

    // ---- decodificacao de endereco -----------------------------------
    assign offset_o = addr_i[OFFSET_W-1:0];
    assign index_o  = addr_i[OFFSET_W + INDEX_W - 1 : OFFSET_W];
    assign tag_o    = addr_i[ADDR_W-1 : OFFSET_W + INDEX_W];

    // ---- escrita sincrona no storage -----------------------------------
    // reset sincrono zera valid/tag/data de TODAS as vias/sets, deixando
    // a simulacao 100% deterministica (nenhum campo comeca em 'x').
    // fora do reset, so a via/set enderecados por wr_way_i/wr_index_i
    // sao atualizados quando wr_en_i esta ativo.
    always @(posedge clk) begin
        if (rst) begin
            for (w_rst = 0; w_rst < WAYS; w_rst = w_rst + 1) begin
                for (s_rst = 0; s_rst < SETS; s_rst = s_rst + 1) begin
                    valid_mem[w_rst][s_rst] <= 1'b0;
                    tag_mem[w_rst][s_rst]   <= {TAG_W{1'b0}};
                    data_mem[w_rst][s_rst]  <= {(BLK_B*8){1'b0}};
                end
            end
        end else if (wr_en_i) begin
            valid_mem[wr_way_i][wr_index_i] <= wr_valid_i;
            tag_mem[wr_way_i][wr_index_i]   <= wr_tag_i;
            data_mem[wr_way_i][wr_index_i]  <= wr_data_i;
        end
    end

    // ---- leitura combinacional do storage -------------------------------
    assign rd_valid_o = valid_mem[rd_way_i][rd_index_i];
    assign rd_tag_o   = tag_mem[rd_way_i][rd_index_i];
    assign rd_data_o  = data_mem[rd_way_i][rd_index_i];

endmodule
