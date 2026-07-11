// =============================================================================
// repl_brrip.v
// PI4 UNIPAMPA - simulador de cache RTL (Fase 4 do plano de validacao)
//
// Responsabilidade deste modulo:
//   Implementar o Bimodal RRIP (BRRIP) de Jaleel et al., "High Performance
//   Cache Replacement Using Re-Reference Interval Prediction (RRIP)",
//   ISCA 2010 (secao 3/4, "Bimodal Insertion Policy" aplicada ao RRIP).
//   BRRIP compartilha com o SRRIP (ver repl_srrip.v) TUDO exceto a
//   politica de INSERCAO -- por isso este modulo reusa, DELIBERADAMENTE e
//   ao maximo, a estrutura, nomenclatura e FSM de repl_srrip.v (mesmo
//   contador RRPV por via, mesma FSM de busca de vitima com aging, mesmo
//   hit->RRPV=0, mesmo despejo buscando RRPV_MAX com aging incrementando
//   todas as vias do set quando nao acha). A UNICA diferenca semantica
//   esta descrita abaixo.
//
//   Cada via de cada set tem um contador RRPV (Re-Reference Prediction
//   Value) de RRPV_BITS bits:
//     RRPV = 0            -> "re-referencia imediata" (linha quente, hit).
//     RRPV = RRPV_MAX-1    -> "intervalo intermediario" (valor de insercao
//                             "raro" do BRRIP -- ver throttle abaixo).
//     RRPV = RRPV_MAX      -> "re-referencia distante" (valor de insercao
//                             "comum" do BRRIP -- ver throttle abaixo -- e
//                             tambem a condicao de candidata a vitima).
//
// -----------------------------------------------------------------------
// DIFERENCA CHAVE vs SRRIP (a UNICA): a politica de INSERCAO (fill)
// -----------------------------------------------------------------------
//   SRRIP (repl_srrip.v) SEMPRE insere no intervalo intermediario
//   (RRPV = RRPV_MAX-1), para toda e qualquer linha preenchida.
//
//   BRRIP insere na GRANDE MAIORIA das vezes com RRPV = RRPV_MAX
//   ("re-referencia distante", quase sempre -- e isso que da ao BRRIP sua
//   resistencia extra a scans/thrashing: a linha nova comeca "quase morta",
//   entao um padrao de acesso que so passa 1x por cada linha -- scan --
//   nunca acumula prioridade sobre as linhas uteis do working set) e, com
//   RARIDADE (throttle bimodal, tipicamente 1/32 no paper original de
//   Jaleel et al., parametrizavel aqui via BRRIP_THROTTLE_BITS), insere no
//   MESMO valor intermediario que o SRRIP sempre usa (RRPV = RRPV_MAX-1).
//   Esse comportamento "e quase sempre BIP" (Bimodal Insertion Policy,
//   Qureshi et al. 2007, adaptada ao dominio RRIP pelo paper de RRIP) e o
//   que separa BRRIP de SRRIP: SRRIP sozinho e vulneravel a padroes de
//   acesso ciclicos maiores que a cache (thrashing), porque toda insercao
//   "empurra" a fila de despejo igualmente; BRRIP, ao raramente conceder o
//   intervalo intermediario, preserva uma fracao pequena do working set
//   mesmo sob thrashing -- e essa fracao e o suficiente, empiricamente
//   (Fig. 8 do paper), pra recuperar a maior parte do desempenho perdido
//   pelo SRRIP em cargas de trabalho que thrasham.
//
//   Em TODO o resto (hit->0, busca de vitima, aging, contrato de pulso das
//   portas, guarda de elaboracao, mascara de race hit-vs-aging) este
//   modulo e uma copia estrutural fiel de repl_srrip.v -- ver as notas
//   completas la; aqui repetimos so o essencial + o que muda.
//
// -----------------------------------------------------------------------
// MECANISMO DE THROTTLE BIMODAL ESCOLHIDO (sintetizavel, deterministico)
// -----------------------------------------------------------------------
//   Descartados por serem constructs de SIMULACAO (proibidos no DUT):
//   $random, $urandom -- nao sintetizaveis, nao pertencem a um modulo RTL.
//
//   Escolhido: um CONTADOR LIVRE (free-running) de BRRIP_THROTTLE_BITS
//   bits, `throttle_ctr`, que incrementa em 1 (com wraparound natural por
//   largura fixa, sem logica extra) a cada FILL efetivado (pulso de
//   fill_en_i), e NAO a cada ciclo de clock. Por que "a cada fill" e nao
//   "a cada ciclo": o enunciado do throttle bimodal e sobre a PROPORCAO
//   de INSERCOES (1 em cada 2^BRRIP_THROTTLE_BITS insercoes usa o valor
//   raro) -- amarrando o contador ao proprio evento que ele governa, essa
//   proporcao fica EXATA e trivial de calcular na mao (nao "seria
//   aproximadamente"), em vez de depender da distribuicao temporal dos
//   fills em relacao a um contador de ciclos independente. E o mecanismo
//   "contador free-running comparado contra um threshold" sugerido no
//   enunciado da tarefa, especializado para contar o proprio evento de
//   interesse.
//
//   Regra de decisao (combinacional, avaliada no MESMO ciclo do fill,
//   usando o valor CORRENTE -- pre-incremento -- de throttle_ctr):
//     throttle_ctr == 0  -> RARO  -> insere em RRPV_INSERT_RARE (=RRPV_MAX-1)
//     throttle_ctr != 0  -> COMUM -> insere em RRPV_INSERT_COMMON (=RRPV_MAX)
//   Apos a decisao, throttle_ctr incrementa (saturando por wraparound de
//   largura fixa: 2^BRRIP_THROTTLE_BITS - 1 + 1 -> 0). Resultado: dentro
//   de qualquer janela de 2^BRRIP_THROTTLE_BITS fills CONSECUTIVOS
//   (alinhada ao ponto em que throttle_ctr passou por 0 pela ultima vez),
//   EXATAMENTE 1 fill usa o valor raro e os demais 2^BRRIP_THROTTLE_BITS-1
//   usam o valor comum -- proporcao 1/2^BRRIP_THROTTLE_BITS EXATA, nao
//   estatistica, e 100% reproduzivel a partir do reset (ver nota de reset
//   determinismo abaixo).
//
//   `throttle_ctr` e GLOBAL ao modulo (1 unico contador compartilhado por
//   TODOS os sets/vias, nao 1 por set) -- fiel ao mecanismo do paper
//   (BIP/DRRIP usam um unico gerador pseudo-aleatorio/contador por
//   estrutura de cache, nao por set), e tambem a escolha mais barata em
//   hardware (1 contador em vez de SETS contadores).
//
//   Taxa DEFAULT do parametro (BRRIP_THROTTLE_BITS, valor de fabrica do
//   modulo): 5 bits -> 1/32, fidelidade direta ao paper (Jaleel et al.,
//   ISCA 2010, secao 4.1, "epsilon = 1/32" usado nos experimentos do
//   BRRIP). Quem instanciar este modulo sem sobrescrever o parametro herda
//   essa taxa "de fabrica" fiel ao paper.
//
//   Taxa usada na CONFIG DE VALIDACAO deste testbench (tb/repl_brrip_tb.v):
//   BRRIP_THROTTLE_BITS=2 -> 1/4, DELIBERADAMENTE menor que o default de
//   fabrica (5 bits/1/32). Motivo: com 1/32 seriam necessarios 32 fills
//   consecutivos so pra observar 1 unica ocorrencia do caso raro -- viavel
//   em hardware real, mas infla o testbench sem agregar cobertura (o
//   mecanismo -- contador free-running comparado a zero -- e IDENTICO
//   independente da largura; only o periodo muda). Reduzir para 2 bits
//   (periodo 4) mantem a sequencia de fills pequena e 100% rastreavel na
//   mao (raro nos fills 1,5,9,... quando contado a partir de 1), exercitando
//   o wraparound completo do contador em poucas linhas de teste, sem abrir
//   mao de nenhuma garantia estrutural (mesmo hardware, parametro diferente).
//
// -----------------------------------------------------------------------
// NOTA: insercao "comum" (RRPV_MAX) e imediatamente re-elegivel a vitima
// -----------------------------------------------------------------------
//   Diferenca de comportamento observavel vs SRRIP (consequencia direta,
//   nao um bug): no SRRIP, TODA linha recem-preenchida entra no intervalo
//   intermediario (RRPV_MAX-1) e portanto tem, no minimo, 1 rodada de
//   "graca" antes de poder ser escolhida vitima de novo (precisa de pelo
//   menos 1 aging para alcancar RRPV_MAX). No BRRIP, quando o throttle
//   escolhe o caso COMUM (a grande maioria das insercoes), a linha entra
//   DIRETO em RRPV_MAX -- ou seja, se o integrador pedir uma nova busca de
//   vitima no MESMO set imediatamente apos esse fill, essa MESMA via pode
//   ser encontrada como vitima de novo, sem NENHUMA rodada de aging. Isso
//   e o proprio mecanismo do BRRIP funcionando como projetado (linhas
//   inseridas no caso comum nao ganham prioridade nenhuma sobre a fila de
//   despejo -- e essa auseencia de prioridade que da a resistencia a
//   scans/thrashing). Testado explicitamente em tb/repl_brrip_tb.v (secao
//   "despejo direto set2" + re-busca imediata).
//
// -----------------------------------------------------------------------
// NOTA DE GENERALIZACAO, NOTA DE NOMENCLATURA, CONTRATOS DE PULSO
// (hit_en_i/fill_en_i/victim_req_i) E NOTA DE RACE HIT-vs-AGING: idênticas
// a repl_srrip.v (mesma FSM, mesmas portas, mesma mascara de protecao) --
// ver os comentarios completos em rtl/repl_srrip.v, nao repetidos aqui na
// integra para evitar duplicacao/desalinhamento futuro entre os dois
// arquivos. Resumo do que se aplica IGUALMENTE aqui:
//   - WAYS pode ser QUALQUER valor >=1 (contador RRPV por via, sem limite
//     estrutural de associatividade).
//   - hit_en_i/fill_en_i sao portas SINCRONAS separadas (hit->0,
//     fill->valor de insercao definido pelo throttle); rd_way_i/rd_index_i/
//     rd_rrpv_o e consulta COMBINACIONAL de debug.
//   - victim_req_i/victim_busy_o/victim_valid_o/victim_way_o seguem o MESMO
//     protocolo multi-ciclo (pulso de 1 ciclo com FSM em IDLE; violacoes do
//     contrato de pulso tem o MESMO comportamento documentado/testado em
//     repl_srrip.v, incluindo o caso extremo WAYS==1 com hit_en_i sustentado
//     -- ver abaixo).
//   - A mascara hit_targets_cur_set_c que exclui, da busca combinacional de
//     candidatas a RRPV_MAX, qualquer via que hit_en_i esteja mirando no
//     MESMO ciclo/set sob avaliacao -- protecao IDENTICA a de repl_srrip.v,
//     reusada aqui linha a linha (mesma race, mesma causa raiz: a FSM
//     decide found_c usando valores PRE-borda, que podem estar
//     "desatualizados" por um hit concorrente na mesma borda). Testada
//     explicitamente em tb/repl_brrip_tb.v (secao "RACE hit-vs-aging"),
//     cenarios analogos aos de repl_srrip_tb.v.
//
//   CASO EXTREMO NAO PROTEGIDO (herdado de repl_srrip.v, mesma causa raiz):
//   se hit_en_i for mantido em nivel alto por VARIOS ciclos consecutivos
//   (violando o contrato de pulso de 1 ciclo) mirando a UNICA via de um set
//   com WAYS==1 enquanto esse set esta em S_AGE, a FSM fica PRESA
//   indefinidamente em S_AGE (found_c nunca fica 1 enquanto a unica via
//   permanecer mascarada) -- mesma limitacao de repl_srrip.v, mesma
//   justificativa de nao ter protecao de hardware dedicada (fora do uso
//   real deste projeto, que usa WAYS=2). Quem reusar este modulo com
//   WAYS==1 deve estar ciente disso.
// =============================================================================

module repl_brrip #(
    parameter SETS      = 4, // numero de conjuntos (sets)
    parameter WAYS      = 2, // associatividade (vias por set) -- QUALQUER valor >=1
    // largura do contador RRPV (RRPV_MAX = 2^RRPV_BITS - 1). Mesma nota de
    // degenerescencia de repl_srrip.v: RRPV_BITS==1 e aceito pelo guard
    // abaixo mas colapsa RRPV_INSERT_RARE(=RRPV_MAX-1=0) para o MESMO valor
    // do hit (0) -- o caso raro do throttle deixa de ser distinguivel de um
    // hit; o caso comum (RRPV_MAX=1) continua distinguivel. Nao proibido,
    // mas quem usar RRPV_BITS=1 deve estar ciente da perda de fidelidade ao
    // "intervalo intermediario" do paper.
    parameter RRPV_BITS = 2,

    // largura do contador de throttle bimodal (periodo = 2^BRRIP_THROTTLE_BITS
    // fills; 1 fill em cada periodo usa RRPV_INSERT_RARE, os demais usam
    // RRPV_INSERT_COMMON). Default=5 -> 1/32, fidelidade ao paper (Jaleel et
    // al., ISCA 2010). Ver nota de mecanismo no cabecalho para a taxa
    // efetivamente usada na config de validacao deste projeto (2 bits, 1/4).
    parameter BRRIP_THROTTLE_BITS = 5,

    // ---- larguras/derivados: mesmo padrao de repl_srrip.v, nunca
    //      hardcoded, calculados a partir dos parameters. -------------------
    localparam INDEX_W  = $clog2(SETS),                  // bits de indice do set
    localparam WAY_W    = (WAYS > 1) ? $clog2(WAYS) : 1,  // bits p/ selecionar a via

    // RRPV_MAX = todos os bits em 1 (maior valor representavel em RRPV_BITS
    // bits) = "re-referencia distante" = valor de insercao COMUM do BRRIP.
    // RRPV_INSERT_RARE = RRPV_MAX-1 = "intervalo intermediario" = valor de
    // insercao RARO do BRRIP (mesmo valor que o SRRIP usa SEMPRE).
    localparam [RRPV_BITS-1:0] RRPV_MAX            = {RRPV_BITS{1'b1}},
    localparam [RRPV_BITS-1:0] RRPV_INSERT_RARE    = RRPV_MAX - {{(RRPV_BITS-1){1'b0}}, 1'b1},
    localparam [RRPV_BITS-1:0] RRPV_INSERT_COMMON  = RRPV_MAX
)(
    input  wire                  clk,
    input  wire                  rst,        // reset SINCRONO, ativo alto

    // ---- HIT (sincrono): a via acessada passa a "re-referencia imediata" --
    // pulsar 1 ciclo quando a logica de hit/miss (modulo/fase futura)
    // detectar um HIT na via hit_way_i do set hit_index_i. Identico a
    // repl_srrip.v.
    input  wire                  hit_en_i,
    input  wire [WAY_W-1:0]      hit_way_i,
    input  wire [INDEX_W-1:0]    hit_index_i,

    // ---- FILL (sincrono): a via recem-preenchida recebe o valor de
    //      insercao decidido pelo throttle bimodal desta borda (RARO ->
    //      RRPV_INSERT_RARE, COMUM -> RRPV_INSERT_COMMON, ver mecanismo no
    //      cabecalho). Pulsar 1 ciclo apos o fill do storage (cache_addr.v)
    //      na via vitima indicada por victim_way_o. Cada pulso de fill_en_i
    //      tambem avanca (incrementa) o contador global de throttle em 1.
    input  wire                  fill_en_i,
    input  wire [WAY_W-1:0]      fill_way_i,
    input  wire [INDEX_W-1:0]    fill_index_i,

    // CONTRATO DE SEQUENCIAMENTO fill_en_i vs. novo victim_req_i no MESMO
    // set (achado na revisao rtl-analyst da Fase 4, mesma race simetrica a
    // hit-vs-aging ja corrigida via hit_targets_cur_set_c, mas para FILL):
    //   found_c/found_way_c usam valores PRE-borda de rrpv_mem. Se, no
    //   mesmo ciclo em que a FSM crava victim_way_reg<=X para o set S,
    //   fill_en_i TAMBEM mirar a via X do set S (fechando o despejo
    //   ANTERIOR daquele set), e um NOVO victim_req_i para o MESMO set S
    //   for aceito nesse exato ciclo, a FSM pode cravar a via X de novo
    //   como vitima usando o valor pre-borda ainda-RRPV_MAX, descartando a
    //   linha recem-inserida sem nunca ter sido usada. Esta race NAO E
    //   mascarada em hardware (nao ha fill_targets_cur_set_c, ao contrario
    //   da mascara existente para hit). Contrato exigido do integrador:
    //   nao reemitir victim_req_i para o set S antes que o fill_en_i do
    //   despejo ANTERIOR daquele set S tenha completado (fluxo
    //   estritamente sequencial MISS->busca->fill por set). Nao testado
    //   nesta fase; mesma lacuna documentada em repl_srrip.v.
    //
    // ---- busca de vitima (handshake multi-ciclo por causa do aging) -------
    // protocolo IDENTICO a repl_srrip.v (ver comentario completo la):
    // pulsar victim_req_i por 1 ciclo com victim_busy_o==0; victim_busy_o
    // fica 1 durante a busca; victim_valid_o pulsa 1 ciclo quando a vitima e
    // encontrada, com victim_way_o valido nesse mesmo ciclo. Desempate por
    // menor indice de via.
    input  wire                  victim_req_i,
    input  wire [INDEX_W-1:0]    victim_index_i,
    output wire                  victim_busy_o,
    output wire                  victim_valid_o,
    output wire [WAY_W-1:0]      victim_way_o,

    // ---- consulta combinacional do RRPV cru de uma via (debug/verificacao) --
    // mesmo padrao rd_*_i/rd_*_o de repl_srrip.v/cache_addr.v/repl_lru.v.
    input  wire [WAY_W-1:0]      rd_way_i,
    input  wire [INDEX_W-1:0]    rd_index_i,
    output wire [RRPV_BITS-1:0]  rd_rrpv_o
);

    // -------------------------------------------------------------------
    // Guarda de elaboracao #1: RRPV_BITS precisa ser >=1, MESMA razao e
    // MESMA tecnica comprovada de repl_srrip.v (ver comentario detalhado
    // la sobre os idiomas alternativos que NAO bloqueiam a elaboracao
    // nesta toolchain -- wire [-1:0], localparam com divisao por zero --
    // ja descartados e documentados la, nao repetidos aqui).
    // -------------------------------------------------------------------
    generate
        if (RRPV_BITS < 1) begin : g_assert_rrpv_bits_ge_1
            repl_brrip_requires_rrpv_bits_ge_1_do_not_instantiate_with_other_config u_rrpv_bits_guard ();
        end
    endgenerate

    // -------------------------------------------------------------------
    // Guarda de elaboracao #2 (NOVA neste modulo, especifica do BRRIP):
    // BRRIP_THROTTLE_BITS precisa ser >=1. Com BRRIP_THROTTLE_BITS==0 o
    // contador `throttle_ctr` teria largura 0 -- alem de nao fazer sentido
    // semantico (periodo 2^0=1 degeneraria o throttle bimodal para "sempre
    // raro", ou seja, BRRIP colapsaria silenciosamente em SRRIP puro, o que
    // e uma config ENGANOSA, nao um erro de sintese em si -- mas a
    // comparacao `throttle_ctr == {0{1'b0}}` contra um registrador de
    // largura 0 e um idioma fragil/nao-portavel entre ferramentas), este
    // guard bloqueia essa config explicitamente na elaboracao, mesma tecnica
    // de instanciar um modulo com nome proposital inexistente.
    // -------------------------------------------------------------------
    generate
        if (BRRIP_THROTTLE_BITS < 1) begin : g_assert_throttle_bits_ge_1
            repl_brrip_requires_throttle_bits_ge_1_do_not_instantiate_with_other_config u_throttle_bits_guard ();
        end
    endgenerate

    // -------------------------------------------------------------------
    // Storage: um contador RRPV_BITS-wide por via/set, IDENTICO a
    // repl_srrip.v (leitura de debug combinacional, mesma justificativa
    // sobre M9K do Cyclone III -- ver repl_srrip.v/cache_addr.v). Reset
    // sincrono inicializa TODAS as vias/sets em RRPV_MAX.
    // -------------------------------------------------------------------
    reg [RRPV_BITS-1:0] rrpv_mem [0:WAYS-1][0:SETS-1];

    // indices de varredura usados so para o reset sincrono do array
    // (limites estaticos definidos pelos parameters -> sintetizavel).
    integer w_rst, s_rst;

    // -------------------------------------------------------------------
    // Contador GLOBAL de throttle bimodal (ver mecanismo no cabecalho do
    // modulo). Reset sincrono zera o contador -- isso e o que GARANTE o
    // "reset determinismo" exigido: a sequencia RARO/COMUM apos um reset e
    // SEMPRE a mesma (RARO no 1o fill apos o reset, depois COMUM nos
    // 2^BRRIP_THROTTLE_BITS-1 fills seguintes, repetindo), nunca dependente
    // de estado anterior "nao inicializado" (nao existe tal estado aqui --
    // e um registrador comum, sem uso de $random/semente externa). Testado
    // explicitamente em tb/repl_brrip_tb.v (secao "reset determinismo do
    // throttle"): reset no MEIO da simulacao (com o contador em um valor
    // nao-zero) e reproduz, bit a bit, a MESMA sequencia RARO/COMUM/COMUM/...
    // observada logo apos o primeiro reset.
    // -------------------------------------------------------------------
    reg [BRRIP_THROTTLE_BITS-1:0] throttle_ctr;

    // decisao RARO/COMUM desta borda: combinacional, le o valor CORRENTE
    // (pre-incremento) de throttle_ctr. RARO exatamente quando o contador
    // esta em 0 -- ou seja, 1 em cada 2^BRRIP_THROTTLE_BITS fills.
    wire throttle_rare_c = (throttle_ctr == {BRRIP_THROTTLE_BITS{1'b0}});

    // -------------------------------------------------------------------
    // FSM de busca de vitima: 3 estados, IDENTICA a repl_srrip.v (S_IDLE/
    // S_AGE/S_FOUND). Ver comentario completo em repl_srrip.v -- nao
    // repetido aqui na integra.
    // -------------------------------------------------------------------
    localparam [1:0] S_IDLE  = 2'd0,
                      S_AGE   = 2'd1,
                      S_FOUND = 2'd2;

    reg [1:0]         state;
    reg [INDEX_W-1:0]  search_idx_reg; // set sob busca (latched ao entrar em S_AGE/S_FOUND)
    reg [WAY_W-1:0]    victim_way_reg; // via vitima encontrada (latched em S_FOUND)

    // set efetivamente sob avaliacao pela busca combinacional abaixo: em
    // S_IDLE ainda nao ha nada latched, entao usamos o proprio
    // victim_index_i de entrada (permite decidir despejo direto no mesmo
    // ciclo do pedido); em S_AGE/S_FOUND usamos o indice ja latched.
    wire [INDEX_W-1:0] cur_search_idx = (state == S_IDLE) ? victim_index_i : search_idx_reg;

    // ---- mascara "hit vai zerar esta via NESTA MESMA borda" -----------------
    // Ver "NOTA DE RACE HIT-vs-AGING" no cabecalho de repl_srrip.v (aplicada
    // aqui identicamente). hit_en_i mirando o MESMO set sob avaliacao
    // (cur_search_idx) significa que a via hit_way_i vai transicionar para
    // RRPV=0 na proxima borda -- a MESMA borda em que a FSM decidiria (se
    // nao fosse por esta mascara) crava-la como vitima usando o valor
    // PRE-borda (ainda RRPV_MAX).
    wire hit_targets_cur_set_c = hit_en_i && (hit_index_i == cur_search_idx);

    // ---- busca combinacional por via com RRPV==RRPV_MAX no set corrente ----
    // priority-encoder sintetizavel: menor indice de via vence em empate.
    // WAYS generico -- o for-loop desenrola para qualquer associatividade.
    // A via alvo de um hit_en_i deste mesmo ciclo/set e EXCLUIDA da
    // elegibilidade a vitima -- corrige a race hit-vs-aging, mesma logica
    // de repl_srrip.v.
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

    // ---- FSM + storage + contador de throttle: um unico always sincrono,
    //      mesmo padrao de reset sincrono explicito de repl_srrip.v. Ordem
    //      de prioridade dentro do bloco (mesma de repl_srrip.v):
    //        1) reset (maior prioridade)
    //        2) transicoes da FSM de busca de vitima + aging (case abaixo)
    //        3) fill_en_i / hit_en_i (aplicados POR ULTIMO -- hit tem
    //           prioridade sobre fill se ambos mirarem a MESMA via/set no
    //           mesmo ciclo, corner case fora do fluxo normal de uso,
    //           documentado por completude, identico a repl_srrip.v).
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
                            // despejo direto: ja existe via com RRPV_MAX
                            victim_way_reg <= found_way_c;
                            state          <= S_FOUND;
                        end else begin
                            // nenhuma via em RRPV_MAX ainda -> precisa de aging
                            state <= S_AGE;
                        end
                    end
                end

                // -------------------------------------------------------
                S_AGE: begin
                    if (found_c) begin
                        // aging de rodadas anteriores ja produziu uma via
                        // com RRPV_MAX -> vitima encontrada, sem incrementar
                        // de novo neste ciclo.
                        victim_way_reg <= found_way_c;
                        state          <= S_FOUND;
                    end else begin
                        // aging: incrementa TODAS as vias do set sob busca
                        // em 1, sem saturar acima de RRPV_MAX.
                        for (k = 0; k < WAYS; k = k + 1) begin
                            rrpv_mem[k][search_idx_reg] <=
                                (rrpv_mem[k][search_idx_reg] == RRPV_MAX) ?
                                RRPV_MAX : (rrpv_mem[k][search_idx_reg] + 1'b1);
                        end
                        // permanece em S_AGE (sem atribuicao explicita a
                        // 'state' -> retem o valor atual)
                    end
                end

                // -------------------------------------------------------
                S_FOUND: begin
                    // pulso de 1 ciclo; retorna a IDLE automaticamente.
                    state <= S_IDLE;
                end

                default: state <= S_IDLE; // estado invalido (nao alcancavel) -> recupera p/ IDLE
            endcase

            // ---- FILL/HIT: acoes independentes da FSM de busca ---------
            // FILL: valor de insercao decidido pelo throttle bimodal desta
            // borda (throttle_rare_c calculado a partir do throttle_ctr
            // CORRENTE, isto e, ANTES do incremento abaixo) -- ver
            // mecanismo completo no cabecalho do modulo. Cada fill tambem
            // avanca o contador global em 1 (wraparound automatico por
            // largura fixa).
            if (fill_en_i) begin
                rrpv_mem[fill_way_i][fill_index_i] <=
                    throttle_rare_c ? RRPV_INSERT_RARE : RRPV_INSERT_COMMON;
                throttle_ctr <= throttle_ctr + 1'b1;
            end
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
