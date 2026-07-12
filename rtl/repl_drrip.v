// =============================================================================
// repl_drrip.v
// PI4 UNIPAMPA - simulador de cache RTL (Fase 8, PARTE 1 do plano de medicao)
//
// Responsabilidade deste modulo:
//   Implementar o DRRIP (Dynamic RRIP) COMPLETO de Jaleel et al., "High
//   Performance Cache Replacement Using Re-Reference Interval Prediction
//   (RRIP)", ISCA 2010, secao 4.2 -- set-dueling entre SRRIP e BRRIP com um
//   PSEL global arbitrando a politica dos sets "seguidores".
//
// -----------------------------------------------------------------------
// POR QUE ESTE MODULO EXISTE (em vez de so instanciar repl_srrip.v e
// repl_brrip.v lado a lado)
// -----------------------------------------------------------------------
//   repl_srrip.v e repl_brrip.v (Fases 3/4) sao IDENTICOS em tudo exceto a
//   politica de INSERCAO (fill): a busca de vitima com aging e o hit->0 sao
//   o MESMO algoritmo, operando sobre o MESMO tipo de storage
//   (rrpv_mem[via][set]). No DRRIP de verdade, um set "seguidor" muda de
//   politica de insercao AO LONGO DO TEMPO (conforme o MSB do PSEL), mas o
//   HISTORICO de RRPV daquele set (o que ja foi envelhecido, o que ja foi
//   hit) tem que ser CONTINUO atraves dessa troca -- nao pode existir 1
//   array rrpv_mem "quando o set esta sendo SRRIP" e outro array DIFERENTE
//   "quando o set esta sendo BRRIP", porque a troca no meio perderia todo o
//   estado acumulado (as vias que estavam quase para RRPV_MAX voltariam a
//   RRPV_MAX "de fabrica" no array novo, por exemplo). Por isso este modulo
//   usa 1 UNICO storage rrpv_mem[via][set] e 1 UNICA FSM de busca de
//   vitima/aging (copia estrutural fiel de repl_srrip.v -- ver la os
//   comentarios completos, nao repetidos aqui na integra), e so BIFURCA a
//   decisao no exato ponto em que ela realmente difere entre as 3 politicas
//   possiveis de um set (SDM-SRRIP / SDM-BRRIP / seguidor): o valor de
//   RRPV_INSERT escolhido no momento do FILL.
//
// -----------------------------------------------------------------------
// ESQUEMA DE MAPEAMENTO SET -> PAPEL (SDM-SRRIP / SDM-BRRIP / seguidor)
// -----------------------------------------------------------------------
//   Escolhido: "static set sampling" classico via bits BAIXOS do INDEX do
//   set (mesma familia de tecnica descrita na Fig. 10 do paper, "sets
//   selecionados por um padrao CONSTANTE de bits do indice" -- a variante
//   mais simples de implementar em hardware, sem necessidade de LFSR/
//   enderecamento dinamico). Parametro SDM_SEL_BITS escolhe QUANTOS bits
//   baixos do indice (index_i[SDM_SEL_BITS-1:0]) participam da decisao:
//
//     index[SDM_SEL_BITS-1:0] == {SDM_SEL_BITS{1'b0}}  -> papel SDM-SRRIP
//     index[SDM_SEL_BITS-1:0] == {SDM_SEL_BITS{1'b1}}  -> papel SDM-BRRIP
//     qualquer outro padrao                             -> papel SEGUIDOR
//
//   Cada lado (SDM-SRRIP, SDM-BRRIP) fica com EXATAMENTE 1/2^SDM_SEL_BITS
//   da cache (um unico padrao fixo de SDM_SEL_BITS bits, dentre os
//   2^SDM_SEL_BITS padroes possiveis). Os sets seguidores sao o restante:
//   1 - 2/2^SDM_SEL_BITS = (2^SDM_SEL_BITS - 2)/2^SDM_SEL_BITS da cache.
//
//   Default deste modulo: SDM_SEL_BITS=4 -> 1/16 de cada lado. Para as
//   configs de ENTREGA do Apendice B (L1 e L2, ambas SETS=64 -> INDEX_W=6):
//     SDM-SRRIP = sets cujo indice tem os 4 bits baixos = 0000
//                 -> indices 0,16,32,48   (4 sets, 4/64 = 1/16)
//     SDM-BRRIP = sets cujo indice tem os 4 bits baixos = 1111
//                 -> indices 15,31,47,63  (4 sets, 4/64 = 1/16)
//     SEGUIDORES = os 56 sets restantes (56/64 = 7/8 da cache real).
//   Fracao pequena o suficiente para amostrar sem desperdicar capacidade
//   util da cache (7/8 dos sets continuam livres para o working set real),
//   e grande o suficiente (4 sets por lado, nao so 1) para nao depender de
//   um unico set "sortudo/azarado" -- fidelidade a ideia central do paper
//   de amostrar VARIOS sets por SDM, nao so 1.
//
//   Escolha de "so os bits BAIXOS do indice" (em vez de bits altos ou
//   espalhados): bits baixos do indice tendem a variar MAIS rapido entre
//   acessos consecutivos de um padrao tipico (stride pequeno), o que
//   distribui os sets de amostragem de forma mais uniforme ao longo do
//   espaco de enderecos tipico de um programa (mesma razao pratica citada
//   informalmente na literatura de set-dueling); e e a implementacao MAIS
//   barata em hardware (um comparador de SDM_SEL_BITS bits contra 2
//   constantes fixas, sem nenhum hash).
//
//   GUARDA DE ELABORACAO: 1 <= SDM_SEL_BITS <= INDEX_W (ver bloco generate
//   abaixo). SDM_SEL_BITS==INDEX_W (usa TODOS os bits do indice) e um caso
//   LIMITE permitido, nao proibido -- necessario justamente para a config
//   de VALIDACAO do plano (SETS=4 -> INDEX_W=2): com SDM_SEL_BITS=2, o
//   padrao 00 vira o UNICO set SDM-SRRIP (indice 0) e o padrao 11 vira o
//   UNICO set SDM-BRRIP (indice 3), sobrando so 2 sets seguidores (indices
//   1,2) -- 1/4 da cache reservado para CADA lado, muito mais do que os
//   1/16 tipicos, e SEM redundancia de amostragem (1 unico set por SDM, nao
//   4). O proprio plano-cache.md ja documenta que "4 sets nao comportam
//   SDMs reais" (Fase 5) -- essa degenerescencia e ESPERADA e aceitavel
//   so para exercitar o MECANISMO de roteamento na config brinquedo, nunca
//   para tirar conclusao de hit-rate real dela. O testbench deste modulo
//   (tb/repl_drrip_tb.v) foca na config de ENTREGA (SETS=64), onde o
//   mapeamento faz sentido de verdade, como o enunciado desta fase pede.
//
// -----------------------------------------------------------------------
// ROTEAMENTO DE INSERCAO (fill) -- a UNICA bifurcacao de comportamento
// -----------------------------------------------------------------------
//   No momento de um fill_en_i, o PAPEL do set fill_index_i decide a regra:
//     papel SDM-SRRIP                              -> sempre RRPV_INSERT_MID
//     papel SDM-BRRIP                               -> throttle bimodal
//                                                       (RARO->MID, COMUM->FAR)
//     papel SEGUIDOR, follower_use_brrip_o==0        -> RRPV_INSERT_MID
//       (PSEL diz que BRRIP esta performando pior no seu SDM -> usa SRRIP)
//     papel SEGUIDOR, follower_use_brrip_o==1        -> throttle bimodal
//       (PSEL diz que SRRIP esta performando pior no seu SDM -> usa BRRIP)
//   follower_use_brrip_o vem DIRETO da instancia interna de psel_dueling.v
//   (nao reimplementado aqui) -- ver "INSTANCIA DE psel_dueling.v" abaixo.
//   A decisao usa o valor de follower_use_brrip_o CORRENTE NO CICLO DO
//   FILL (nao um valor latched no momento do miss original) -- fidelidade
//   literal ao enunciado da tarefa ("insere via regra que o PSEL disser que
//   esta vencendo NO MOMENTO do fill").
//
//   RRPV_INSERT_MID = RRPV_MAX-1 ("intervalo intermediario", o mesmo valor
//   que repl_srrip.v SEMPRE usa e que repl_brrip.v usa no caso RARO).
//   RRPV_INSERT_FAR = RRPV_MAX ("re-referencia distante", o valor que
//   repl_brrip.v usa no caso COMUM). Nomenclatura unificada aqui (em vez de
//   RRPV_INSERT/RRPV_INSERT_RARE/RRPV_INSERT_COMMON como nos 2 modulos
//   fonte) porque os MESMOS 2 valores agora servem a 2 papeis diferentes
//   (MID e usado tanto pelo SDM-SRRIP quanto pelo caso raro do SDM-BRRIP/
//   seguidor-BRRIP) -- ver mux combinacional fill_use_brrip_c/
//   fill_use_srrip_c mais abaixo no corpo do modulo.
//
// -----------------------------------------------------------------------
// CONTADOR DE THROTTLE BIMODAL: GLOBAL, mas conta so as INSERCOES
// GOVERNADAS por BRRIP (nao TODAS as insercoes da cache)
// -----------------------------------------------------------------------
//   Igual a repl_brrip.v, `throttle_ctr` e um UNICO contador free-running
//   compartilhado (nao 1 por set). Diferenca necessaria aqui: em
//   repl_brrip.v TODA insercao e BRRIP (o modulo so implementa essa
//   politica), entao "incrementa a cada fill_en_i" e "incrementa a cada
//   insercao BRRIP" sao a MESMA coisa. Aqui NEM toda insercao usa a regra
//   BRRIP (sets SDM-SRRIP e seguidores-SRRIP usam MID sempre, sem consultar
//   o throttle) -- se o contador avancasse a CADA fill_en_i (inclusive os
//   SRRIP), a proporcao RARO/COMUM dentro da POPULACAO que realmente usa
//   BRRIP deixaria de ser EXATA 1/2^BRRIP_THROTTLE_BITS (ficaria diluida
//   por eventos SRRIP intercalados, sem relacao com o mecanismo que o
//   throttle governa). Por isso `throttle_ctr` aqui avanca SOMENTE quando
//   fill_en_i pulsa E a decisao de insercao daquele fill for BRRIP (SDM-
//   BRRIP OU seguidor com follower_use_brrip_o==1 no momento) -- preserva a
//   MESMA garantia de proporcao EXATA (nao estatistica) que repl_brrip.v
//   documenta, agora restrita a "insercoes efetivamente regidas por BRRIP",
//   que e a generalizacao correta do mecanismo original para um cenario
//   onde SRRIP e BRRIP convivem no mesmo array.
//
// -----------------------------------------------------------------------
// INSTANCIA DE psel_dueling.v (nao reimplementado aqui)
// -----------------------------------------------------------------------
//   miss_srrip_i do PSEL e alimentado quando um victim_req_i e ACEITO
//   (state==S_IDLE, mesmo ciclo em que a FSM de busca sairia de IDLE) para
//   um set de papel SDM-SRRIP; miss_brrip_i, para um set de papel
//   SDM-BRRIP. "victim_req_i chegando" JA E o miss por definicao do
//   contrato de cache_datapath.v (miss_o pulsa exatamente quando um pedido
//   de via vitima e gerado, ver DECISAO DE PROJETO #2 la) -- nao ha
//   nenhuma classificacao adicional de hit/miss a fazer aqui, so rotear o
//   proprio pulso de pedido para o lado certo do PSEL conforme o papel do
//   set. Sets seguidores NAO alimentam nenhum dos dois (um miss num
//   seguidor nao e evidencia para nenhum dos 2 lados do duelo -- so os
//   SDMs dedicados votam, fidelidade ao paper).
//
// -----------------------------------------------------------------------
// PORTA EXTERNA: MESMO CONTRATO de repl_srrip.v/repl_brrip.v
// -----------------------------------------------------------------------
//   hit_en_i/hit_way_i/hit_index_i, fill_en_i/fill_way_i/fill_index_i,
//   victim_req_i/victim_index_i/victim_busy_o/victim_valid_o/victim_way_o,
//   rd_way_i/rd_index_i/rd_rrpv_o -- identico bit a bit, substituto
//   plugavel direto na interface de cache_datapath.v (ver DECISAO DE
//   PROJETO #2 la). Mesmo protocolo de pulso de 1 ciclo, mesma semantica de
//   victim_busy_o/victim_valid_o, mesmos comportamentos documentados para
//   violacao de contrato (herdados por construcao, mesma FSM). Portas
//   ADICIONAIS de debug (psel_o, follower_use_brrip_o, rd_is_sdm_srrip_o,
//   rd_is_sdm_brrip_o) sao OPCIONAIS do ponto de vista do integrador --
//   cache_datapath.v nao as usa nem precisa conecta-las; existem so para o
//   testbench conseguir provar o roteamento SDM/PSEL sem depender de
//   referencia hierarquica a sinais internos.
//
// -----------------------------------------------------------------------
// PROTECAO DE RACE HIT-vs-AGING e GUARDA RRPV_BITS>=1: REUSADAS, nao
// reimplementadas
// -----------------------------------------------------------------------
//   A mascara hit_targets_cur_set_c (evita cravar como vitima uma via que
//   esta "renascendo" por hit na mesma borda) e a guarda de elaboracao
//   RRPV_BITS>=1 sao EXATAMENTE as mesmas de repl_srrip.v/repl_brrip.v --
//   ver os comentarios completos la (NOTA DE RACE HIT-vs-AGING em
//   repl_srrip.v). Aplicam-se aqui identicamente porque a FSM de busca e a
//   mesma, so operando sobre 1 unico array compartilhado por todos os
//   papeis em vez de 1 array por politica.
// =============================================================================

module repl_drrip #(
    // ---- config da cache (default = config de ENTREGA do Apendice B, L1:
    //      4KB/32B bloco/2-way/64 sets -- DIFERENTE do default SETS=4 de
    //      repl_srrip.v/repl_brrip.v de proposito: o mapeamento SDM deste
    //      modulo so faz sentido de verdade na escala real, ver cabecalho).
    parameter SETS      = 64,
    parameter WAYS      = 2,
    parameter RRPV_BITS = 2,

    // periodo do throttle bimodal = 2^BRRIP_THROTTLE_BITS insercoes
    // BRRIP-governadas (ver nota no cabecalho sobre a populacao contada).
    // Default=5 -> 1/32, fidelidade ao paper, mesmo default de fabrica de
    // repl_brrip.v.
    parameter BRRIP_THROTTLE_BITS = 5,

    // largura do PSEL interno (repassada para a instancia de
    // psel_dueling.v). Default=10, fidelidade ao paper, mesmo default de
    // fabrica de psel_dueling.v.
    parameter PSEL_BITS = 10,

    // numero de bits BAIXOS do indice do set usados no mapeamento SDM (ver
    // "ESQUEMA DE MAPEAMENTO" no cabecalho). Default=4 -> 1/16 de cada lado
    // para SETS=64 (configs do Apendice B). DEVE satisfazer
    // 1 <= SDM_SEL_BITS <= INDEX_W (ver guarda de elaboracao abaixo).
    parameter SDM_SEL_BITS = 4,

    // ---- larguras/derivados: mesmo padrao de repl_srrip.v/repl_brrip.v,
    //      nunca hardcoded. -------------------------------------------------
    localparam INDEX_W  = $clog2(SETS),
    localparam WAY_W    = (WAYS > 1) ? $clog2(WAYS) : 1,

    localparam [RRPV_BITS-1:0] RRPV_MAX        = {RRPV_BITS{1'b1}},
    localparam [RRPV_BITS-1:0] RRPV_INSERT_MID = RRPV_MAX - {{(RRPV_BITS-1){1'b0}}, 1'b1}, // RRPV_MAX-1
    localparam [RRPV_BITS-1:0] RRPV_INSERT_FAR = RRPV_MAX                                  // RRPV_MAX
)(
    input  wire                  clk,
    input  wire                  rst,        // reset SINCRONO, ativo alto

    // ---- HIT (sincrono): identico a repl_srrip.v/repl_brrip.v -------------
    input  wire                  hit_en_i,
    input  wire [WAY_W-1:0]      hit_way_i,
    input  wire [INDEX_W-1:0]    hit_index_i,

    // ---- FILL (sincrono): valor de insercao decidido pelo PAPEL do set
    //      fill_index_i (ver "ROTEAMENTO DE INSERCAO" no cabecalho) --------
    input  wire                  fill_en_i,
    input  wire [WAY_W-1:0]      fill_way_i,
    input  wire [INDEX_W-1:0]    fill_index_i,

    // ---- busca de vitima (handshake multi-ciclo, protocolo IDENTICO a
    //      repl_srrip.v/repl_brrip.v -- victim_req_i tambem e o proprio
    //      evento de "miss" consumido pelo PSEL interno, ver cabecalho) ----
    input  wire                  victim_req_i,
    input  wire [INDEX_W-1:0]    victim_index_i,
    output wire                  victim_busy_o,
    output wire                  victim_valid_o,
    output wire [WAY_W-1:0]      victim_way_o,

    // ---- consulta combinacional do RRPV cru de uma via (debug/verificacao) --
    input  wire [WAY_W-1:0]      rd_way_i,
    input  wire [INDEX_W-1:0]    rd_index_i,
    output wire [RRPV_BITS-1:0]  rd_rrpv_o,

    // ---- saidas de debug ADICIONAIS (opcionais para o integrador, ver
    //      cabecalho -- uteis para o testbench provar o roteamento SDM/PSEL
    //      sem depender de referencia hierarquica) ---------------------------
    output wire [PSEL_BITS-1:0]  psel_o,               // passthrough do PSEL interno
    output wire                  follower_use_brrip_o,  // passthrough do PSEL interno
    output wire                  rd_is_sdm_srrip_o,     // papel de rd_index_i: SDM-SRRIP?
    output wire                  rd_is_sdm_brrip_o      // papel de rd_index_i: SDM-BRRIP?
);

    // -------------------------------------------------------------------
    // Guardas de elaboracao (mesma tecnica comprovada em repl_srrip.v/
    // repl_brrip.v/psel_dueling.v: instanciar um modulo com nome
    // proposital inexistente dentro de generate/if, forcando erro fatal de
    // resolucao). PSEL_BITS<2 NAO precisa de guarda propria aqui -- a
    // instancia de psel_dueling.v abaixo ja falha por conta propria nessa
    // config (guarda dela mesma), ver o comentario "NOTA DE PRECISAO" no
    // cabecalho de psel_dueling.v.
    // -------------------------------------------------------------------
    generate
        if (RRPV_BITS < 1) begin : g_assert_rrpv_bits_ge_1
            repl_drrip_requires_rrpv_bits_ge_1_do_not_instantiate_with_other_config u_rrpv_bits_guard ();
        end
    endgenerate

    generate
        if (BRRIP_THROTTLE_BITS < 1) begin : g_assert_throttle_bits_ge_1
            repl_drrip_requires_throttle_bits_ge_1_do_not_instantiate_with_other_config u_throttle_bits_guard ();
        end
    endgenerate

    generate
        if (SDM_SEL_BITS < 1) begin : g_assert_sdm_sel_bits_ge_1
            repl_drrip_requires_sdm_sel_bits_ge_1_do_not_instantiate_with_other_config u_sdm_sel_bits_guard_lo ();
        end
    endgenerate

    generate
        if (SDM_SEL_BITS > INDEX_W) begin : g_assert_sdm_sel_bits_le_index_w
            repl_drrip_requires_sdm_sel_bits_le_index_w_do_not_instantiate_with_other_config u_sdm_sel_bits_guard_hi ();
        end
    endgenerate

    // -------------------------------------------------------------------
    // Storage UNICO: 1 contador RRPV_BITS-wide por via/set, compartilhado
    // por TODOS os papeis (SDM-SRRIP, SDM-BRRIP, seguidor) -- ver "POR QUE
    // ESTE MODULO EXISTE" no cabecalho. Reset sincrono inicializa TODAS as
    // vias/sets em RRPV_MAX, mesma justificativa de repl_srrip.v/
    // repl_brrip.v.
    // -------------------------------------------------------------------
    reg [RRPV_BITS-1:0] rrpv_mem [0:WAYS-1][0:SETS-1];

    integer w_rst, s_rst; // indices de varredura do reset sincrono (estaticos -> sintetizavel)

    // -------------------------------------------------------------------
    // Contador GLOBAL de throttle bimodal -- avanca SOMENTE em insercoes
    // BRRIP-governadas (ver "CONTADOR DE THROTTLE BIMODAL" no cabecalho).
    // -------------------------------------------------------------------
    reg [BRRIP_THROTTLE_BITS-1:0] throttle_ctr;
    wire throttle_rare_c = (throttle_ctr == {BRRIP_THROTTLE_BITS{1'b0}});

    // -------------------------------------------------------------------
    // Mapeamento SET -> PAPEL (combinacional, ver "ESQUEMA DE MAPEAMENTO"
    // no cabecalho). Calculado separadamente para os 3 indices que este
    // modulo precisa classificar em paralelo no mesmo ciclo (fill, o
    // proprio pedido de vitima/miss para o PSEL, e a consulta de debug) --
    // TODOS usam a MESMA regra de comparacao contra os 2 padroes fixos.
    // -------------------------------------------------------------------
    wire [SDM_SEL_BITS-1:0] fill_sdm_sel_c   = fill_index_i[SDM_SEL_BITS-1:0];
    wire [SDM_SEL_BITS-1:0] victim_sdm_sel_c = victim_index_i[SDM_SEL_BITS-1:0];
    wire [SDM_SEL_BITS-1:0] rd_sdm_sel_c     = rd_index_i[SDM_SEL_BITS-1:0];

    wire fill_is_sdm_srrip_c   = (fill_sdm_sel_c   == {SDM_SEL_BITS{1'b0}});
    wire fill_is_sdm_brrip_c   = (fill_sdm_sel_c   == {SDM_SEL_BITS{1'b1}});
    wire fill_is_follower_c    = !fill_is_sdm_srrip_c && !fill_is_sdm_brrip_c;

    wire victim_is_sdm_srrip_c = (victim_sdm_sel_c == {SDM_SEL_BITS{1'b0}});
    wire victim_is_sdm_brrip_c = (victim_sdm_sel_c == {SDM_SEL_BITS{1'b1}});

    assign rd_is_sdm_srrip_o = (rd_sdm_sel_c == {SDM_SEL_BITS{1'b0}});
    assign rd_is_sdm_brrip_o = (rd_sdm_sel_c == {SDM_SEL_BITS{1'b1}});

    // -------------------------------------------------------------------
    // FSM de busca de vitima: 3 estados, ESTRUTURALMENTE IDENTICA a
    // repl_srrip.v/repl_brrip.v (S_IDLE/S_AGE/S_FOUND) -- ver comentario
    // completo em repl_srrip.v, nao repetido aqui na integra. Opera sobre
    // o UNICO rrpv_mem compartilhado, agnostica ao papel do set (o papel
    // so importa para o FILL, nunca para a busca/aging/hit). Declarada
    // ANTES da instancia de psel_dueling.v abaixo porque victim_accept_c
    // (o pulso de "miss" consumido pelo PSEL) precisa referenciar `state`.
    // -------------------------------------------------------------------
    localparam [1:0] S_IDLE  = 2'd0,
                      S_AGE   = 2'd1,
                      S_FOUND = 2'd2;

    reg [1:0]         state;
    reg [INDEX_W-1:0]  search_idx_reg; // set sob busca (latched ao entrar em S_AGE/S_FOUND)
    reg [WAY_W-1:0]    victim_way_reg; // via vitima encontrada (latched em S_FOUND)

    wire [INDEX_W-1:0] cur_search_idx = (state == S_IDLE) ? victim_index_i : search_idx_reg;

    // ---- mascara "hit vai zerar esta via NESTA MESMA borda" -----------------
    // Ver "NOTA DE RACE HIT-vs-AGING" em repl_srrip.v -- reusada IDENTICA.
    wire hit_targets_cur_set_c = hit_en_i && (hit_index_i == cur_search_idx);

    // ---- busca combinacional por via com RRPV==RRPV_MAX no set corrente ----
    integer k;
    reg                  found_c;
    reg [WAY_W-1:0]      found_way_c;
    always @(*) begin
        found_c     = 1'b0;
        found_way_c = {WAY_W{1'b0}};
        for (k = 0; k < WAYS; k = k + 1) begin
            if (!found_c && (rrpv_mem[k][cur_search_idx] == RRPV_MAX) &&
                !(hit_targets_cur_set_c && (hit_way_i == k[WAY_W-1:0]))) begin
                found_c     = 1'b1;
                found_way_c = k[WAY_W-1:0];
            end
        end
    end

    // -------------------------------------------------------------------
    // Instancia de psel_dueling.v (Fase 5, NAO reimplementado aqui). O
    // "miss" de cada lado do duelo e o proprio victim_req_i ACEITO
    // (state==S_IDLE neste ciclo) para um set do papel correspondente --
    // ver "INSTANCIA DE psel_dueling.v" no cabecalho.
    // -------------------------------------------------------------------
    wire victim_accept_c   = victim_req_i && (state == S_IDLE);
    wire psel_miss_srrip_c = victim_accept_c && victim_is_sdm_srrip_c;
    wire psel_miss_brrip_c = victim_accept_c && victim_is_sdm_brrip_c;

    psel_dueling #(
        .PSEL_BITS (PSEL_BITS)
    ) u_psel (
        .clk                  (clk),
        .rst                  (rst),
        .miss_srrip_i         (psel_miss_srrip_c),
        .miss_brrip_i         (psel_miss_brrip_c),
        .follower_use_brrip_o (follower_use_brrip_o),
        .psel_o               (psel_o)
    );

    // -------------------------------------------------------------------
    // Decisao de insercao (fill): papel do set + (se seguidor) o PSEL
    // corrente decidem se este fill usa a regra SRRIP (sempre MID) ou a
    // regra BRRIP (throttle bimodal MID/FAR) -- ver "ROTEAMENTO DE
    // INSERCAO" no cabecalho. Mutuamente exclusivas e exaustivas por
    // construcao (fill_is_sdm_srrip_c/fill_is_sdm_brrip_c nunca sao 1 ao
    // mesmo tempo, ja que os 2 padroes de comparacao sao diferentes para
    // SDM_SEL_BITS>=1, garantido pela guarda de elaboracao acima).
    // -------------------------------------------------------------------
    wire fill_use_brrip_c = fill_is_sdm_brrip_c ||
                             (fill_is_follower_c && follower_use_brrip_o);
    wire fill_use_srrip_c = fill_is_sdm_srrip_c ||
                             (fill_is_follower_c && !follower_use_brrip_o);

    // ---- FSM + storage + throttle: um unico always sincrono, mesma ordem
    //      de prioridade de repl_srrip.v/repl_brrip.v: (1) reset,
    //      (2) transicoes da FSM de busca + aging, (3) fill_en_i/hit_en_i
    //      (aplicados por ultimo -- hit tem prioridade sobre fill/aging se
    //      coincidirem na mesma via/set, corner case fora do fluxo normal,
    //      documentado por completude identica a repl_srrip.v).
    // -------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state          <= S_IDLE;
            search_idx_reg <= {INDEX_W{1'b0}};
            victim_way_reg <= {WAY_W{1'b0}};
            throttle_ctr   <= {BRRIP_THROTTLE_BITS{1'b0}};
            for (w_rst = 0; w_rst < WAYS; w_rst = w_rst + 1) begin
                for (s_rst = 0; s_rst < SETS; s_rst = s_rst + 1) begin
                    rrpv_mem[w_rst][s_rst] <= RRPV_MAX;
                end
            end
        end else begin
            case (state)
                // -------------------------------------------------------
                S_IDLE: begin
                    if (victim_req_i) begin
                        search_idx_reg <= victim_index_i;
                        if (found_c) begin
                            victim_way_reg <= found_way_c;
                            state          <= S_FOUND;
                        end else begin
                            state <= S_AGE;
                        end
                    end
                end

                // -------------------------------------------------------
                S_AGE: begin
                    if (found_c) begin
                        victim_way_reg <= found_way_c;
                        state          <= S_FOUND;
                    end else begin
                        for (k = 0; k < WAYS; k = k + 1) begin
                            rrpv_mem[k][search_idx_reg] <=
                                (rrpv_mem[k][search_idx_reg] == RRPV_MAX) ?
                                RRPV_MAX : (rrpv_mem[k][search_idx_reg] + 1'b1);
                        end
                        // permanece em S_AGE (sem atribuicao explicita a 'state')
                    end
                end

                // -------------------------------------------------------
                S_FOUND: begin
                    state <= S_IDLE;
                end

                default: state <= S_IDLE; // estado invalido (nao alcancavel) -> recupera p/ IDLE
            endcase

            // ---- FILL: roteado por papel do set (ver fill_use_brrip_c/
            //      fill_use_srrip_c acima) -----------------------------
            if (fill_en_i) begin
                if (fill_use_brrip_c) begin
                    rrpv_mem[fill_way_i][fill_index_i] <=
                        throttle_rare_c ? RRPV_INSERT_MID : RRPV_INSERT_FAR;
                    throttle_ctr <= throttle_ctr + 1'b1; // so avanca em insercoes BRRIP-governadas
                end else begin // fill_use_srrip_c (mutuamente exclusivo e exaustivo)
                    rrpv_mem[fill_way_i][fill_index_i] <= RRPV_INSERT_MID;
                end
            end

            // ---- HIT: identico a repl_srrip.v/repl_brrip.v, agnostico a papel --
            if (hit_en_i) begin
                rrpv_mem[hit_way_i][hit_index_i] <= {RRPV_BITS{1'b0}};
            end
        end
    end

    // ---- saidas da busca de vitima (combinacionais, funcao do estado) ------
    assign victim_busy_o  = (state != S_IDLE);
    assign victim_valid_o = (state == S_FOUND);
    assign victim_way_o   = victim_way_reg;

    // ---- consulta combinacional de debug do RRPV cru de uma via ------------
    assign rd_rrpv_o = rrpv_mem[rd_way_i][rd_index_i];

endmodule
