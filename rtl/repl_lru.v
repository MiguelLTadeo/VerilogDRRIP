// =============================================================================
// repl_lru.v
// PI4 UNIPAMPA - simulador de cache RTL (Fase 2 do plano de validacao)
//
// Responsabilidade deste modulo:
//   Manter, para cada SET, 1 bit de estado que registra qual via foi usada
//   mais recentemente (MRU - Most Recently Used). Como so existe 1 bit de
//   estado por set, ele so consegue distinguir 2 vias (a MRU e a "outra"),
//   entao a via vitima (LRU - Least Recently Used) e sempre o COMPLEMENTO
//   da via MRU armazenada.
//
//   Fluxo de uso pelo integrador (cache_addr + repl_lru + logica de
//   hit/miss, que fica em modulo/fase futura):
//     - HIT na via W do set S: pulsar wr_en_i=1, wr_index_i=S, wr_way_i=W
//       no proximo posedge clk -> marca a via W como MRU do set S.
//     - MISS no set S: consultar rd_victim_way_o com rd_index_i=S
//       (combinacional) para saber qual via deve ser despejada/realocada;
//       apos o fill nessa via (escrita no storage do cache_addr), pulsar
//       wr_en_i=1 com wr_index_i=S, wr_way_i=rd_victim_way_o para marcar a
//       via recem-preenchida como MRU (mesma acao de "marcar MRU" usada no
//       hit; nao ha necessidade de uma porta de update separada).
//
// -----------------------------------------------------------------------
// LIMITACAO DE PROJETO (leia antes de reusar este modulo com WAYS != 2):
//
//   Este e um LRU de 1 bit por set, tecnica classica que so representa
//   corretamente a ordem de uso para associatividade EXATAMENTE IGUAL A 2
//   (2-way, como a config real do PI4: 4KB/32B/2-way/64 sets). Com 1 bit
//   so da para codificar "qual das 2 vias e a mais nova", nao existe
//   informacao suficiente para ordenar 3+ vias (seria necessario um
//   contador/registro de ordem por via, tipicamente log2(WAYS!) bits ou um
//   vetor de prioridades). Por isso o parametro WAYS existe aqui somente
//   para manter a assinatura alinhada ao restante do projeto e para
//   dimensionar WAY_W; a ELABORACAO FALHA DE PROPOSITO (ver bloco
//   generate g_assert_ways_eq_2 abaixo) se WAYS != 2, em vez de sintetizar silenciosamente um LRU
//   incorreto. Fases futuras (repl_srrip/repl_brrip, itens 3 e 4 do plano)
//   generalizam para N vias usando contadores RRPV por via, que e o
//   mecanismo que de fato escala para associatividades maiores.
// =============================================================================

module repl_lru #(
    parameter SETS = 4, // numero de conjuntos (sets)
    parameter WAYS = 2  // associatividade (vias por set) -- DEVE ser 2 (ver acima)
)(
    clk, rst,
    wr_en_i, wr_way_i, wr_index_i,
    rd_index_i, rd_mru_way_o, rd_victim_way_o
);

    // ---- larguras derivadas: mesmo padrao de cache_addr.v, nunca
    //      hardcoded, calculadas a partir dos parameters. Declaradas aqui,
    //      logo no inicio do corpo do modulo -- estilo de porta
    //      Verilog-1995/2001 NAO-ANSI (a lista de parametros #(...) so
    //      aceita `parameter` de verdade nesta sintaxe, compativel com o
    //      Quartus II 13.0sp1/Cyclone III alvo do projeto). ---------------
    localparam INDEX_W = $clog2(SETS);                 // bits de indice do set
    localparam WAY_W   = (WAYS > 1) ? $clog2(WAYS) : 1;  // bits p/ selecionar a via

    input  wire                  clk;
    input  wire                  rst;        // reset SINCRONO, ativo alto

    // ---- porta de atualizacao do estado MRU (sincrona) ----------------------
    // usada tanto em HIT (marca a via acessada como MRU) quanto logo apos
    // o fill de uma linha em MISS/eviction (marca a via recem-preenchida
    // como MRU). E a MESMA acao de hardware nos dois casos: "esta via
    // deste set passou a ser a mais recentemente usada".
    input  wire                  wr_en_i;
    input  wire [WAY_W-1:0]      wr_way_i;
    input  wire [INDEX_W-1:0]    wr_index_i;

    // ---- porta de consulta do set (combinacional) ----------------------------
    // usada pela logica de hit/miss (modulo/fase futura) para decidir, em
    // caso de MISS, qual via deve ser a vitima da substituicao.
    input  wire [INDEX_W-1:0]    rd_index_i;
    output wire [WAY_W-1:0]      rd_mru_way_o;    // via mais recentemente usada do set consultado
    output wire [WAY_W-1:0]      rd_victim_way_o; // via vitima (LRU) = complemento da MRU, so valido p/ WAYS==2

    // -------------------------------------------------------------------
    // Guarda de elaboracao: este LRU de 1 bit por set so e correto para
    // WAYS==2 (ver limitacao de projeto no cabecalho). Se alguem
    // instanciar este modulo com WAYS != 2, forcamos um erro de
    // elaboracao em vez de deixar o modulo sintetizar silenciosamente um
    // LRU errado.
    //
    // NOTA sobre idiomas que NAO funcionam aqui (testados e descartados):
    //   - `wire [-1:0] x;`: IEEE 1364-2005 SS7.1.5 trata indices negativos
    //     como validos (largura = |msb-lsb|+1 = 2 bits) -- compila
    //     silenciosamente em qualquer ferramenta, no maximo com aviso de
    //     "sinal nao usado". NAO bloqueia nada.
    //   - `localparam integer x = 1/(WAYS==2);`: divisao por zero em
    //     expressao constante de localparam produz 'x' silenciosamente no
    //     ModelSim/Questa (comprovado experimentalmente: `Errors: 0`,
    //     valor exibido = 'x'), sem abortar elaboracao. NAO bloqueia nada.
    //
    // Idioma que REALMENTE funciona (comprovado com WAYS=4 forcado -- ver
    // relatorio de entrega para o log completo do vsim): instanciar, DENTRO
    // do ramo `generate` que so existe quando WAYS != 2, um modulo cujo
    // nome nao existe em lugar nenhum do projeto. Quando WAYS==2 esse ramo
    // nunca e gerado (nenhum problema). Quando WAYS!=2 o elaborador tenta
    // resolver o nome do modulo, nao encontra e aborta com erro fatal de
    // elaboracao ("design unit was not found" / "Error loading design",
    // exit code != 0) -- comportamento robusto em ModelSim/Questa e
    // equivalente em Quartus (falha de resolucao de instancia tambem e
    // erro fatal de elaboracao/sintese la).
    // -------------------------------------------------------------------
    generate
        if (WAYS != 2) begin : g_assert_ways_eq_2
            repl_lru_requires_ways_eq_2_do_not_instantiate_with_other_ways u_ways_guard ();
        end
    endgenerate

    // -------------------------------------------------------------------
    // Estado por set: 1 registrador de WAY_W bits (== 1 bit quando
    // WAYS==2) guardando o INDICE da via MRU daquele set. A via vitima
    // (LRU) e sempre a outra via, obtida por complemento bit a bit --
    // valido justamente porque so existem 2 valores possiveis (0 e 1)
    // para uma via quando WAYS==2.
    //
    // Leitura (rd_mru_way_o/rd_victim_way_o, mais abaixo) e COMBINACIONAL
    // -- sem registrar rd_index_i em clk -- mesmo padrao adotado em
    // cache_addr.v para o storage de tag/valid/data (ver comentario la,
    // linhas ~82-99). Leitura combinacional NAO e o padrao que o Quartus
    // reconhece para inferir M9K no Cyclone III; o inferenciador so mapeia
    // para M9K com leitura SINCRONA (endereco registrado, dado valido um
    // ciclo depois). Nesta fase de validacao (array minusculo, WAY_W=1 bit
    // x poucos sets) o resultado esperado da sintese e LEs/MLAB, nao M9K,
    // entao isso nao e um problema aqui. A decisao de registrar essa
    // leitura (para permitir inferencia de M9K na config final de FPGA)
    // fica FORA de escopo desta fase e deve ser revisitada junto com a
    // mesma decisao ja sinalizada em cache_addr.v, nas fases de
    // integracao/sintese final do projeto.
    // -------------------------------------------------------------------
    reg [WAY_W-1:0] mru_way [0:SETS-1];

    // indice de varredura usado so para o reset sincrono do array
    // (limite estatico definido pelo parameter SETS -> sintetizavel).
    integer s_rst;

    // ---- atualizacao sincrona do estado MRU -----------------------------
    // reset sincrono define a via 0 como MRU (logo, via 1 como vitima
    // inicial) em TODOS os sets, deixando a simulacao 100% deterministica.
    // fora do reset, so o set enderecado por wr_index_i e atualizado
    // quando wr_en_i esta ativo, gravando a via indicada como nova MRU.
    always @(posedge clk) begin
        if (rst) begin
            for (s_rst = 0; s_rst < SETS; s_rst = s_rst + 1) begin
                mru_way[s_rst] <= {WAY_W{1'b0}};
            end
        end else if (wr_en_i) begin
            mru_way[wr_index_i] <= wr_way_i;
        end
    end

    // ---- consulta combinacional do set -----------------------------------
    assign rd_mru_way_o    = mru_way[rd_index_i];
    assign rd_victim_way_o = ~mru_way[rd_index_i];

endmodule
