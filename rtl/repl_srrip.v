// =============================================================================
// repl_srrip.v
// PI4 UNIPAMPA - simulador de cache RTL (Fase 3 do plano de validacao)
//
// Responsabilidade deste modulo:
//   Implementar o Static RRIP (SRRIP-HP) de Jaleel et al., "High Performance
//   Cache Replacement Using Re-Reference Interval Prediction (RRIP)",
//   ISCA 2010. Cada via de cada set tem um contador RRPV (Re-Reference
//   Prediction Value) de RRPV_BITS bits que estima QUANDO aquela linha sera
//   reacessada:
//     RRPV = 0            -> "re-referencia imediata" (linha quente)
//     RRPV = RRPV_MAX-1    -> "intervalo intermediario" (valor de insercao)
//     RRPV = RRPV_MAX      -> "re-referencia distante" (candidata a vitima)
//
//   Duas acoes sincronas alteram RRPV (portas SEPARADAS -- ver nota de
//   nomenclatura abaixo):
//     - HIT na via W do set S: RRPV[W][S] <= 0 (pulsar hit_en_i).
//     - FILL (apos miss) na via W do set S: RRPV[W][S] <= RRPV_MAX-1
//       (pulsar fill_en_i). E o valor de insercao do SRRIP-HP do paper
//       (secao 3, "insere no intervalo intermediario" em vez de MRU/LRU
//       classico) -- disso vem a resistencia do RRIP a varreduras (scans).
//
//   Busca de vitima (despejo em MISS), algoritmo do paper (Figura 5):
//     1) Procura, no set, alguma via com RRPV == RRPV_MAX. Se achar, essa
//        via e a vitima (despejo "direto").
//     2) Se NENHUMA via tiver RRPV == RRPV_MAX, incrementa o RRPV de TODAS
//        as vias do set em 1 (sem saturar acima de RRPV_MAX) e repete a
//        busca -- esse e o "aging" do RRIP. Como aging pode exigir varias
//        rodadas (na pior hipotese, RRPV_MAX - min(RRPV) rodadas), a busca
//        de vitima NAO e combinacional pura: e uma pequena FSM de 3 estados
//        (ver abaixo) que pode levar multiplos ciclos de clock.
//
// -----------------------------------------------------------------------
// NOTA DE NOMENCLATURA (por que este modulo NAO usa wr_en_i/wr_way_i/
// wr_index_i como repl_lru.v):
//   No LRU de 1 bit (repl_lru.v), hit e "fill seguido de marcar MRU" sao a
//   MESMA acao de hardware ("esta via passou a ser a mais recentemente
//   usada"), por isso uma unica porta wr_en_i bastava. No RRIP, hit e fill
//   sao acoes DIFERENTES com valores-alvo DIFERENTES (hit->0, fill->
//   RRPV_MAX-1), entao este modulo expoe duas portas de escrita sincronas
//   distintas e nomeadas pelo que fazem: hit_en_i/hit_way_i/hit_index_i e
//   fill_en_i/fill_way_i/fill_index_i. A porta de consulta combinacional
//   do RRPV cru de uma via (rd_way_i/rd_index_i/rd_rrpv_o) segue o MESMO
//   padrao rd_*_i/rd_*_o de cache_addr.v/repl_lru.v.
//
// NOTA DE GENERALIZACAO (diferenca chave vs repl_lru.v):
//   repl_lru.v e um LRU de 1 bit por set, que SO funciona corretamente para
//   WAYS==2 (a elaboracao daquele modulo falha de proposito se WAYS!=2 --
//   ver o guard la). Este modulo (repl_srrip.v) generaliza para QUALQUER
//   WAYS >= 1, porque cada via tem seu PROPRIO contador RRPV_BITS-wide
//   independente; a busca de vitima e um for-loop sintetizavel (encolhido/
//   desenrolado pela ferramenta) sobre WAYS posicoes, sem limite estrutural
//   de associatividade. E exatamente esse mecanismo de contador por via
//   (em vez de 1 bit global por set) que o RRIP usa para escalar alem de
//   2-way -- fidelidade ao paper (Jaleel et al., ISCA 2010, secao 3).
//
// NOTA DE RACE HIT-vs-AGING (corner case corrigido na revisao rtl-analyst
// da Fase 3 -- ressalva MEDIA):
//   Cenario do bug: a FSM de busca de vitima (S_AGE, ver abaixo) decide
//   found_c/found_way_c COMBINACIONALMENTE a partir dos valores de
//   rrpv_mem JA ASSENTADOS pela rodada de aging anterior (valores
//   "pre-borda" do ciclo corrente). Se, no MESMO ciclo em que found_c=1
//   aponta a via X do set S como vitima (porque rrpv_mem[X][S]==RRPV_MAX
//   *antes* desta borda), chegar tambem hit_en_i para essa MESMA via X do
//   MESMO set S, entao NA MESMA BORDA: (i) a FSM crava
//   victim_way_reg<=X e vai para S_FOUND, E (ii) o hit zera
//   rrpv_mem[X][S]<=0. No ciclo seguinte, victim_way_o aponta pra uma via
//   que acabou de "renascer" com RRPV=0 -- se o integrador fizer fill
//   nela, descarta uma linha recem-acessada (viola a propria semantica do
//   RRIP, que existe justamente para NAO despejar linhas quentes).
//
//   Correcao escolhida (abordagem "a" da revisao, nao so documentacao):
//   found_c/found_way_c agora sao calculados sobre uma vista "pos-hit
//   deste ciclo" de rrpv_mem -- qualquer via que hit_en_i estiver mirando
//   NESTE MESMO CICLO, no MESMO set sob avaliacao (cur_search_idx), e
//   EXCLUIDA da lista de candidatas a RRPV_MAX, mesmo que seu valor
//   pre-borda seja RRPV_MAX (ver mascara hit_targets_cur_set_c no bloco de
//   busca combinacional abaixo). Efeito:
//     - se existir OUTRA via no mesmo set tambem em RRPV_MAX (empate), ela
//       vence no lugar da via que esta sendo hit (a busca simplesmente
//       escolhe o proximo candidato legitimo, sem custo de ciclo extra).
//     - se a via hit for a UNICA em RRPV_MAX, found_c fica 0 neste ciclo
//       (a FSM PERMANECE em S_AGE e aplica mais uma rodada de aging nas
//       demais vias -- a propria via hit already sera sobrescrita por seu
//       valor pos-hit=0 pela prioridade hit-por-ultimo ja existente no
//       always sincrono, entao ela nunca e artificialmente "saturada" em
//       RRPV_MAX pela logica de aging). A busca so volta a apontar
//       vitima quando alguma via GENUINAMENTE ociosa alcancar RRPV_MAX.
//   Por que "a" em vez de "b" (guard/assertion + contrato estritamente
//   sequencial): o custo de implementacao de "a" e baixo (1 mascara
//   combinacional no priority-encoder existente, sem estados/ciclos
//   extras) e elimina o problema de raiz em vez de apenas proibir por
//   contrato um padrao de uso (hit concorrente com busca de vitima no
//   mesmo set) que, embora incomum no fluxo tipico HIT->hit_en_i ;
//   MISS->victim_req_i...fill_en_i, nao e implausivel em um pipeline mais
//   agressivo (ex.: um segundo acesso ao mesmo set completando um hit
//   enquanto uma busca de despejo iniciada por outro acesso anterior ainda
//   esta em aging). Testado explicitamente em tb/repl_srrip_tb.v (secao
//   "RACE hit-vs-aging"): dois cenarios, (1) empate com alternativa
//   disponivel -- a via hit e corretamente preterida em favor da via
//   irma; (2) via hit e a UNICA candidata -- a busca corretamente adia a
//   decisao por mais rodadas de aging em vez de cravar a via recem-hit
//   como vitima.
//
//   CASO NAO PROTEGIDO (achado na revisao de follow-up, severidade Menor,
//   nao bloqueante para a Config A do projeto): a mitigacao acima presume
//   hit_en_i pulsado por 1 ciclo (mesmo CONTRATO DE PULSO documentado
//   abaixo para victim_req_i). Se hit_en_i for mantido em nivel alto por
//   VARIOS ciclos consecutivos (contrato violado) mirando a UNICA via de
//   um set que estiver em S_AGE:
//     - para WAYS>=2 (inclui a Config A, WAYS=2): NAO trava. As demais
//       vias do set continuam envelhecendo normalmente (nao mascaradas) e
//       alcancam RRPV_MAX em no maximo RRPV_MAX rodadas adicionais --
//       apenas latencia extra limitada, comportamento correto e ate
//       desejavel (a linha quente nao e despejada).
//     - para WAYS==1 (extremo da generalizacao "QUALQUER WAYS>=1" citada
//       acima): a unica via do set E a via mascarada. found_c NUNCA fica
//       1 enquanto hit_en_i permanecer alto -- a FSM fica PRESA
//       indefinidamente em S_AGE (victim_valid_o nunca sobe), sem
//       protecao de hardware. Nao ha guard nem teste para este caso
//       porque exige violar o contrato de pulso E usar WAYS==1
//       simultaneamente -- combinacao fora do uso real deste projeto
//       (Config A usa WAYS=2), mas quem reusar este modulo com WAYS==1
//       deve estar ciente de que o contrato de pulso de hit_en_i passa a
//       ser uma garantia de liveness, nao so de corretude de dado.
// =============================================================================

module repl_srrip #(
    parameter SETS      = 4, // numero de conjuntos (sets)
    parameter WAYS      = 2, // associatividade (vias por set) -- QUALQUER valor >=1
    // largura do contador RRPV (RRPV_MAX = 2^RRPV_BITS - 1). ATENCAO:
    // RRPV_BITS==1 e um caso degenerado consistente com o paper (M=1 na
    // notacao de Jaleel et al.) mas colapsa RRPV_INSERT(=RRPV_MAX-1=0)
    // para o MESMO valor do hit (0) -- perde-se o "intervalo
    // intermediario" que distingue SRRIP de um NRU/MRU classico (insercao
    // e hit passam a ser indistinguiveis, RRPV so tem os valores {0,1}).
    // Nao e proibido (RRPV_BITS>=1 e aceito pelo guard de elaboracao
    // abaixo), mas quem reusar este modulo com RRPV_BITS=1 deve estar
    // ciente de que esta obtendo NRU, nao SRRIP-HP de fato.
    parameter RRPV_BITS = 2
)(
    clk, rst,
    hit_en_i, hit_way_i, hit_index_i,
    fill_en_i, fill_way_i, fill_index_i,
    victim_req_i, victim_index_i, victim_busy_o, victim_valid_o, victim_way_o,
    rd_way_i, rd_index_i, rd_rrpv_o
);

    // ---- larguras/derivados: mesmo padrao de cache_addr.v/repl_lru.v,
    //      nunca hardcoded, calculados a partir dos parameters. Declarados
    //      aqui, logo no inicio do corpo do modulo -- estilo de porta
    //      Verilog-1995/2001 NAO-ANSI (a lista de parametros #(...) so
    //      aceita `parameter` de verdade nesta sintaxe, compativel com o
    //      Quartus II 13.0sp1/Cyclone III alvo do projeto). ---------------
    localparam INDEX_W  = $clog2(SETS);                  // bits de indice do set
    localparam WAY_W    = (WAYS > 1) ? $clog2(WAYS) : 1;  // bits p/ selecionar a via

    // RRPV_MAX = todos os bits em 1 (maior valor representavel em RRPV_BITS
    // bits) = "re-referencia distante". RRPV_INSERT = RRPV_MAX-1 = valor de
    // insercao do SRRIP-HP ("intervalo intermediario", Fig. 5 do paper).
    localparam [RRPV_BITS-1:0] RRPV_MAX    = {RRPV_BITS{1'b1}};
    localparam [RRPV_BITS-1:0] RRPV_INSERT = RRPV_MAX - {{(RRPV_BITS-1){1'b0}}, 1'b1};

    input  wire                  clk;
    input  wire                  rst;        // reset SINCRONO, ativo alto

    // ---- HIT (sincrono): a via acessada passa a "re-referencia imediata" --
    // pulsar 1 ciclo quando a logica de hit/miss (modulo/fase futura)
    // detectar um HIT na via hit_way_i do set hit_index_i.
    input  wire                  hit_en_i;
    input  wire [WAY_W-1:0]      hit_way_i;
    input  wire [INDEX_W-1:0]    hit_index_i;

    // ---- FILL (sincrono): a via recem-preenchida entra no intervalo
    //      intermediario (RRPV = RRPV_MAX-1), NAO em RRPV=0 -- e essa a
    //      diferenca central do RRIP vs um MRU classico (resistencia a
    //      scans: uma linha nova nao "salta" pra frente da fila de
    //      despejo). Pulsar 1 ciclo apos o fill do storage (cache_addr.v)
    //      na via vitima indicada por victim_way_o.
    input  wire                  fill_en_i;
    input  wire [WAY_W-1:0]      fill_way_i;
    input  wire [INDEX_W-1:0]    fill_index_i;

    // CONTRATO DE SEQUENCIAMENTO fill_en_i vs. novo victim_req_i no MESMO
    // set (achado na revisao de follow-up da Fase 4, aplicavel tambem
    // aqui por simetria estrutural com a race hit-vs-aging ja corrigida):
    //   found_c/found_way_c usam valores PRE-borda de rrpv_mem. Se, no
    //   mesmo ciclo em que a FSM crava victim_way_reg<=X para o set S,
    //   fill_en_i TAMBEM mirar a via X do set S (fechando o despejo
    //   ANTERIOR daquele set), e um NOVO victim_req_i para o MESMO set S
    //   for aceito nesse exato ciclo (S_IDLE relendo victim_req_i), a
    //   FSM pode cravar a via X de novo como vitima usando o valor
    //   pre-borda ainda-RRPV_MAX, descartando a linha que acabou de ser
    //   inserida sem nunca ter sido usada. AO CONTRARIO da race
    //   hit-vs-aging, esta NAO E mascarada em hardware (nao ha
    //   fill_targets_cur_set_c). Contrato exigido do integrador: nao
    //   reemitir victim_req_i para o set S antes que o fill_en_i do
    //   despejo ANTERIOR daquele set S tenha completado (fluxo
    //   estritamente sequencial MISS->busca->fill por set, como
    //   documentado no plano do projeto). Nao testado nesta fase.
    //
    // ---- busca de vitima (handshake multi-ciclo por causa do aging) -------
    // protocolo:
    //   1) com victim_busy_o==0 (FSM ociosa), pulsar victim_req_i=1 por 1
    //      ciclo com victim_index_i = set do MISS. Pulsos enquanto
    //      victim_busy_o==1 sao IGNORADOS (a FSM so aceita novo pedido em
    //      IDLE) -- contrato de uso: o integrador deve esperar
    //      victim_busy_o baixar antes de pedir uma nova busca.
    //
    //      CONTRATO DE PULSO (1 ciclo) e o que esta implementacao FAZ se
    //      violado (documentado e testado em tb/repl_srrip_tb.v, secao
    //      "victim_req_i sustentado"; nao ha protecao em hardware contra a
    //      violacao, apenas o comportamento resultante e definido/testado
    //      nesta implementacao especifica):
    //        - manter victim_req_i em 1 por VARIOS ciclos enquanto
    //          victim_busy_o==1 (FSM em S_AGE/S_FOUND) e INOFENSIVO: esses
    //          estados nunca leem victim_req_i, entao o resultado da busca
    //          em andamento nao muda.
    //        - se victim_req_i AINDA estiver em 1 no exato ciclo em que a
    //          FSM retorna a S_IDLE (S_FOUND->S_IDLE), esse nivel alto e
    //          interpretado como um NOVO pedido nesse mesmo ciclo -- a FSM
    //          reinicia a busca imediatamente (usando o victim_index_i
    //          corrente) sem nunca passar 1 ciclo visivel em
    //          victim_busy_o==0. Isso pode gerar uma sequencia continua de
    //          "vitima encontrada" para o MESMO set enquanto o sinal
    //          continuar alto -- efeito colateral de manter o pedido
    //          asserted alem de 1 ciclo, nao um recurso de "busca continua"
    //          proposital. O integrador deve tratar isso como contrato
    //          violado: pulsar por exatamente 1 ciclo e a unica forma
    //          suportada de uso.
    //   2) victim_busy_o fica em 1 enquanto a busca esta em andamento
    //      (inclui o ciclo em que o resultado esta disponivel).
    //   3) quando a vitima e encontrada, victim_valid_o fica em 1 por
    //      EXATAMENTE 1 ciclo, com victim_way_o valido NESSE MESMO ciclo
    //      (a FSM retorna a IDLE no ciclo seguinte automaticamente).
    // desempate: se mais de uma via tiver RRPV==RRPV_MAX simultaneamente,
    // vence a de MENOR indice (prioridade estatica, ver busca combinacional
    // abaixo) -- escolha arbitraria permitida pelo paper (nao especifica
    // desempate), documentada aqui para tornar o comportamento deterministico.
    input  wire                  victim_req_i;
    input  wire [INDEX_W-1:0]    victim_index_i;
    output wire                  victim_busy_o;
    output wire                  victim_valid_o;
    output wire [WAY_W-1:0]      victim_way_o;

    // ---- consulta combinacional do RRPV cru de uma via (debug/verificacao) --
    // mesmo padrao rd_*_i/rd_*_o de cache_addr.v/repl_lru.v.
    input  wire [WAY_W-1:0]      rd_way_i;
    input  wire [INDEX_W-1:0]    rd_index_i;
    output wire [RRPV_BITS-1:0]  rd_rrpv_o;

    // -------------------------------------------------------------------
    // Guarda de elaboracao: RRPV_BITS precisa ser >=1 para RRPV_INSERT
    // (=RRPV_MAX-1) nao "estourar" por baixo (RRPV_BITS==0 faria
    // RRPV_MAX==0 e RRPV_INSERT tentaria representar -1 num campo de 0
    // bits). Mesma tecnica comprovada em repl_lru.v (linhas ~77-102):
    // dentro de generate/if da condicao de ERRO, instancia um modulo com
    // nome proposital inexistente, forcando erro fatal de resolucao na
    // elaboracao (ModelSim/Questa e Quartus tratam ambos como erro fatal).
    // Os idiomas alternativos (wire [-1:0], localparam com divisao por
    // zero) NAO bloqueiam a elaboracao nesta toolchain -- ja descartados
    // e documentados em repl_lru.v.
    //
    // VERIFICADO EXPERIMENTALMENTE (instanciando este modulo com
    // RRPV_BITS=0 forcado): nesta config invalida, o proprio calculo de
    // RRPV_MAX/RRPV_INSERT logo abaixo (`{RRPV_BITS{1'b1}}` com
    // RRPV_BITS=0, e `{(RRPV_BITS-1){1'b0}}` com expoente negativo) ja
    // dispara erro fatal de elaboracao no ModelSim/Questa por conta
    // propria ("Replication multiplier (0) should be greater than zero" /
    // "Negative replication multiplier (-1)"), ANTES mesmo do elaborador
    // chegar a avaliar este bloco `generate`. Ou seja, para RRPV_BITS==0 a
    // falha ja acontece "de graca" pelo proprio operador de replicacao.
    // Mantemos o guard explicito abaixo mesmo assim, como defesa em
    // profundidade e documentacao clara da intencao (robusto mesmo que a
    // forma de calcular RRPV_MAX/RRPV_INSERT mude no futuro e deixe de
    // falhar naturalmente).
    // -------------------------------------------------------------------
    generate
        if (RRPV_BITS < 1) begin : g_assert_rrpv_bits_ge_1
            repl_srrip_requires_rrpv_bits_ge_1_do_not_instantiate_with_other_config u_rrpv_bits_guard ();
        end
    endgenerate

    // -------------------------------------------------------------------
    // Storage: um contador RRPV_BITS-wide por via/set. Leitura de debug
    // (rd_rrpv_o, mais abaixo) e COMBINACIONAL -- mesmo padrao adotado em
    // cache_addr.v/repl_lru.v (ver comentario detalhado la sobre M9K do
    // Cyclone III: leitura combinacional nao e o padrao que o Quartus
    // reconhece para inferencia de M9K; nesta fase de validacao, array
    // minusculo, espera-se sintese em LEs/MLAB, entao isso nao e problema
    // aqui). Reset sincrono inicializa TODAS as vias/sets em RRPV_MAX
    // ("re-referencia distante"): escolha deterministica para simulacao,
    // consistente com implementacoes tipicas de RRIP onde uma linha ainda
    // invalida (valid bit em cache_addr.v, fora do escopo deste modulo)
    // deve ser candidata natural a vitima assim que passar a ser
    // considerada para despejo.
    // -------------------------------------------------------------------
    reg [RRPV_BITS-1:0] rrpv_mem [0:WAYS-1][0:SETS-1];

    // indices de varredura usados so para o reset sincrono do array
    // (limites estaticos definidos pelos parameters -> sintetizavel).
    integer w_rst, s_rst;

    // -------------------------------------------------------------------
    // FSM de busca de vitima. 3 estados:
    //   S_IDLE  - ociosa, aguardando victim_req_i.
    //   S_AGE   - busca ativa no set latched em search_idx_reg: a CADA
    //             ciclo neste estado, verifica combinacionalmente
    //             (found_c/found_way_c, bloco always @(*) abaixo) se
    //             alguma via ja tem RRPV==RRPV_MAX. Se sim, vai para
    //             S_FOUND. Se nao, aplica o "aging" (incrementa TODAS as
    //             vias do set em 1, sem saturar acima de RRPV_MAX) e
    //             permanece em S_AGE para reavaliar no proximo ciclo.
    //             Este e o estado que pode se repetir por varios ciclos
    //             (equivalente ao "AGE" sugerido no plano de validacao).
    //   S_FOUND - vitima encontrada; victim_valid_o=1 e victim_way_o
    //             validos por EXATAMENTE 1 ciclo; retorna a S_IDLE no
    //             ciclo seguinte automaticamente (nao precisa de ack).
    //
    // Caso especial: se a busca ja encontra vitima no PROPRIO ciclo em que
    // victim_req_i e aceito (estado ainda S_IDLE, nenhuma via em aging
    // necessaria), a transicao vai DIRETO de S_IDLE para S_FOUND -- e o
    // "despejo direto" do algoritmo, sem nenhuma rodada de aging.
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
    // Ver "NOTA DE RACE HIT-vs-AGING" no cabecalho do modulo. hit_en_i
    // mirando o MESMO set sob avaliacao (cur_search_idx) significa que a
    // via hit_way_i vai transicionar para RRPV=0 na proxima borda -- a
    // MESMA borda em que a FSM decidiria (se nao fosse por esta mascara)
    // crava-la como vitima usando o valor PRE-borda (ainda RRPV_MAX).
    wire hit_targets_cur_set_c = hit_en_i && (hit_index_i == cur_search_idx);

    // ---- busca combinacional por via com RRPV==RRPV_MAX no set corrente ----
    // priority-encoder sintetizavel: menor indice de via vence em empate.
    // WAYS generico -- o for-loop desenrola para qualquer associatividade.
    // A via alvo de um hit_en_i deste mesmo ciclo/set (hit_targets_cur_set_c
    // + hit_way_i==k) e EXCLUIDA da elegibilidade a vitima, mesmo que seu
    // valor pre-borda seja RRPV_MAX -- corrige a race hit-vs-aging (ver nota
    // no cabecalho): evita crivar como vitima uma via que esta "renascendo"
    // por hit na mesma borda.
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

    // ---- FSM + storage: um unico always sincrono, mesmo padrao de reset
    //      sincrono explicito de cache_addr.v/repl_lru.v. Ordem de
    //      prioridade dentro do bloco (relevante so em cenarios fora do
    //      fluxo normal de uso, ja que hit/fill/victim_req nao devem
    //      coincidir no MESMO set na mesma config real -- fluxo e sempre
    //      sequencial: HIT->hit_en_i ; MISS->victim_req_i...fill_en_i):
    //        1) reset (maior prioridade)
    //        2) transicoes da FSM de busca de vitima + aging (case abaixo)
    //        3) hit_en_i / fill_en_i (aplicados POR ULTIMO, portanto tem
    //           prioridade sobre um incremento de aging que por acaso
    //           mire a MESMA via/set no mesmo ciclo -- corner case nao
    //           esperado em uso normal, documentado aqui por completude).
    //
    //      Esta prioridade (hit/fill por ultimo) e o que garante que, no
    //      cenario da "NOTA DE RACE HIT-vs-AGING" (cabecalho do modulo),
    //      a via hit termine mesmo em RRPV=0 (nao em RRPV_MAX "salvo" por
    //      um incremento de aging concorrente) -- e a mascara
    //      hit_targets_cur_set_c (bloco de busca combinacional acima)
    //      garante que essa mesma via nunca seja simultaneamente cravada
    //      como victim_way_reg. As duas mecanicas juntas fecham a race.
    // -------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state          <= S_IDLE;
            search_idx_reg <= {INDEX_W{1'b0}};
            victim_way_reg <= {WAY_W{1'b0}};
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
                        // com RRPV_MAX (avaliado com os valores CORRENTES
                        // de rrpv_mem, ja atualizados pela ultima rodada
                        // de aging) -> vitima encontrada, sem incrementar
                        // de novo neste ciclo.
                        victim_way_reg <= found_way_c;
                        state          <= S_FOUND;
                    end else begin
                        // aging: incrementa TODAS as vias do set sob busca
                        // em 1, sem saturar acima de RRPV_MAX (a checagem
                        // de saturacao aqui e defensiva -- found_c==0
                        // implica que nenhuma via ja esta em RRPV_MAX).
                        for (k = 0; k < WAYS; k = k + 1) begin
                            rrpv_mem[k][search_idx_reg] <=
                                (rrpv_mem[k][search_idx_reg] == RRPV_MAX) ?
                                RRPV_MAX : (rrpv_mem[k][search_idx_reg] + 1'b1);
                        end
                        // permanece em S_AGE (sem atribuicao explicita a
                        // 'state' -> retem o valor atual, padrao Verilog
                        // para registrador sem atribuicao no ramo do case)
                    end
                end

                // -------------------------------------------------------
                S_FOUND: begin
                    // pulso de 1 ciclo (victim_valid_o/victim_way_o ja
                    // validos combinacionalmente enquanto state==S_FOUND,
                    // ver assigns abaixo); retorna a IDLE automaticamente.
                    state <= S_IDLE;
                end

                default: state <= S_IDLE; // estado invalido (nao alcancavel) -> recupera p/ IDLE
            endcase

            // ---- HIT/FILL: acoes independentes da FSM de busca ---------
            if (fill_en_i) begin
                rrpv_mem[fill_way_i][fill_index_i] <= RRPV_INSERT;
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
