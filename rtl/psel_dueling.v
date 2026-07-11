// =============================================================================
// psel_dueling.v
// PI4 UNIPAMPA - simulador de cache RTL (Fase 5 do plano de validacao)
//
// Responsabilidade deste modulo:
//   Implementar o PSEL (Policy SELector), o contador saturante que arbitra
//   o "set dueling" de Jaleel et al., "High Performance Cache Replacement
//   Using Re-Reference Interval Prediction (RRIP)", ISCA 2010, secao 4.2
//   ("Dynamic RRIP" / DRRIP via set-dueling, tecnica originalmente de
//   Qureshi et al., "A Case for MLP-Aware Cache Replacement", ISCA 2006).
//
//   Mecanica do set-dueling (contexto, fora do escopo DESTE modulo -- ver
//   "FORA DE ESCOPO" abaixo): um pequeno numero de sets da cache e reservado
//   como Sample Dueling Monitors (SDMs) -- um subconjunto fixo de sets roda
//   SEMPRE SRRIP puro (SDM-SRRIP), outro subconjunto disjunto roda SEMPRE
//   BRRIP puro (SDM-BRRIP). Todos os DEMAIS sets ("seguidores", a grande
//   maioria da cache) rodam a politica que o PSEL disser que esta vencendo
//   no momento. O PSEL e um contador saturante UNICO e GLOBAL (nao 1 por
//   set) que "vota": cada MISS observado em um set do SDM-SRRIP e um voto a
//   favor de trocar para BRRIP nos seguidores; cada MISS num set do
//   SDM-BRRIP e um voto a favor de trocar para SRRIP. O MSB do contador
//   decide o vencedor corrente (ver "CONVENCAO" abaixo).
//
// -----------------------------------------------------------------------
// FORA DE ESCOPO desta fase/deste modulo (deliberado, ver plano-cache.md
// item 5: "valide SEPARADO da cache pequena (4 sets nao comportam SDMs
// reais)"):
//   - Este modulo NAO sabe quais indices de set sao SDM-SRRIP, SDM-BRRIP ou
//     seguidores -- essa e uma decisao de MAPEAMENTO (tipicamente feita por
//     poucos bits do INDEX do set, ex. "os sets cujo INDEX termina em uma
//     constante escolhida por politica de amostragem constante ou
//     enderecamento dinamico", ver secao 4.2/Fig. 10 do paper) que cabe ao
//     INTEGRADOR (uma fase futura, fora deste plano) decidir e rotear.
//   - Este modulo tambem NAO decide sozinho se um acesso e HIT ou MISS, nem
//     em qual set ele ocorreu -- ele so recebe, de quem quer que faca essa
//     classificacao (cache_addr.v + repl_srrip.v/repl_brrip.v numa
//     integracao futura), dois pulsos de evento ja pre-filtrados:
//     "ocorreu um miss num set do SDM-SRRIP" (miss_srrip_i) e "ocorreu um
//     miss num set do SDM-BRRIP" (miss_brrip_i).
//   - Este modulo e testado aqui com uma sequencia SINTETICA desses dois
//     pulsos, alimentada diretamente pelo testbench -- sem instanciar
//     cache_addr.v/repl_srrip.v/repl_brrip.v. E exatamente o que o plano
//     pede ao dizer "valide SEPARADO da cache pequena".
//
// -----------------------------------------------------------------------
// CONVENCAO DE INCREMENTO/DECREMENTO (escolhida e documentada; a convencao
// oposta e igualmente valida na literatura, mas o hardware PRECISA fixar
// uma e ser consistente -- eis a que este modulo usa):
//
//   miss_brrip_i (miss num set do SDM-BRRIP) -> INCREMENTA o PSEL.
//   miss_srrip_i (miss num set do SDM-SRRIP) -> DECREMENTA o PSEL.
//
//   Intuicao: o contador "caminha" na direcao de quem esta MISSANDO MENOS.
//   Se o SDM-BRRIP esta perdendo mais partidas (mais misses -> mais
//   incrementos), o contador sobe e se aproxima do teto (MSB=1). Se o
//   SDM-SRRIP esta perdendo mais (mais misses -> mais decrementos), o
//   contador desce e se aproxima do piso (MSB=0).
//
// -----------------------------------------------------------------------
// RELACAO MSB <-> POLITICA DOS SEGUIDORES (follower_use_brrip_o)
// -----------------------------------------------------------------------
//   A politica que VENCE (e aplicada aos seguidores) e a que MISSOU MENOS
//   no seu SDM dedicado -- e a que "puxou menos" o contador na sua propria
//   direcao de missing, isto e, e a OPOSTA de quem esta "vencendo a
//   votacao de misses".
//
//   PSEL_BITS-1 (MSB) == 1  -> o contador esta no METADE SUPERIOR da faixa
//     -> mais incrementos que decrementos ocorreram recentemente -> SDM-BRRIP
//     missou MAIS (foi quem mais empurrou o contador pra cima) -> BRRIP esta
//     performando PIOR -> os seguidores devem usar SRRIP.
//   PSEL_BITS-1 (MSB) == 0  -> o contador esta na METADE INFERIOR da faixa
//     -> mais decrementos que incrementos ocorreram recentemente -> SDM-SRRIP
//     missou MAIS -> SRRIP esta performando PIOR -> os seguidores devem usar
//     BRRIP.
//
//   Logo: follower_use_brrip_o = ~psel_reg[PSEL_BITS-1] (NEGACAO do MSB).
//   Esta e a mesma relacao inversa descrita textualmente no enunciado da
//   tarefa: "se PSEL indica mais misses em SRRIP [MSB=0, metade inferior],
//   a maioria usa BRRIP" -- exatamente o assign acima.
//
// -----------------------------------------------------------------------
// COMPORTAMENTO EM MISS SIMULTANEO (miss_srrip_i E miss_brrip_i pulsados no
// MESMO ciclo) -- escolha de projeto e justificativa
// -----------------------------------------------------------------------
//   Cenario nao esperado no uso real (cada SDM e monitorado
//   independentemente, um MESMO acesso so pode ser roteado para NO MAXIMO
//   um SDM por vez -- um set e SDM-SRRIP OU SDM-BRRIP OU seguidor, nunca
//   dois papeis ao mesmo tempo, entao um unico acesso nunca gera os dois
//   pulsos simultaneamente por construcao da integracao futura). Ainda
//   assim, como sao portas independentes, nada em HARDWARE impede que dois
//   MISSES DE ACESSOS DIFERENTES (um dirigido a um set SDM-SRRIP, outro a um
//   set SDM-BRRIP) calhem de ser reportados na MESMA borda de clock em um
//   integrador com mais de 1 porta de miss concorrente -- por isso este
//   modulo define e testa o caso.
//
//   Escolha: CANCELAMENTO -- quando os dois pulsam juntos, o incremento e o
//   decremento se anulam algebricamente e o PSEL NAO MUDA naquele ciclo
//   (nem satura, nem prioriza um lado). Motivo da escolha (em vez de dar
//   prioridade fixa a um dos dois): os dois eventos representam evidencia
//   IGUALMENTE valida e simultanea a favor de politicas opostas -- dar
//   prioridade a um lado introduziria um vies sistematico arbitrario (ex.
//   "SRRIP sempre vence empates") sem justificativa no paper (que nao
//   antecipa esse cenario, ja que descreve UM PSEL por par de SDMs
//   avaliado organicamente pelo fluxo de acessos, nao por portas paralelas
//   independentes). Cancelamento e a unica opcao que trata os dois votos
//   com peso simetrico. Implementado dando ao caso {miss_brrip_i,
//   miss_srrip_i}==2'b11 sua PROPRIA ramificacao no case abaixo (retem o
//   valor corrente), em vez de deixar os efeitos de incremento e decremento
//   colidirem numa unica atribuicao (o que exigiria um `+1-1` explicito --
//   funcionalmente identico ao cancelamento, mas a ramificacao dedicada
//   deixa a intencao de projeto legivel no RTL, nao so no comentario).
//   Testado explicitamente em tb/psel_dueling_tb.v em DOIS pontos da faixa
//   (meio da faixa, longe das bordas, para provar que NAO ha prioridade
//   disfarcada de saturacao; e nas duas bordas, onde cancelamento e
//   saturacao dariam o mesmo resultado observavel, testado por completude).
//
// -----------------------------------------------------------------------
// SATURACAO (sem wraparound)
// -----------------------------------------------------------------------
//   psel_reg NUNCA ultrapassa PSEL_MAX (=2^PSEL_BITS-1, todos os bits em 1)
//   por incremento, nem fica abaixo de 0 por decremento -- ao alcancar um
//   extremo, incrementos/decrementos adicionais NESSA direcao sao
//   descartados (o contador trava no extremo) ate que um evento na direcao
//   OPOSTA o mova dali. Testado explicitamente (item iii/iv do plano).
//
// -----------------------------------------------------------------------
// VALOR DE RESET (justificativa)
// -----------------------------------------------------------------------
//   psel_reg reseta no PONTO MEDIO da faixa: PSEL_RESET = 2^(PSEL_BITS-1)
//   (bit MSB=1, todos os demais bits=0). Para PSEL_BITS=10 (largura default,
//   fiel ao paper, Jaleel et al. ISCA 2010 secao 4.2), isso e 512 -- o meio
//   exato da faixa 0..1023. Motivo: antes de QUALQUER amostragem (primeiro
//   miss observado em qualquer SDM apos o reset), o hardware nao deve
//   favorecer SRRIP nem BRRIP -- um reset em 0 ou no MAX enviesaria a
//   decisao inicial dos seguidores para uma das duas politicas sem nenhuma
//   evidencia empirica ainda coletada, contrariando o proprio proposito do
//   set-dueling (deixar os DADOS decidirem). O ponto medio exato para uma
//   faixa com um numero PAR de valores (2^PSEL_BITS, sempre par para
//   PSEL_BITS>=1) cai entre dois inteiros (ex. 511.5 para PSEL_BITS=10);
//   escolhemos arredondar para CIMA (2^(PSEL_BITS-1), que tem MSB=1) em vez
//   de para baixo -- escolha arbitraria mas deterministica e simples de
//   expressar em RTL (um unico bit setado), documentada aqui para deixar
//   claro que o "empate" de reset resolve a favor de SRRIP nos seguidores
//   (MSB=1 -> follower_use_brrip_o=0, ver relacao acima) ate a primeira
//   amostragem inclinar o contador para um lado ou outro.
// =============================================================================

module psel_dueling #(
    // largura do contador PSEL. Default=10, fidelidade direta ao paper
    // (Jaleel et al., ISCA 2010, secao 4.2 -- contador de 10 bits, faixa
    // 0..1023, reset em 512). Parametrizavel para qualquer PSEL_BITS>=2
    // (ver guard de elaboracao abaixo sobre por que PSEL_BITS==1 e
    // rejeitado, e a config REDUZIDA usada no testbench de validacao desta
    // fase, mesmo espirito de BRRIP_THROTTLE_BITS reduzido em
    // tb/repl_brrip_tb.v -- ver cabecalho daquele arquivo).
    parameter PSEL_BITS = 10,

    // ---- derivados: mesmo padrao de repl_srrip.v/repl_brrip.v, nunca
    //      hardcoded, calculados a partir do parameter. ---------------------
    localparam [PSEL_BITS-1:0] PSEL_MAX   = {PSEL_BITS{1'b1}},          // teto (todos os bits em 1)
    localparam [PSEL_BITS-1:0] PSEL_MIN   = {PSEL_BITS{1'b0}},          // piso (todos os bits em 0)
    localparam [PSEL_BITS-1:0] PSEL_RESET = {1'b1, {(PSEL_BITS-1){1'b0}}} // ponto medio (MSB=1, resto=0)
)(
    input  wire clk,
    input  wire rst,              // reset SINCRONO, ativo alto

    // ---- eventos de miss dos SDMs (pulsos de 1 ciclo) ----------------------
    // pulsar 1 ciclo quando a logica de hit/miss (fora do escopo deste
    // modulo, ver "FORA DE ESCOPO" no cabecalho) detectar um MISS num set
    // pertencente ao SDM-SRRIP (miss_srrip_i) ou ao SDM-BRRIP (miss_brrip_i).
    // Se mantido em nivel alto por varios ciclos (contrato de pulso
    // violado), o comportamento e BEM DEFINIDO (nao apenas tolerado): o
    // incremento/decremento correspondente e aplicado a CADA borda de clock
    // enquanto o sinal permanecer alto (o contador simplesmente segue
    // contando/saturando normalmente) -- ao contrario das FSMs multi-ciclo
    // de repl_srrip.v/repl_brrip.v, este modulo nao tem estado transitorio
    // que um pulso sustentado possa corromper.
    input  wire miss_srrip_i,     // miss no SDM-SRRIP -> DECREMENTA o PSEL
    input  wire miss_brrip_i,     // miss no SDM-BRRIP -> INCREMENTA o PSEL

    // ---- decisao de politica para os sets seguidores (combinacional, funcao
    //      direta do MSB corrente de psel_reg -- ver relacao MSB<->politica
    //      no cabecalho do modulo) ------------------------------------------
    //   1 -> seguidores devem usar BRRIP (SRRIP esta performando pior no seu SDM)
    //   0 -> seguidores devem usar SRRIP (BRRIP esta performando pior no seu SDM,
    //        ou -- no reset, antes de qualquer amostragem -- empate resolvido
    //        a favor de SRRIP por construcao do valor de reset, ver acima)
    output wire follower_use_brrip_o,

    // ---- consulta combinacional do valor bruto do contador PSEL (debug/
    //      verificacao) -- mesmo padrao rd_*_i/rd_*_o de cache_addr.v/
    //      repl_lru.v/repl_srrip.v/repl_brrip.v: aqueles modulos expoem o
    //      estado interno (tag/valid/data, MRU/vitima, RRPV cru) por uma
    //      porta de leitura combinacional dedicada em vez de depender de
    //      referencia hierarquica (dut.sinal_interno) no testbench. Este
    //      modulo tem um UNICO registrador de estado (psel_reg, ver
    //      "Storage" abaixo) e nenhum enderecamento associado (o PSEL e
    //      global, nao indexado por via/set) -- por isso a porta de debug
    //      aqui e mais simples que as dos demais modulos (sem entrada
    //      rd_*_i de endereco, so a saida com o valor corrente).
    output wire [PSEL_BITS-1:0] psel_o
);

    // -------------------------------------------------------------------
    // Guarda de elaboracao: PSEL_BITS precisa ser >=2. Motivo (especifico
    // deste modulo, distinto da guarda RRPV_BITS>=1 de repl_srrip.v/
    // repl_brrip.v): com PSEL_BITS==1 o termo `{(PSEL_BITS-1){1'b0}}` do
    // calculo de PSEL_RESET vira uma replicacao de multiplicador ZERO
    // (`{0{1'b0}}`), o mesmo TIPO de idioma (multiplicador de replicacao
    // calculado por parametro chegando a 0/negativo) que repl_srrip.v/
    // repl_brrip.v documentam como fatal nesta toolchain para os SEUS
    // proprios calculos (RRPV_MAX/RRPV_INSERT com RRPV_BITS==0). Alem do
    // risco de ferramenta, PSEL_BITS==1 tambem e semanticamente degenerado
    // para um contador de set-dueling: a faixa colapsaria para {0,1}, sem
    // espaco para acumular evidencia gradual de qual politica esta
    // MISSANDO MENOS (um unico miss em qualquer SDM já levaria o contador a
    // um extremo, eliminando a propria natureza "saturante e gradual" que
    // da ao PSEL sua resistencia a ruido/outliers pontuais -- o proposito
    // central do set-dueling do paper). Por ambos os motivos (risco de
    // ferramenta + perda de significado), PSEL_BITS<2 e bloqueado na
    // elaboracao com a MESMA tecnica ja comprovada nas fases anteriores:
    // instanciar um modulo com nome proposital inexistente dentro de
    // generate/if, forcando erro fatal de resolucao (ModelSim/Questa e
    // Quartus tratam ambos como erro fatal). Os idiomas alternativos
    // (wire[-1:0], localparam com divisao por zero) NAO bloqueiam a
    // elaboracao nesta toolchain -- ja descartados e documentados em
    // repl_srrip.v/repl_brrip.v, nao repetidos aqui.
    //
    // NOTA DE PRECISAO -- ao contrario de repl_srrip.v/repl_brrip.v (que
    // trazem uma nota "VERIFICADO EXPERIMENTALMENTE" afirmando que, para
    // RRPV_BITS==0, o PROPRIO calculo de RRPV_MAX/RRPV_INSERT ja dispara
    // erro fatal de elaboracao ANTES do generate/if ser avaliado -- ver
    // repl_srrip.v em torno da linha 254), a MESMA alegacao NAO se
    // confirma para este modulo com PSEL_BITS==1 (o valor usado pelo teste
    // negativo deste modulo, tb/psel_dueling_guard_neg_tb.v). VERIFICADO
    // EXPERIMENTALMENTE (isolando o modulo completo, com a guarda abaixo
    // temporariamente removida, instanciado com PSEL_BITS=1 e elaborado no
    // ModelSim/Questa 2020.1 via vlog+vsim): a elaboracao completa SEM
    // ERRO (`Errors: 0`). A causa: em repl_srrip.v/repl_brrip.v, o PRIMEIRO
    // termo avaliado, `RRPV_MAX = {RRPV_BITS{1'b1}}`, e uma replicacao de
    // TOPO DE EXPRESSAO atribuida diretamente a um alvo tambem degenerado
    // (`[RRPV_BITS-1:0]` com RRPV_BITS=0 vira `[-1:0]`), o que o
    // ModelSim/Questa rejeita com "Replication multiplier (0) should be
    // greater than zero" / "Negative replication multiplier (-1)" -- a
    // elaboracao ja aborta AQUI, entao o segundo termo (`RRPV_INSERT`,
    // que contem `{(RRPV_BITS-1){1'b0}}` ANINHADO dentro de
    // `{{(RRPV_BITS-1){1'b0}}, 1'b1}`, nao isolado) nunca chega a ser
    // avaliado independentemente -- nao e um segundo mecanismo de defesa,
    // e apenas inalcancado. Ja aqui o termo `{(PSEL_BITS-1){1'b0}}` com PSEL_BITS=1 fica
    // ANINHADO dentro de uma concatenacao maior com um bit valido
    // (`{1'b1, {(PSEL_BITS-1){1'b0}}}`), atribuida a um alvo de largura
    // valida (`[PSEL_BITS-1:0]` com PSEL_BITS=1 vira `[0:0]`, 1 bit) -- uma
    // replicacao de multiplicador ZERO aninhada dessa forma e aceita
    // SILENCIOSAMENTE por esta toolchain (contribui 0 bits a concatenacao),
    // ao contrario da mesma replicacao usada como termo isolado de topo.
    // CONSEQUENCIA: para este modulo, a guarda explicita de generate/if
    // abaixo NAO e defesa em profundidade redundante -- ela e o UNICO
    // mecanismo que efetivamente bloqueia PSEL_BITS==1 nesta toolchain (sem
    // ela, a elaboracao sucederia silenciosamente, com PSEL_RESET calculado
    // de forma degenerada). Isso TAMBEM foi confirmado no mesmo experimento
    // (com a guarda removida, `Errors: 0, Warnings: 0` na elaboracao
    // completa). O teste negativo deste modulo (tb/psel_dueling_guard_neg_tb.v
    // + sim/run_psel_dueling_guard_neg.do) portanto exercita de fato a
    // guarda explicita abaixo, e nao um efeito colateral "de graca" do
    // calculo de PSEL_RESET (diferenca real de comportamento em relacao a
    // repl_srrip.v/repl_brrip.v, registrada aqui para nao insinuar uma
    // verificacao que não se aplica da mesma forma a este modulo).
    // -------------------------------------------------------------------
    generate
        if (PSEL_BITS < 2) begin : g_assert_psel_bits_ge_2
            psel_dueling_requires_psel_bits_ge_2_do_not_instantiate_with_other_config u_psel_bits_guard ();
        end
    endgenerate

    // -------------------------------------------------------------------
    // Storage: um UNICO contador saturante, GLOBAL ao modulo (nao 1 por
    // set -- fiel ao mecanismo do paper, ver cabecalho: o PSEL arbitra a
    // decisao para TODOS os seguidores de uma vez, a partir da evidencia
    // agregada dos SDMs). Reset sincrono inicializa no ponto medio
    // documentado acima (PSEL_RESET).
    // -------------------------------------------------------------------
    reg [PSEL_BITS-1:0] psel_reg;

    always @(posedge clk) begin
        if (rst) begin
            psel_reg <= PSEL_RESET;
        end else begin
            case ({miss_brrip_i, miss_srrip_i})
                2'b10: begin
                    // so miss_brrip_i: incrementa, saturando em PSEL_MAX
                    // (nao faz wraparound -- ao alcancar o teto, permanece
                    // la ate um decremento o mover dali).
                    psel_reg <= (psel_reg == PSEL_MAX) ? PSEL_MAX : (psel_reg + 1'b1);
                end
                2'b01: begin
                    // so miss_srrip_i: decrementa, saturando em PSEL_MIN
                    // (nao faz wraparound -- ao alcancar o piso, permanece
                    // la ate um incremento o mover dali).
                    psel_reg <= (psel_reg == PSEL_MIN) ? PSEL_MIN : (psel_reg - 1'b1);
                end
                2'b11: begin
                    // ambos no MESMO ciclo: CANCELAMENTO -- ver justificativa
                    // completa no cabecalho do modulo ("COMPORTAMENTO EM MISS
                    // SIMULTANEO"). O contador retem seu valor corrente,
                    // tanto em pontos intermediarios da faixa quanto nas
                    // bordas (onde o resultado coincide com o que a
                    // saturacao isolada tambem daria, por coincidencia
                    // aritmetica, nao por serem o mesmo mecanismo).
                    psel_reg <= psel_reg;
                end
                default: begin
                    // 2'b00: nenhum miss neste ciclo -> retem o valor.
                    psel_reg <= psel_reg;
                end
            endcase
        end
    end

    // ---- decisao de politica dos seguidores: negacao do MSB corrente -------
    // (ver "RELACAO MSB <-> POLITICA DOS SEGUIDORES" no cabecalho do modulo
    // para a derivacao completa desta formula).
    assign follower_use_brrip_o = ~psel_reg[PSEL_BITS-1];

    // ---- porta de debug: expõe o valor bruto de psel_reg, combinacional --
    // (ver comentario da porta psel_o na lista de portas acima). Sem
    // registrar nada extra -- e o mesmo reg, so visivel por uma porta em
    // vez de exigir referencia hierarquica no testbench.
    assign psel_o = psel_reg;

endmodule
