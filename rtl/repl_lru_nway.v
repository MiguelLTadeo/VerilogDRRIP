// =============================================================================
// repl_lru_nway.v
// PI4 UNIPAMPA - simulador de cache RTL (Fase 7 do plano de validacao)
//
// Responsabilidade deste modulo:
//   Generalizar o LRU de 1 bit por set da Fase 2 (repl_lru.v, que so e
//   correto para WAYS==2 -- ver o guard de elaboracao la) para QUALQUER
//   associatividade WAYS >= 1, em particular a config real do L2 do
//   Apendice B (8-way). Mantem TRUE LRU exato (nao e uma aproximacao),
//   usando a tecnica classica de MATRIZ DE BITS de recencia por par de
//   vias (bit-matrix / "MRU matrix" LRU), a mesma descrita em textos de
//   arquitetura de computadores para TLBs/caches associativos e usada
//   historicamente em hardware real (ex.: familia MIPS R4000/R10000).
//
// -----------------------------------------------------------------------
// DECISAO DE ARQUITETURA: MATRICIAL (true LRU) em vez de tree-PLRU
// -----------------------------------------------------------------------
//   O plano (Fase 7) deixa a escolha aberta entre LRU matricial (O(WAYS^2)
//   de area, mas ORDEM EXATA de recencia entre todas as vias) e tree-PLRU
//   (O(WAYS) de area, mas so uma APROXIMACAO de LRU -- a arvore binaria de
//   bits "aponta" para um subconjunto de vias antigas, nao necessariamente
//   a mais antiga de verdade).
//
//   Escolhido: MATRICIAL. Motivo (ver tambem a nota do prompt desta fase):
//   a metrica de nota do projeto e HIT RATE, comparando LRU (baseline)
//   contra DRRIP. Se a baseline "LRU" na verdade fosse uma aproximacao
//   (tree-PLRU), a comparacao pro Apendice B ficaria contaminada por uma
//   segunda variavel (fidelidade da baseline), alem da politica em si.
//   Para a config real deste projeto (WAYS<=8, L1=2-way/L2=8-way), o custo
//   de area O(WAYS^2) da matriz e 8*8=64 bits de estado POR SET (contra 8
//   bits de uma arvore PLRU) -- para SETS=64 (config de entrega do L2),
//   isso e 64*64=4096 flip-flops so pra este modulo. Cyclone III
//   (EP3C25F324C6) tem ~24k LEs; mesmo sem otimizacao, 4096 FFs cabem
//   folgadamente em LEs/MLAB (nao seria mapeado em M9K de qualquer forma,
//   ver nota de leitura combinacional mais abaixo, mesmo raciocinio de
//   repl_lru.v). Como o escopo deste projeto CORTOU sintese/area no
//   Quartus (ver plano-cache.md, secao "Fora de escopo"), esse calculo e
//   so uma estimativa de sanidade, nao uma validacao de fechamento de
//   sintese -- mas confirma que a "linha" citada no prompt (matricial
//   pode ficar proibitivo em 8-way) NAO e cruzada aqui. Por isso: pesos
//   para matricial, como o prompt sugeriu, e a linha nao chegou a ser
//   atravessada.
//
// -----------------------------------------------------------------------
// COMO FUNCIONA A MATRIZ (por set)
// -----------------------------------------------------------------------
//   Estado: mat[S][i][j] (1 bit), para 0<=i,j<WAYS, i != j (diagonal nao
//   usada, fica sempre 0). Semantica:
//     mat[S][i][j] == 1  <=>  via i foi acessada mais recentemente que a
//                             via j, dentro do set S.
//   O par (mat[S][i][j], mat[S][j][i]) e sempre COMPLEMENTAR por
//   construcao da atualizacao abaixo (nunca ambos 1 nem ambos 0 apos o
//   reset) -- ou seja, a matriz sempre codifica uma ORDEM TOTAL estrita
//   entre as WAYS vias de cada set. Isso e o algoritmo classico de "MRU
//   bit matrix": SIM, ha redundancia de armazenamento (mat[i][j] e
//   mat[j][i] carregam a mesma informacao, com sinal invertido), mas essa
//   redundancia e o que torna a leitura (achar MRU/LRU) um simples
//   AND/OR de linha em vez de exigir um calculo de "rank" mais caro --
//   troca deliberada de area por simplicidade combinacional e de
//   verificacao (mais facil de auditar bit a bit no testbench).
//
//   ATUALIZACAO (mesma acao de hardware para HIT e para FILL apos MISS,
//   EXATAMENTE como em repl_lru.v -- por isso este modulo reusa a MESMA
//   porta unica wr_en_i/wr_way_i/wr_index_i, em vez do par
//   hit_en_i/fill_en_i que repl_srrip.v precisa; ver a nota de
//   nomenclatura no cabecalho de repl_srrip.v para o contraste): ao
//   marcar a via K do set S como "acabou de ser usada",
//     para toda via J != K:  mat[S][K][J] <= 1 ; mat[S][J][K] <= 0
//   ou seja, K passa a ser "mais recente que todo mundo" e todo mundo
//   passa a ser "menos recente que K" -- a ordem relativa ENTRE as demais
//   vias (J1 vs J2, ambas != K) NAO e tocada, preservando a ordem antiga
//   entre elas. Esta e a atualizacao textbook que mantem a matriz sempre
//   como uma ordem total valida (invariante verificado no testbench).
//
//   CONSULTA (combinacional, mesmo padrao de latencia-zero de
//   rd_victim_way_o em repl_lru.v -- ver a nota de leitura combinacional
//   la, linhas ~111-124, que se aplica identicamente aqui):
//     - via MRU do set = a UNICA via cuja LINHA e toda 1 (bateu todo
//       mundo): para todo J != via, mat[S][via][J] == 1.
//     - via vitima (LRU) do set = a UNICA via cuja LINHA e toda 0 (nao
//       bateu ninguem): para todo J != via, mat[S][via][J] == 0.
//     Ambas resolvidas por um priority-encoder sintetizavel (menor indice
//     de via vence em caso de estado nao-canonico -- nunca deveria
//     acontecer dado o invariante de ordem total, mas o priority-encoder
//     torna o hardware determinístico de qualquer forma, mesmo padrao de
//     "menor indice vence" usado em repl_srrip.v/repl_brrip.v).
//
// -----------------------------------------------------------------------
// RESET: por que reproduz EXATAMENTE o reset de repl_lru.v para WAYS==2
// -----------------------------------------------------------------------
//   repl_lru.v inicializa mru_way[S]=via0 em todos os sets (logo
//   victim=via1 pro caso 2-way). Para generalizar isso de forma
//   consistente pra WAYS>2, o reset desta matriz estabelece a ORDEM TOTAL
//   INICIAL "via0 (mais recente) > via1 > via2 > ... > via(WAYS-1) (mais
//   antiga)":
//     mat[S][i][j] <= (i < j) ? 1 : 0   (para todo par i!=j, todo set S)
//   Para WAYS==2 isso da exatamente mat[S][0][1]=1, mat[S][1][0]=0 ->
//   MRU=via0, victim=via1 -- BIT A BIT o mesmo estado inicial de
//   repl_lru.v. Combinado com a mesma regra de atualizacao (marcar K
//   como "bate todo mundo"), a sequencia de MRU/victim produzida por este
//   modulo com WAYS=2 e IDENTICA, passo a passo, a de repl_lru.v para
//   qualquer sequencia de acessos -- validado bit a bit em
//   tb/repl_lru_nway_tb.v reusando a MESMA sequencia de acessos do
//   testbench da Fase 2 (tb/repl_lru_tb.v).
//
// -----------------------------------------------------------------------
// INTERFACE: identica a repl_lru.v (drop-in generalizado)
// -----------------------------------------------------------------------
//   Mesmos nomes de porta, mesma largura derivada (WAY_W/INDEX_W pelas
//   mesmas formulas de cache_addr.v/repl_lru.v), mesmo contrato de uso
//   (wr_en_i pulsa em hit OU em fill-apos-miss; rd_victim_way_o e
//   combinacional e SEMPRE valido, sem handshake de "busy"). Isso significa
//   que este modulo se encaixa em cache_datapath.v (Fase 6) EXATAMENTE do
//   mesmo jeito que repl_lru.v: victim_valid_i do datapath fica amarrado
//   em 1'b1 fixo pelo integrador (ver DECISAO DE PROJETO #2 no cabecalho
//   de cache_datapath.v), rd_index_i <= access_index_o enquanto miss_o
//   esta pendente, e wr_en_i/wr_way_i/wr_index_i pulsam a partir de
//   hit_o/fill_done_o + access_way_o/access_index_o.
// =============================================================================

module repl_lru_nway #(
    parameter SETS = 4, // numero de conjuntos (sets)
    parameter WAYS = 2  // associatividade (vias por set) -- QUALQUER valor >=1
                         // (diferente de repl_lru.v, aqui NAO ha guard de
                         // elaboracao restringindo a 2 -- esta e a
                         // generalizacao que a Fase 7 pede)
)(
    clk, rst,
    wr_en_i, wr_way_i, wr_index_i,
    rd_index_i, rd_mru_way_o, rd_victim_way_o
);

    // ---- larguras derivadas: mesmo padrao/formula de cache_addr.v e
    //      repl_lru.v, nunca hardcoded. Declaradas aqui, logo no inicio do
    //      corpo do modulo -- estilo de porta Verilog-1995/2001 NAO-ANSI (a
    //      lista de parametros #(...) so aceita `parameter` de verdade
    //      nesta sintaxe, compativel com o Quartus II 13.0sp1/Cyclone III
    //      alvo do projeto). --------------------------------------------
    localparam INDEX_W = $clog2(SETS);                 // bits de indice do set
    localparam WAY_W   = (WAYS > 1) ? $clog2(WAYS) : 1;  // bits p/ selecionar a via

    input  wire                  clk;
    input  wire                  rst;        // reset SINCRONO, ativo alto

    // ---- porta de atualizacao do estado MRU (sincrona) ----------------------
    // usada tanto em HIT (marca a via acessada como MRU) quanto logo apos
    // o fill de uma linha em MISS/eviction (marca a via recem-preenchida
    // como MRU) -- MESMA acao de hardware nos dois casos, MESMO contrato
    // de repl_lru.v (ver cabecalho).
    input  wire                  wr_en_i;
    input  wire [WAY_W-1:0]      wr_way_i;
    input  wire [INDEX_W-1:0]    wr_index_i;

    // ---- porta de consulta do set (combinacional) ----------------------------
    // usada pela logica de hit/miss (cache_datapath.v, Fase 6) para saber
    // a via MRU e, em caso de MISS, qual via deve ser a vitima.
    input  wire [INDEX_W-1:0]    rd_index_i;
    output wire [WAY_W-1:0]      rd_mru_way_o;    // via mais recentemente usada do set consultado
    output wire [WAY_W-1:0]      rd_victim_way_o; // via vitima (true LRU exato, qualquer WAYS>=1)

    // -------------------------------------------------------------------
    // Estado: matriz de recencia por set. Array unpacked de 3 dimensoes
    // (Verilog-2001 permite N dimensoes unpacked em "reg ... nome
    // [d0][d1][d2]"), cada elemento e 1 bit (sem largura explicita antes
    // do nome = elemento de 1 bit, mesmo idioma de reg simples). Leitura
    // e COMBINACIONAL (sem registrar rd_index_i em clk) -- mesma decisao
    // deliberada de repl_lru.v (ver a nota de leitura combinacional la,
    // linhas ~111-124): nesta fase de validacao o array e pequeno o
    // bastante (config brinquedo e config de entrega L2, ambas <=64 sets
    // x 8 vias) para o resultado esperado de sintese ser LEs/MLAB, nao
    // M9K -- registrar a leitura pra permitir inferencia de M9K fica fora
    // de escopo aqui, junto com a mesma decisao ja sinalizada em
    // cache_addr.v/repl_lru.v.
    // -------------------------------------------------------------------
    reg mat [0:SETS-1][0:WAYS-1][0:WAYS-1];

    // indices de varredura do reset sincrono (limites estaticos definidos
    // pelos parameters SETS/WAYS -> sintetizavel, mesmo padrao de
    // cache_addr.v/cache_datapath.v pros loops de reset de array).
    integer s_rst, i_rst, j_rst;

    // indice de varredura da atualizacao sincrona (loop sobre as demais
    // vias do set escrito -- limite estatico WAYS, mesmo padrao dos
    // for-loops sintetizaveis de repl_srrip.v/repl_brrip.v).
    integer j_upd;

    // ---- atualizacao sincrona da matriz de recencia ---------------------
    always @(posedge clk) begin
        if (rst) begin
            // ordem total inicial via0(MRU) > via1 > ... > via(WAYS-1)(LRU)
            // em TODOS os sets -- ver "RESET" no cabecalho pra por que
            // isso reproduz bit a bit o reset de repl_lru.v quando WAYS==2.
            for (s_rst = 0; s_rst < SETS; s_rst = s_rst + 1) begin
                for (i_rst = 0; i_rst < WAYS; i_rst = i_rst + 1) begin
                    for (j_rst = 0; j_rst < WAYS; j_rst = j_rst + 1) begin
                        mat[s_rst][i_rst][j_rst] <= (i_rst < j_rst) ? 1'b1 : 1'b0;
                    end
                end
            end
        end else if (wr_en_i) begin
            // via wr_way_i do set wr_index_i passa a bater TODAS as
            // demais vias desse set (diagonal mat[.][K][K] nunca e
            // tocada, permanece 0 desde o reset -- nao tem significado,
            // nunca e lida pelas comparacoes "j != v" abaixo).
            for (j_upd = 0; j_upd < WAYS; j_upd = j_upd + 1) begin
                if (j_upd != wr_way_i) begin
                    mat[wr_index_i][wr_way_i][j_upd] <= 1'b1;
                    mat[wr_index_i][j_upd][wr_way_i] <= 1'b0;
                end
            end
        end
    end

    // -------------------------------------------------------------------
    // Consulta combinacional do set enderecado por rd_index_i:
    //   row_zero_c[v] = 1  <=>  linha v inteira 0 (excluindo diagonal)
    //                           <=> via v e a VITIMA (nao bateu ninguem)
    //   row_one_c[v]  = 1  <=>  linha v inteira 1 (excluindo diagonal)
    //                           <=> via v e a MRU (bateu todo mundo)
    // Dado o invariante de ordem total mantido pela atualizacao acima,
    // exatamente 1 via satisfaz cada condicao (para WAYS>=1; com WAYS==1
    // as duas condicoes sao vacuamente verdadeiras pra via 0, coerente:
    // via unica e MRU e vitima ao mesmo tempo).
    // -------------------------------------------------------------------
    integer v_scan, j_scan;
    reg [WAYS-1:0] row_zero_c;
    reg [WAYS-1:0] row_one_c;
    always @(*) begin
        for (v_scan = 0; v_scan < WAYS; v_scan = v_scan + 1) begin
            row_zero_c[v_scan] = 1'b1;
            row_one_c[v_scan]  = 1'b1;
            for (j_scan = 0; j_scan < WAYS; j_scan = j_scan + 1) begin
                if (j_scan != v_scan) begin
                    if (mat[rd_index_i][v_scan][j_scan]) begin
                        row_zero_c[v_scan] = 1'b0; // bateu alguem -> nao e a vitima
                    end else begin
                        row_one_c[v_scan] = 1'b0;  // perdeu de alguem -> nao e a MRU
                    end
                end
            end
        end
    end

    // ---- priority-encoders sintetizaveis (menor indice vence em empate,
    //      mesmo idioma/estilo de found_c/found_way_c em repl_srrip.v) ---
    integer pv;
    reg                found_victim_c;
    reg [WAY_W-1:0]    victim_way_c;
    reg                found_mru_c;
    reg [WAY_W-1:0]    mru_way_c;
    always @(*) begin
        found_victim_c = 1'b0;
        victim_way_c   = {WAY_W{1'b0}};
        found_mru_c    = 1'b0;
        mru_way_c      = {WAY_W{1'b0}};
        for (pv = 0; pv < WAYS; pv = pv + 1) begin
            if (!found_victim_c && row_zero_c[pv]) begin
                found_victim_c = 1'b1;
                victim_way_c   = pv[WAY_W-1:0];
            end
            if (!found_mru_c && row_one_c[pv]) begin
                found_mru_c = 1'b1;
                mru_way_c   = pv[WAY_W-1:0];
            end
        end
    end

    assign rd_mru_way_o    = mru_way_c;
    assign rd_victim_way_o = victim_way_c;

endmodule
