// =============================================================================
// cache_datapath.v
// PI4 UNIPAMPA - simulador de cache RTL (Fase 6 do plano de validacao)
//
// Responsabilidade deste modulo:
//   Implementar a CACHE de verdade ao redor de uma politica de substituicao
//   PLUGAVEL: comparacao de tag entre TODAS as vias de um set (o que
//   cache_addr.v -- Fase 1 -- explicitamente deixou de fora, ver cabecalho
//   la), geracao de hit/miss, leitura/escrita de dados, e bits valid/dirty
//   por linha (politica de escrita, ver secao "POLITICA DE ESCRITA" abaixo).
//
// -----------------------------------------------------------------------
// DECISAO DE PROJETO #1 -- por que este modulo NAO instancia cache_addr.v
// -----------------------------------------------------------------------
//   cache_addr.v (Fase 1) expoe um storage por via com UMA UNICA porta de
//   leitura combinacional (rd_way_i/rd_index_i selecionam 1 via por vez).
//   Isso foi deliberado la (ver linhas ~18-25 daquele arquivo): a
//   comparacao de tag entre TODAS as vias de um set simultaneamente foi
//   empurrada para esta fase. Só que decidir hit/miss EXIGE ler as N vias
//   de um set NO MESMO CICLO (comparacao paralela) -- um unico par
//   rd_way_i/rd_index_i nao da conta disso sem instanciar cache_addr.v
//   WAYS vezes (WAYS storages redundantes, um por "porta de leitura"), o
//   que so pioraria a legibilidade sem nenhum ganho. Por isso este modulo
//   implementa seu PROPRIO storage (tag/valid/dirty/data por via/set),
//   seguindo o MESMO estilo de array [via][set] e reset sincrono de
//   cache_addr.v/repl_srrip.v, mas com leitura paralela das WAYS vias de um
//   set (for-loop sintetizavel, igual ao priority-encoder de
//   repl_srrip.v/repl_brrip.v). cache_addr.v continua sendo o modulo de
//   REFERENCIA/documentacao do split de endereco (reaproveitado aqui via
//   os MESMOS localparams derivados, mesma formula), mas nao e instanciado
//   diretamente.
//
// -----------------------------------------------------------------------
// DECISAO DE PROJETO #2 -- interface de substituicao PLUGAVEL (o ponto
// critico desta fase)
// -----------------------------------------------------------------------
//   repl_lru.v (Fase 2) e repl_srrip.v/repl_brrip.v (Fases 3/4) tem
//   INTERFACES DIFERENTES entre si por necessidade estrutural:
//     - repl_lru: via vitima e COMBINACIONAL/instantanea (rd_victim_way_o
//       nao depende de nenhum "pedido" -- e so o complemento do MRU
//       registrado) e usa uma UNICA porta de escrita (wr_en_i) tanto para
//       hit quanto para fill (mesma acao de hardware).
//     - repl_srrip/repl_brrip: a busca de vitima pode levar MULTIPLOS
//       ciclos (FSM de aging), exigindo um handshake victim_req_i /
//       victim_busy_o / victim_valid_o; alem disso hit e fill sao acoes
//       SEPARADAS (hit_en_i/fill_en_i) com valores-alvo de RRPV diferentes.
//
//   Nao existe um "least common denominator" de sinais que sirva como
//   porta identica para os dois sem forcar um dos dois a fingir uma
//   semantica que nao tem. Por isso, seguindo a alternativa sugerida no
//   plano do projeto, cache_datapath NAO INSTANCIA nenhum repl_* -- ele
//   expoe uma interface GENERICA, MINIMA, do PONTO DE VISTA DO DATAPATH
//   (que e sempre a mesma, nao importa a politica por tras):
//     - miss_o (pulso) + access_index_o = "preciso de uma via vitima para
//       este set" -- equivalente generico ao victim_req_i do RRIP; para o
//       LRU, o integrador simplesmente ja tem a resposta combinacional
//       disponivel e amarra victim_valid_i em 1'b1 fixo.
//     - victim_valid_i / victim_way_i (entradas) = "aqui esta a via
//       vitima" -- equivalente generico ao victim_valid_o/victim_way_o do
//       RRIP ou ao rd_victim_way_o (sempre valido) do LRU.
//     - hit_o / fill_done_o (pulsos) + access_way_o/access_index_o =
//       "isto aconteceu nesta via/set" -- e o que o integrador usa para
//       pulsar hit_en_i/fill_en_i (RRIP) ou wr_en_i (LRU, tanto para hit
//       quanto para fill, ja que repl_lru trata as duas acoes iguais).
//   O datapath e agnostico: ele NUNCA sabe se do outro lado tem um LRU
//   combinacional de 1 ciclo ou uma FSM de RRIP que demora N ciclos -- ele
//   so fica em S_WAIT_VICTIM ate victim_valid_i subir, quantos ciclos isso
//   levar e problema exclusivo do modulo de politica plugado por fora. A
//   integracao real (instanciar repl_lru OU repl_srrip+psel_dueling+
//   repl_brrip ao lado de um cache_datapath e ligar os fios) fica para a
//   Fase 8 (measure_tb), como o plano pede.
//
// -----------------------------------------------------------------------
// DECISAO DE PROJETO #3 -- latencia: hit tambem e REGISTRADO (1 ciclo)
// -----------------------------------------------------------------------
//   Mesmo um HIT so fica visivel (hit_o/rdata_valid_o) 1 ciclo DEPOIS do
//   req_i que o causou (a comparacao de tag e combinacional internamente,
//   mas a saida e amostrada em clk). Escolha deliberada: uniformiza a
//   latencia minima observavel pelo integrador (nunca ha um caminho
//   combinacional "req_i entra -> hit sai -> escreve no mesmo ciclo"),
//   o que evita caminhos combinacionais longos (compara tag -> decide
//   escrita -> grava storage no mesmo ciclo) e simplifica tanto o
//   testbench quanto a futura integracao com o pipeline do RV32I (Fase 8
//   so precisa tratar 2 casos de latencia: "1 ciclo" para hit, "1 + N
//   ciclos" para miss, nunca "0 ciclos").
//
// -----------------------------------------------------------------------
// POLITICA DE ESCRITA (secao 4 da Especificacao de Projeto, PDF na raiz)
// -----------------------------------------------------------------------
//   A secao 4 do PDF ("Configuracao da Hierarquia de Memoria e Espaco de
//   Parametros") lista, na linha "Politica de Escrita": "A atual
//   implementada" -- para L1 e para L2. O PDF NAO especifica concretamente
//   se e write-through/write-back nem write-allocate/no-write-allocate; a
//   frase remete a uma decisao que cada equipe ja teria tomado em etapa
//   anterior do projeto (nao documentada neste repositorio ate esta fase).
//   Na AUSENCIA dessa decisao explicita, este modulo assume e IMPLEMENTA:
//
//     WRITE-BACK: um HIT de escrita so atualiza o dado DENTRO da cache
//     (data_mem) e marca a linha como suja (dirty_mem<=1); NAO propaga a
//     escrita para a memoria/nivel inferior imediatamente. A escrita so
//     "desce" quando a linha suja e EVICTADA (wb_req_o/wb_addr_o/wb_data_o
//     pulsam nesse momento) -- fielmente ao padrao mais comum para cache
//     de DADOS (reduz trafego para a memoria vs. write-through) e ao que
//     usualmente se pressupoe quando a politica de escrita nao e
//     explicitada num enunciado de projeto de cache com foco em hit rate.
//
//     WRITE-ALLOCATE: um MISS de escrita ALOCA a linha (busca o bloco via
//     fill_data_i, igual a um miss de leitura) antes de aplicar a escrita;
//     a linha nasce no cache ja com o dado escrito e dirty_mem<=1 (em vez
//     de escrever direto na memoria e nunca trazer o bloco para o cache,
//     que seria no-write-allocate). Combina naturalmente com write-back
//     (combinacao classica, oposta a write-through+no-write-allocate).
//
//   Esta e uma SUPOSICAO EXPLICITA deste modulo, nao uma leitura literal do
//   PDF (que nao especifica) -- ver tambem o relatorio de entrega desta
//   fase. Se o time confirmar/decidir diferente (ex.: write-through), a
//   mudanca fica isolada nos 2 pontos marcados "POLITICA DE ESCRITA" no
//   codigo abaixo (marca de dirty no hit de escrita, e a ausencia de
//   propagacao imediata para wb_req_o).
//
// -----------------------------------------------------------------------
// SUPOSICAO DE GRANULARIDADE DE ESCRITA (fora de escopo desta fase)
// -----------------------------------------------------------------------
//   Este projeto nao define, ate esta fase, um barramento de dados
//   byte-enderecavel nem mascara de bytes (wstrb) para o nivel inferior de
//   memoria -- cache_addr.v (Fase 1) ja trabalha com blocos inteiros
//   (wr_data_i/rd_data_o de BLK_B*8 bits) e este modulo segue o MESMO
//   padrao: wdata_i/rdata_o/fill_data_i sao sempre o BLOCO INTEIRO
//   (BLK_B*8 bits). Ou seja, uma "escrita" aqui substitui o bloco inteiro,
//   nao um byte/palavra dentro dele. Mascaramento de escrita em
//   granularidade menor que o bloco (necessario para um core RV32I real
//   com LB/SB/SW) fica EXPLICITAMENTE fora de escopo desta fase -- e um
//   ponto de integracao a revisitar nas fases de integracao com o core
//   (cortadas do escopo deste projeto, ver plano-cache.md).
//
// -----------------------------------------------------------------------
// SUPOSICAO DE MODELO DE MEMORIA (fora de escopo desta fase)
// -----------------------------------------------------------------------
//   Nao ha modelagem de latencia do nivel inferior de memoria (L2/DRAM)
//   aqui: fill_data_i deve estar disponivel e estavel no MESMO ciclo em
//   que o fill e consumido (equivalente a uma memoria ideal de 1 ciclo,
//   igual ao fill_data_i sendo apenas mais um sinal combinacional fornecido
//   por quem instanciar este modulo). O caminho de write-back
//   (wb_req_o/wb_addr_o/wb_data_o) e so um PULSO informativo de 1 ciclo;
//   o consumo real desse pulso por uma memoria/L2 com latencia fica para a
//   Fase 8 (measure_tb) se necessario.
// =============================================================================

module cache_datapath #(
    parameter ADDR_W = 8, // largura do endereco de memoria (bits)
    parameter BLK_B  = 4, // bytes por bloco/linha de cache
    parameter SETS   = 4, // numero de conjuntos (sets)
    parameter WAYS   = 2, // associatividade (vias por set) -- QUALQUER valor >=1

    // ---- larguras derivadas: NUNCA hardcoded, mesmo padrao/formula de
    //      cache_addr.v (nao reinstanciado aqui, ver DECISAO DE PROJETO #1
    //      no cabecalho, mas a formula e IDENTICA para manter os dois
    //      modulos sempre compativeis bit a bit ao trocar so os parameters).
    localparam OFFSET_W = $clog2(BLK_B),               // bits de offset dentro do bloco
    localparam INDEX_W  = $clog2(SETS),                // bits de indice do set
    localparam TAG_W    = ADDR_W - INDEX_W - OFFSET_W, // bits restantes = tag
    localparam WAY_W    = (WAYS > 1) ? $clog2(WAYS) : 1 // bits p/ selecionar a via
)(
    input  wire                   clk,
    input  wire                   rst,        // reset SINCRONO, ativo alto

    // ---- interface do processador / harness de medicao (Fase 8) -----------
    // CONTRATO DE req_i (mesmo rigor de documentacao dos contratos de pulso
    // de repl_srrip.v -- ver la vitim_req_i/hit_en_i, linhas ~199-219):
    //   req_i deve ser amostrado JUNTO com ready_o na MESMA borda de clk --
    //   convencao padrao de handshake valid/ready (ex.: AMBA): se
    //   req_i==1 E ready_o==1 nessa borda, a transacao e ACEITA naquela
    //   borda (equivalente a "valid && ready = transfer"). O integrador
    //   (Fase 8) e responsavel por, apos ver a transacao aceita, OU
    //   derrubar req_i (se nao houver proximo acesso pronto) OU trocar
    //   addr_i/we_i/wdata_i para a PROXIMA transacao antes da proxima
    //   borda -- exatamente como um master AMBA deve avancar/derrubar
    //   valid apos ver valid&&ready aceitos, nunca repetir o MESMO beat
    //   sem intencao.
    //
    //   O QUE ESTA IMPLEMENTACAO FAZ se o contrato for violado (documentado
    //   e TESTADO em tb/cache_datapath_tb.v, secao "req_i sustentado"):
    //   se req_i permanecer em 1 por VARIOS ciclos consecutivos com o
    //   MESMO endereco enquanto ready_o==1 (por ex. um HIT, que resolve em
    //   1 ciclo e mantem ready_o==1 no ciclo seguinte -- nunca ha um ciclo
    //   de "ocupado" observavel para o integrador se apoiar), CADA ciclo em
    //   que req_i==1 e amostrado em S_IDLE e tratado como uma NOVA
    //   transacao independente -- comportamento DETERMINISTICO (nunca 'x'
    //   ou UB), proporcional EXATAMENTE ao numero de ciclos em que req_i
    //   esteve alto (nem mais, nem menos), e testavel bit a bit. NAO existe
    //   protecao de hardware (guard) contra isso -- decisao deliberada,
    //   pela mesma razao que repl_srrip.v nao protege hit_en_i sustentado:
    //   um guard aqui contrariaria o proprio padrao valid/ready que o
    //   modulo implementa (back-to-back requests com req_i mantido em 1 e
    //   addr_i TROCADO a cada ciclo e uso LEGITIMO e esperado, ex.: um
    //   trace de enderecos do harness de medicao da Fase 8 apresentando 1
    //   endereco por ciclo; nao ha como o hardware distinguir "quero
    //   repetir esta transacao de proposito" de "esqueci de trocar
    //   addr_i/derrubar req_i" sem informacao adicional fora de escopo
    //   aqui). A responsabilidade de nao reemitir sem querer e do
    //   integrador, como em qualquer barramento valid/ready convencional.
    input  wire                   req_i,      // pulsar 1 ciclo p/ solicitar acesso (ver CONTRATO acima)
    input  wire                   we_i,       // 1=escrita, 0=leitura (qualificado por req_i)
    input  wire [ADDR_W-1:0]      addr_i,
    input  wire [BLK_B*8-1:0]     wdata_i,    // dado a escrever (bloco INTEIRO, ver nota de granularidade)
    output wire                   ready_o,    // 1 quando o datapath aceita um novo req_i (S_IDLE)

    output wire                   rdata_valid_o, // pulso 1 ciclo: rdata_o valido (so em leitura)
    output wire [BLK_B*8-1:0]     rdata_o,

    // ---- interface de substituicao PLUGAVEL (ver DECISAO DE PROJETO #2) ---
    // saidas consumidas pelo modulo de politica externo (repl_lru OU
    // repl_srrip/repl_brrip+psel_dueling, instanciados por fora, Fase 8):
    output wire                   hit_o,          // pulso 1 ciclo: hit nesta transacao
    output wire                   miss_o,         // pulso 1 ciclo: miss detectado (== pedido de via vitima)
    output wire                   fill_done_o,    // pulso 1 ciclo: fill concluido (nova via valida)
    output wire [INDEX_W-1:0]     access_index_o, // set da transacao corrente (valido com hit_o/miss_o/fill_done_o)
    output wire [WAY_W-1:0]       access_way_o,   // via envolvida (hit_way em hit_o; via preenchida em fill_done_o)

    // entradas vindas do modulo de politica externo (resposta ao miss_o):
    input  wire                   victim_valid_i, // 1 quando victim_way_i esta valido p/ consumo
    input  wire [WAY_W-1:0]       victim_way_i,

    // ---- interface com memoria/nivel inferior (ver nota de modelo de memoria) --
    input  wire [BLK_B*8-1:0]     fill_data_i,    // bloco vindo da memoria, amostrado no ciclo do fill

    // ---- write-back (consequencia da politica WRITE-BACK assumida acima) ---
    output wire                   wb_req_o,       // pulso 1 ciclo: via vitima estava suja, precisa write-back
    output wire [ADDR_W-1:0]      wb_addr_o,      // endereco reconstruido da linha evictada (tag antigo + index)
    output wire [BLK_B*8-1:0]     wb_data_o       // dado da linha evictada
);

    // -------------------------------------------------------------------
    // Storage por via/set: tag/valid/dirty/data, MESMO estilo de array
    // [via][set] e reset sincrono de cache_addr.v/repl_srrip.v (ver
    // DECISAO DE PROJETO #1 no cabecalho sobre por que este storage e
    // proprio deste modulo em vez de reaproveitar cache_addr.v).
    // -------------------------------------------------------------------
    reg [TAG_W-1:0]   tag_mem   [0:WAYS-1][0:SETS-1];
    reg               valid_mem [0:WAYS-1][0:SETS-1];
    reg               dirty_mem [0:WAYS-1][0:SETS-1];
    reg [BLK_B*8-1:0] data_mem  [0:WAYS-1][0:SETS-1];

    integer w_rst, s_rst; // indices de varredura do reset sincrono (sintetizavel: limites estaticos)

    // ---- decodificacao de endereco (combinacional) -------------------------
    // NOTA: OFFSET_W (bits de offset dentro do bloco, addr_i[OFFSET_W-1:0])
    // e DELIBERADAMENTE nao decodificado aqui (ao contrario de cache_addr.v,
    // que expoe offset_o para consumidores futuros/genericos). Este modulo
    // opera em granularidade de BLOCO INTEIRO (ver nota de "SUPOSICAO DE
    // GRANULARIDADE DE ESCRITA" no cabecalho) -- os bits de offset nunca
    // influenciam nenhuma decisao de hardware aqui (nem selecao de
    // via/set, nem endereco de write-back, que forca o offset reconstruido
    // para {OFFSET_W{1'b0}} propositalmente). Manter um wire offset_c
    // teria sido codigo morto (nunca lido em nenhum assign/sempre-block);
    // omiti-lo em vez de declarar e nunca usar.
    wire [INDEX_W-1:0]  index_c  = addr_i[OFFSET_W + INDEX_W - 1 : OFFSET_W];
    wire [TAG_W-1:0]    tag_c    = addr_i[ADDR_W-1 : OFFSET_W + INDEX_W];

    // ---- comparacao de tag PARALELA entre as WAYS vias do set enderecado ---
    // priority-encoder sintetizavel (mesmo idioma de repl_srrip.v/
    // repl_brrip.v para found_c/found_way_c): menor indice de via vence em
    // empate -- em uso normal so 1 via pode casar (tags/valid mutuamente
    // exclusivos por construcao), o priority-encode e so defesa em
    // profundidade.
    integer i;
    reg               hit_c;
    reg [WAY_W-1:0]   hit_way_c;
    always @(*) begin
        hit_c     = 1'b0;
        hit_way_c = {WAY_W{1'b0}};
        for (i = 0; i < WAYS; i = i + 1) begin
            if (!hit_c && valid_mem[i][index_c] && (tag_mem[i][index_c] == tag_c)) begin
                hit_c     = 1'b1;
                hit_way_c = i[WAY_W-1:0];
            end
        end
    end

    // -------------------------------------------------------------------
    // FSM de 2 estados: S_IDLE (aceita req_i, resolve hit/miss) e
    // S_WAIT_VICTIM (miss pendente, aguardando victim_valid_i do modulo de
    // politica plugado por fora -- pode ser 1 ciclo, para uma politica
    // combinacional como o LRU, ou N ciclos, para uma FSM de aging como o
    // RRIP; o datapath e agnostico a isso, so poll victim_valid_i a cada
    // ciclo enquanto espera).
    // -------------------------------------------------------------------
    localparam S_IDLE        = 1'b0,
               S_WAIT_VICTIM = 1'b1;

    reg state;

    // transacao de miss latched (precisa sobreviver aos N ciclos de espera
    // por victim_valid_i em S_WAIT_VICTIM):
    reg [INDEX_W-1:0]  pending_index_r;
    reg [TAG_W-1:0]    pending_tag_r;
    reg                pending_we_r;
    reg [BLK_B*8-1:0]  pending_wdata_r;

    // saidas registradas (pulsos de 1 ciclo + dados associados):
    reg                hit_r, miss_r, fill_done_r, rdata_valid_r, wb_req_r;
    reg [INDEX_W-1:0]  access_index_r;
    reg [WAY_W-1:0]    access_way_r;
    reg [BLK_B*8-1:0]  rdata_r;
    reg [ADDR_W-1:0]   wb_addr_r;
    reg [BLK_B*8-1:0]  wb_data_r;

    always @(posedge clk) begin
        if (rst) begin
            state           <= S_IDLE;
            pending_index_r <= {INDEX_W{1'b0}};
            pending_tag_r   <= {TAG_W{1'b0}};
            pending_we_r    <= 1'b0;
            pending_wdata_r <= {(BLK_B*8){1'b0}};

            hit_r          <= 1'b0;
            miss_r         <= 1'b0;
            fill_done_r    <= 1'b0;
            rdata_valid_r  <= 1'b0;
            wb_req_r       <= 1'b0;
            access_index_r <= {INDEX_W{1'b0}};
            access_way_r   <= {WAY_W{1'b0}};
            rdata_r        <= {(BLK_B*8){1'b0}};
            wb_addr_r      <= {ADDR_W{1'b0}};
            wb_data_r      <= {(BLK_B*8){1'b0}};

            for (w_rst = 0; w_rst < WAYS; w_rst = w_rst + 1) begin
                for (s_rst = 0; s_rst < SETS; s_rst = s_rst + 1) begin
                    valid_mem[w_rst][s_rst] <= 1'b0;
                    dirty_mem[w_rst][s_rst] <= 1'b0;
                    tag_mem[w_rst][s_rst]   <= {TAG_W{1'b0}};
                    data_mem[w_rst][s_rst]  <= {(BLK_B*8){1'b0}};
                end
            end
        end else begin
            // ---- limpa pulsos de 1 ciclo por padrao; os ramos abaixo -----
            //      podem sobrescrever com 1'b1 quando a acao correspondente
            //      acontece NESTE ciclo (ultima atribuicao em ordem
            //      procedural vence, idioma padrao de registrador de
            //      pulso -- mesmo efeito pratico do padrao usado em
            //      repl_srrip.v/repl_brrip.v para as saidas da FSM).
            hit_r         <= 1'b0;
            miss_r        <= 1'b0;
            fill_done_r   <= 1'b0;
            rdata_valid_r <= 1'b0;
            wb_req_r      <= 1'b0;

            case (state)
                // -----------------------------------------------------------
                S_IDLE: begin
                    if (req_i) begin
                        if (hit_c) begin
                            // ---- HIT --------------------------------------
                            // POLITICA DE ESCRITA (write-back): escrita em
                            // hit so atualiza a cache e marca dirty; NAO
                            // propaga para memoria agora (ver secao no
                            // cabecalho do modulo).
                            if (we_i) begin
                                data_mem[hit_way_c][index_c]  <= wdata_i;
                                dirty_mem[hit_way_c][index_c] <= 1'b1;
                            end
                            rdata_r       <= data_mem[hit_way_c][index_c];
                            rdata_valid_r <= ~we_i; // so leitura produz dado valido
                            hit_r          <= 1'b1;
                            access_index_r <= index_c;
                            access_way_r   <= hit_way_c;
                            // permanece em S_IDLE: hit resolve em 1 ciclo
                        end else begin
                            // ---- MISS: latch da transacao + pede via vitima
                            pending_index_r <= index_c;
                            pending_tag_r   <= tag_c;
                            pending_we_r    <= we_i;
                            pending_wdata_r <= wdata_i;
                            miss_r          <= 1'b1;
                            access_index_r  <= index_c;
                            state           <= S_WAIT_VICTIM;
                        end
                    end
                end

                // -----------------------------------------------------------
                S_WAIT_VICTIM: begin
                    if (victim_valid_i) begin
                        // ---- eviction: se a via vitima estava valida E
                        //      suja, precisa de write-back (consequencia da
                        //      politica WRITE-BACK assumida). Le os valores
                        //      PRE-atualizacao (nao-blocking preserva o
                        //      valor atual no lado direito, mesmo idioma
                        //      usado em repl_srrip.v para found_c).
                        if (valid_mem[victim_way_i][pending_index_r] &&
                            dirty_mem[victim_way_i][pending_index_r]) begin
                            wb_req_r  <= 1'b1;
                            wb_addr_r <= {tag_mem[victim_way_i][pending_index_r],
                                          pending_index_r,
                                          {OFFSET_W{1'b0}}};
                            wb_data_r <= data_mem[victim_way_i][pending_index_r];
                        end

                        // ---- fill: WRITE-ALLOCATE -- se a transacao
                        //      pendente era uma escrita, a linha ja nasce
                        //      escrita (e suja); senao, nasce com o bloco
                        //      buscado da memoria (limpa).
                        valid_mem[victim_way_i][pending_index_r] <= 1'b1;
                        tag_mem[victim_way_i][pending_index_r]   <= pending_tag_r;
                        data_mem[victim_way_i][pending_index_r]  <=
                            pending_we_r ? pending_wdata_r : fill_data_i;
                        dirty_mem[victim_way_i][pending_index_r] <= pending_we_r;

                        fill_done_r    <= 1'b1;
                        access_index_r <= pending_index_r;
                        access_way_r   <= victim_way_i;
                        rdata_r        <= pending_we_r ? pending_wdata_r : fill_data_i;
                        rdata_valid_r  <= ~pending_we_r; // so leitura produz dado valido

                        state <= S_IDLE;
                    end
                    // enquanto victim_valid_i==0, permanece em S_WAIT_VICTIM
                    // (nenhum novo req_i e aceito -- ver ready_o abaixo)
                end

                // NOTA: sem ramo `default`, DELIBERADAMENTE (diferente de
                // repl_srrip.v/repl_brrip.v, que tem 2'd3 nao usado dos 4
                // valores possiveis de um estado de 2 bits e por isso
                // precisam de um default de recuperacao). Aqui `state` e um
                // UNICO bit com EXATAMENTE 2 valores possiveis
                // (S_IDLE=1'b0, S_WAIT_VICTIM=1'b1), ambos ja cobertos
                // pelos ramos acima -- um `default` seria codigo morto
                // inalcancavel (nenhuma "terceira codificacao" existe para
                // um reg de 1 bit fora de reset), tanto em simulacao
                // (apos o reset sincrono zerar `state`) quanto em sintese.
            endcase
        end
    end

    // ---- saidas combinacionais (funcao dos registradores de pulso) --------
    assign ready_o        = (state == S_IDLE);
    assign hit_o           = hit_r;
    assign miss_o          = miss_r;
    assign fill_done_o     = fill_done_r;
    assign access_index_o  = access_index_r;
    assign access_way_o    = access_way_r;
    assign rdata_valid_o   = rdata_valid_r;
    assign rdata_o         = rdata_r;
    assign wb_req_o        = wb_req_r;
    assign wb_addr_o       = wb_addr_r;
    assign wb_data_o       = wb_data_r;

endmodule
