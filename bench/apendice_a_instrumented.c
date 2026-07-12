/* ============================================================================
 * apendice_a_instrumented.c
 * PI4 UNIPAMPA - Fase 9 (bench_traces): versao INSTRUMENTADA do Apendice A
 * da especificacao do projeto, usada para GERAR os 4 traces de enderecos
 * consumidos por tb/measure_harness.v (rtl DRRIP vs LRU).
 *
 * Este arquivo NAO faz parte do RTL/testbench Verilog: e um programa C de
 * apoio, compilado e executado no HOST (gcc), cuja UNICA finalidade e
 * reproduzir o PADRAO DE ACESSO A MEMORIA das 4 funcoes de benchmark do
 * Apendice A (run_streaming, run_matrix_conv, run_linked_list,
 * run_pattern_search) e despejar 1 arquivo de trace texto por benchmark,
 * no formato exato que tb/measure_harness.v espera:
 *
 *     <CMD> <ENDERECO_HEX>      (1 acesso por linha, CMD='R' ou 'W',
 *                                 endereco em hex SEM prefixo "0x")
 *
 * ============================================================================
 * REVISAO 2 (esta versao) -- resposta ao veredito REPROVADO do rtl-analyst
 * na 1a submissao da Fase 9
 * ============================================================================
 * A 1a versao deste arquivo (RTL/testbenches/tabela ja corretos, mas ESCALA
 * dos traces errada) foi REPROVADA por 3 motivos, todos sobre a mesma causa
 * raiz -- os traces gerados nao criavam DISPUTA REAL de via em cache:
 *
 *   (1) run_streaming com STREAM_OUTER_ITERS=1 virou um scan de passada
 *       UNICA: hit rate (93.890%) 100% explicado por localidade ESPACIAL
 *       dentro do bloco (~15/16), sem nenhuma decisao de substituicao real
 *       acontecendo (LRU e DRRIP davam o MESMO resultado por nunca serem
 *       forcados a escolher entre 2+ candidatos genuinamente vivos).
 *   (2) run_pattern_search gerava ZERO escritas (0 ocorrencias de '^W' no
 *       trace) -- o ramo de match (`blob[i]==blob[i-j]`) nunca disparava com
 *       o hash+stride da 1a versao, entao o `break`/incremento nunca era
 *       exercitado.
 *   (3) Nenhum dos 8 cenarios (4 benchmarks x 2 configs) demonstrava
 *       qualquer sensibilidade a politica -- 3 de 4 empatavam exatamente
 *       (0.000pp) e o 4o (matrix_conv) so mostrava DRRIP PIOR, tudo
 *       consistente com "trace fraco demais", nao com uma comparacao real.
 *
 * -----------------------------------------------------------------------
 * INSIGHT CENTRAL desta revisao: "tags distintas por set > WAYS" e
 * NECESSARIO mas NAO SUFICIENTE para criar disputa real
 * -----------------------------------------------------------------------
 * Investigando a causa raiz do problema (1): mesmo o benchmark
 * run_linked_list original (Node de 8B, 2000 nos = 16KB, muito maior que a
 * L1 de 4KB) ja fazia, ao longo do trace INTEIRO, ~8 tags distintas
 * visitarem cada set da L1 (2000 nos / 4 nos-por-bloco-L1 / 64 sets ~ 7.8
 * tags/set) -- MUITO mais que WAYS=2. Mesmo assim o hit rate batia
 * IDENTICO entre LRU e DRRIP. Por que? Porque a travessia e um UNICO
 * ponteiro sequencial: o set S so e visitado de novo depois de UMA VOLTA
 * INTEIRA por todos os outros sets -- ou seja, em qualquer instante, existe
 * NO MAXIMO 1 tag "vivo" disputando aquele set; a decisao de vitima nunca
 * tem 2+ candidatos genuinamente recentes para escolher, entao QUALQUER
 * politica (LRU, SRRIP, BRRIP) toma a MESMA decisao trivial ("evictar o
 * unico residente"), nao importa quantas tags DIFERENTES passaram por ali
 * ao longo de todo o trace. "Tags distintas > WAYS" mede se HOUVE
 * candidatos suficientes; o que realmente importa e se esses candidatos
 * chegam ENTRELACADOS NO TEMPO (2+ tags recentes competindo pelo mesmo set
 * na mesma janela de tempo). Por isso esta revisao redesenha cada
 * benchmark para garantir ENTRELACAMENTO real, nao so um working set maior
 * que a cache:
 *
 *   - run_streaming: o mecanismo de HOTSET (endereco fixo hot_data,
 *     tocado a cada 64 elementos) ja entrelacava, por construcao, o
 *     residente "quente" (reuso frequente) com o fluxo "frio" de streaming
 *     que passa pelo MESMO set esporadicamente -- so precisava de um
 *     working set que realmente EXCEDESSE a cache (nao so 2x a L1 E so 1
 *     passada, que e o que a 1a tentativa desta revisao ainda tinha de
 *     errado -- ver nota em STREAM_ARRAY_SIZE abaixo) E de passadas
 *     suficientes para essa disputa se repetir e ser estatisticamente
 *     relevante.
 *   - run_pattern_search: a janela de comparacao (`blob[i]` vs
 *     `blob[i-j]`, j=1..PATTERN_MAX_J-1) ja e por construcao uma disputa
 *     ENTRELACADA (posicao atual vs. janela recente) -- faltava (a) as
 *     escritas de fato acontecerem (blob com alfabeto pequeno demais pra
 *     nunca repetir na janela) e (b) o proprio blob exceder a L2 (ver nota
 *     em PATTERN_BLOB_BYTES abaixo).
 *   - run_matrix_conv: mantido no tamanho estrutural original do Apendice A
 *     (width=128) mas com a altura da "imagem" dimensionada para que o
 *     footprint total exceda a L2 (64KB, ver MATRIX_HEIGHT abaixo), e
 *     adicionado um laco externo de REPETICAO (MATRIX_OUTER_ITERS,
 *     inexistente no Apendice A original) pela MESMA razao do streaming:
 *     sem repeticao sobre o mesmo working set, uma unica passada de
 *     convolucao so tem reuso de curtissimo prazo intra-passada, nunca
 *     disputa entre passadas.
 *   - run_linked_list: redesenhado com 2 CURSORES concorrentes entrelacados
 *     (2 ponteiros percorrendo o MESMO array circular de nos, defasados em
 *     metade da lista, avancando em passos alternados) -- em vez de 1 unico
 *     ponteiro sequencial (que, como explicado acima, NUNCA cria disputa
 *     real nao importa o tamanho do working set). Representa um padrao
 *     realista (2 consumidores percorrendo a mesma estrutura), preserva o
 *     caracter de "ponteiros/saltos de memoria" do benchmark original, e
 *     garante que 2 tags DIFERENTES estejam sempre "recentes" ao mesmo
 *     tempo -- a condicao que realmente importa para criar disputa.
 *
 *   Em TODOS os 4 casos, o footprint final foi calibrado (ver bloco de
 *   ESCALA abaixo) para ~2x a capacidade da L2 real (32KB), nao so da L1
 *   (4KB) -- ja que o MESMO trace e reusado nas simulacoes L1 e L2 (so a
 *   geometria da cache muda), exceder apenas a L1 deixaria a L2 (8x maior,
 *   4x mais associativa) sem nenhuma disputa real, o que uma 1a tentativa
 *   desta revisao (footprints de 8KB) confirmou empiricamente via
 *   analyze_contention(): 0% dos sets da L2 com tags>WAYS em todos os 4
 *   benchmarks, apesar de 100% dos sets da L1 ja passarem no piso minimo.
 *
 * -----------------------------------------------------------------------
 * FERRAMENTA DE VALIDACAO ANTES do ModelSim: contagem de tags distintas
 * por set (analyze_contention(), no fim deste arquivo)
 * -----------------------------------------------------------------------
 * Exatamente como o rtl-analyst pediu: para cada benchmark e para cada
 * config (L1 e L2), este programa recalcula (com a MESMA formula de
 * INDEX/TAG usada em rtl/cache_datapath.v: index_w=log2(SETS),
 * offset_w=log2(BLK_B), tag = addr >> (offset_w+index_w)) quantas tags
 * DISTINTAS visitam cada um dos SETS sets ao longo do trace gerado, e
 * reporta: tags/set MAXIMO, quantos sets tem tags>WAYS (heuristica minima
 * de "ha candidatos suficientes"), e a media de tags/set. Resultado
 * impresso em stdout E salvo em resultados/tag_dispute_analysis.txt --
 * usado para VALIDAR a escala ANTES de rodar as 16 simulacoes de verdade
 * no ModelSim (o proprio numero, por si so, NAO prova entrelacamento
 * temporal -- ver insight acima -- mas serve de piso minimo necessario;
 * o entrelacamento em si vem do DESENHO de cada funcao run_*_instrumented,
 * documentado acima).
 *
 * -----------------------------------------------------------------------
 * O QUE NAO MUDOU em relacao a 1a versao (mantido, ja estava correto)
 * -----------------------------------------------------------------------
 *   - Sem valgrind (nao instalado, fora de escopo instalar).
 *   - Enderecos SINTETICOS deterministicos por BASE+offset (mesmas 5
 *     bases: BASE_ARRAY/BASE_OUT/BASE_HOT/BASE_BLOB/BASE_NODES).
 *   - Node modelado como 8B (4B data + 4B next-ptr), fiel a um alvo RV32.
 *   - Formato do trace ("R"/"W" + endereco hex) inalterado.
 * ============================================================================
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

/* ---- enderecos base sinteticos (deterministicos, nao sao ponteiros reais) */
#define BASE_ARRAY  0x00000000u
#define BASE_OUT    0x00010000u
#define BASE_HOT    0x00020000u
#define BASE_BLOB   0x00030000u
#define BASE_NODES  0x00040000u

#define NODE_SIZE_BYTES 8u   /* 4B data + 4B next-ptr, modelo RV32 */

/* ============================================================================
 * ESCALA (REVISAO 2) -- cada benchmark agora tem suas PROPRIAS constantes de
 * working-set/repeticao (em vez de compartilhar 1 ARRAY_SIZE generico como
 * na v1), calibradas para criar disputa real de via nas configs de entrega
 * (L1: 4KB/32B-bloco/2-way/64 sets; L2: 32KB/64B-bloco/8-way/64 sets), tudo
 * verificado empiricamente com analyze_contention() antes de rodar o
 * ModelSim (ver resultados/tag_dispute_analysis.txt).
 * ============================================================================ */

/* ---- streaming + hotset -------------------------------------------------- */
/* IMPORTANTE: o MESMO trace gerado aqui e reusado tanto na simulacao L1
   quanto na L2 (ver tb/measure_bench_*_l1_*_tb.v / *_l2_*_tb.v -- so a
   GEOMETRIA da cache muda, o trace e identico). Para haver disputa real de
   via nas DUAS configs, o footprint precisa exceder a MAIOR delas (L2,
   32KB) -- exceder so a L1 (4KB) nao e suficiente (deixaria a L2, 8x maior
   e 4x mais associativa, sem nenhuma disputa, como a 1a tentativa desta
   revisao mostrou empiricamente via analyze_contention(), 0% dos sets da
   L2 com tags>WAYS). Por isso o working set abaixo mira ~2x a L2 real. */
#define STREAM_ARRAY_SIZE  16384  /* ints = 64KB: 16x capacidade da L1 (4KB), 2x da L2 (32KB) */
#define STREAM_OUTER_ITERS     3  /* passadas repetidas sobre o MESMO working set (v1 tinha
                                      reduzido p/ 1, o que eliminava toda disputa entre
                                      passadas; original do Apendice A tinha 10 -- 3 preserva
                                      "repeticao suficiente" dentro de um orcamento de
                                      acessos administravel para o footprint maior acima) */

/* ---- matriz/convolucao ---------------------------------------------------- */
#define MATRIX_WIDTH        128  /* igual ao Apendice A original (parametro estrutural do
                                      algoritmo de convolucao, nao um multiplicador de
                                      repeticao) */
#define MATRIX_HEIGHT        128  /* width*height = 16384 ints = 64KB, mesmo footprint (2x L2)
                                      usado em todos os benchmarks nesta revisao, pelo mesmo
                                      motivo documentado acima em STREAM_ARRAY_SIZE */
#define MATRIX_OUTER_ITERS     2  /* NOVO nesta revisao (nao existia no Apendice A original):
                                      sem repetir a passada de convolucao sobre o MESMO
                                      working-set, so ha reuso de curtissimo prazo
                                      intra-passada, nunca disputa entre passadas -- mesma
                                      razao do STREAM_OUTER_ITERS acima */

/* ---- linked list (pointer chasing) ---------------------------------------- */
#define NUM_NODES           8192  /* original: 2000 -- 8192 nos * 8B = 64KB, mesmo footprint
                                      (2x L2) das demais, pelo mesmo motivo acima */
#define LL_LAPS                2  /* numero de voltas completas de CADA cursor pela lista
                                      circular (ver DECISAO DE PROJETO #6 abaixo: motivo de
                                      2 cursores entrelacados em vez de 1 unico ponteiro) */
#define LL_CURSOR_B_OFFSET  (NUM_NODES/2 + 8)  /* REVISAO 3 (achado Medio do rtl-analyst,
                                      rodada 2): offset do cursor B. ERA NUM_NODES/2 (=4096)
                                      puro -- ALGEBRICAMENTE PROVADO travado no MESMO set que
                                      o cursor A o trace INTEIRO nas duas configs (4096/4=1024,
                                      1024 mod 64=0; 4096/8=512, 512 mod 64=0 -- ver prova
                                      completa na DECISAO DE PROJETO #6 abaixo). Corrigido para
                                      NUM_NODES/2 + 8 (=4104), que quebra a congruencia nas
                                      DUAS configs simultaneamente (prova tambem abaixo). */

/* ---- pattern search --------------------------------------------------------*/
#define PATTERN_BLOB_BYTES (64 * 1024)  /* tamanho do blob -- 64KB = 2x a L2 real (32KB); a
                                            1a tentativa desta revisao usava exatamente 32KB
                                            (leitura literal de "blob = L2_SIZE_BYTES" no
                                            Apendice A original) e isso NAO criava nenhuma
                                            disputa de via na propria L2 (blob do MESMO
                                            tamanho da cache nunca a excede) -- corrigido para
                                            2x, mesmo criterio aplicado aos outros 3
                                            benchmarks acima */
#define PATTERN_MAX_J           16     /* original: 64 -- janela de comparacao "olha p/ tras" */
#define PATTERN_I_STRIDE        64     /* original: 1 implicito -- 64 = tamanho de bloco da L2,
                                           passo do laco externo (ver revisao 1 para a
                                           justificativa completa: sem isso o PISO MINIMO de
                                           acessos ja explode para ordem de milhoes) */
#define PATTERN_ALPHABET        12     /* NOVO nesta revisao: tamanho do "alfabeto" do blob
                                           (blob[i] em 0..11, nao 0..255) -- ver DECISAO DE
                                           PROJETO #7 abaixo: garante que o ramo de match
                                           (blob[i]==blob[i-j]) realmente dispare com
                                           frequencia dentro da janela de PATTERN_MAX_J, ao
                                           contrario do hash de alfabeto 0..255 da v1 (que
                                           colidia raramente demais dentro de uma janela de
                                           so 15 comparacoes e gerava 0 escritas) */

/* ============================================================================
 * DECISAO DE PROJETO #6 -- por que linked_list agora usa 2 CURSORES
 * entrelacados em vez de 1 ponteiro sequencial (E por que o offset entre
 * eles teve que ser CORRIGIDO numa 3a revisao -- achado Medio do
 * rtl-analyst na rodada 2 de revisao da Fase 9)
 * ============================================================================
 * Um UNICO ponteiro percorrendo uma lista circular, nao importa o tamanho da
 * lista frente a cache, NUNCA cria disputa real de via: o set S so e
 * revisitado depois de uma volta inteira pelos outros sets, entao ha NO
 * MAXIMO 1 tag "vivo" competindo por aquele set a qualquer instante -- a
 * decisao de vitima e sempre trivial (so ha 1 residente pra evictar),
 * INDEPENDENTE da politica (ver insight central no topo do arquivo; foi
 * exatamente isso que produziu o empate exato 91.667%==91.667% na v1,
 * reprovado). Com 2 CURSORES avancando em passos alternados sobre a MESMA
 * lista circular, a ideia e que a cada instante 2 tags DIFERENTES (a
 * posicao de cada cursor) estejam "recentes" simultaneamente -- a condicao
 * de entrelacamento necessaria para que a escolha de vitima (entre o
 * residente do cursor A e o do cursor B) deixe de ser trivial. Continua
 * sendo fielmente um padrao de "ponteiros/saltos de memoria" (2
 * consumidores percorrendo a mesma estrutura encadeada, um cenario
 * realista, nao um artificio sem relacao com o benchmark original).
 *
 * -----------------------------------------------------------------------
 * BUG ENCONTRADO NA RODADA 2 (offset NUM_NODES/2 puro estava travado no
 * MESMO set o tempo todo, nao desincronizado) -- achado do rtl-analyst,
 * PROVADO algebricamente e CORRIGIDO aqui
 * -----------------------------------------------------------------------
 * A 1a escolha de offset entre os cursores (LL_CURSOR_B_OFFSET = NUM_NODES/2
 * = 4096, "meia lista de distancia") PARECIA razoavel, mas e MATEMATICAMENTE
 * equivalente a nenhuma dessincronizacao: os dois cursores visitam o MESMO
 * set index a CADA instante t, nas DUAS configs, o trace inteiro. Prova:
 *
 *   set(idx) = floor(idx / K) mod SETS, onde K = nodes-por-bloco-de-cache
 *              (K=BLK_B/NODE_SIZE_BYTES: K=4 p/ L1 BLK_B=32, K=8 p/ L2
 *              BLK_B=64) -- ja descontada a contribuicao de BASE_NODES no
 *              indice de set, que e 0 nas duas configs (BASE_NODES=0x40000
 *              e multiplo exato de SETS*BLK_B tanto p/ BLK_B=32 quanto
 *              p/ BLK_B=64).
 *   idx_b(t) = idx_a(t) + OFFSET (mod NUM_NODES)
 *   Se OFFSET e MULTIPLO EXATO de K (garantido quando NUM_NODES e OFFSET
 *   sao ambos multiplos de K, sem nenhuma ambiguidade de arredondamento):
 *       set_b(t) - set_a(t) = (OFFSET/K) mod SETS   -- CONSTANTE p/ todo t.
 *   Com OFFSET=NUM_NODES/2=4096: OFFSET/K = 4096/4=1024 (L1) e
 *   4096/8=512 (L2). 1024 mod 64 = 0. 512 mod 64 = 0. Ou seja
 *   set_b(t)-set_a(t) = 0 SEMPRE, nas DUAS configs -- os cursores NUNCA
 *   disputam sets diferentes ao mesmo tempo; estao em lockstep permanente,
 *   so defasados em FASE (cursor B repete o mesmo ciclo de tags do cursor A
 *   por set, so que "atrasado" NUM_NODES/2 nos = metade das voltas). Sinal
 *   diagnostico batendo com o achado: tag_dispute_analysis.txt mostrava
 *   media 32.00 tags/set (nao maior), consistente com os 2 cursores
 *   compartilhando o MESMO conjunto de 32 blocos-tag por set ao longo do
 *   trace inteiro (ver nota "POR QUE A MEDIA DE TAGS/SET CONTINUA ~32.00
 *   APOS A CORRECAO" mais abaixo -- esse numero especifico NAO muda com o
 *   fix, e isso e ESPERADO, nao um sinal de que o fix nao funcionou).
 *
 * CORRECAO: LL_CURSOR_B_OFFSET = NUM_NODES/2 + 8 = 4104 (era so NUM_NODES/2).
 * Ainda multiplo de K nas DUAS configs (4104 e multiplo de 4 E de 8, ja que
 * e multiplo de mmc(4,8)=8), preservando a formula fechada acima (sem
 * ambiguidade de fase, deslocamento CONSTANTE garantido p/ todo t):
 *   L1 (K=4): OFFSET/K = 4104/4 = 1026.  1026 mod 64 = 2   (!= 0)
 *   L2 (K=8): OFFSET/K = 4104/8 = 513.   513  mod 64 = 1   (!= 0)
 * Ou seja, com a correcao, o cursor B esta SEMPRE exatamente 2 sets a
 * frente do cursor A na L1, e SEMPRE exatamente 1 set a frente na L2 --
 * dessincronizacao real, constante, provada, e valida para o trace INTEIRO
 * (nao so "na maioria das vezes"): a cada tick, os 2 cursores agora
 * genuinamente disputam sets DIFERENTES entre si (nunca o mesmo), o que
 * significa que, conforme cada cursor completa seu proprio ciclo pelos 64
 * sets, um dado set S passa a ser visitado por A e por B em MOMENTOS
 * DIFERENTES (nao mais no mesmo tick) -- essa dessincronizacao temporal e
 * o que cria a condicao de entrelacamento real entre os dois "fluxos" de
 * tags dentro de um mesmo set ao longo do tempo.
 *
 * POR QUE A MEDIA DE TAGS/SET CONTINUA ~32.00 APOS A CORRECAO (nao dobra
 * para ~64.00): os dois cursores percorrem a MESMA lista circular
 * subjacente (nao 2 listas/arrays distintos) -- ao longo de laps
 * suficientes, cada cursor SOZINHO ja visita TODOS os NUM_NODES nos, logo
 * todos os blocos-tag de qualquer set S, independente do offset de fase
 * entre eles. O conjunto de tags DISTINTAS que um set S ve ao longo do
 * trace inteiro e uma propriedade de NUM_NODES/K (quantos blocos existem
 * no total, mod SETS), NAO de quantos cursores o percorrem nem do offset
 * de fase entre eles -- so o INSTANTE em que cada tag chega muda com o
 * fix, nao QUAIS tags chegam. Por isso a media de tags/set nao e a metrica
 * que prova o fix (ela e cega a tempo, so conta "visitou alguma vez") --
 * quem prova o fix e a analise algebrica acima (contagem de sets), e o
 * resultado empirico de hit rate antes/depois documentado no relatorio de
 * entrega (resultados/hit_rate_comparativo.md).
 *
 * DECISAO DE PROJETO #7 -- blob de alfabeto pequeno (0..11) em vez de hash
 * de 8 bits pleno (0..255)
 * ============================================================================
 * A v1 usava blob[i] = hash(i) & 0xFF (256 valores possiveis). Com uma
 * janela de comparacao de so PATTERN_MAX_J-1=15 posicoes, a chance de
 * blob[i] coincidir com ALGUM dos 15 valores da janela era baixa (~15/256
 * ~ 5.5% por tentativa acumulada, na pratica 0 escritas observadas no
 * trace gerado). Reduzindo o alfabeto para PATTERN_ALPHABET=12 valores
 * possiveis (blob[i] = hash(i) % 12), a mesma janela de 15 comparacoes tem
 * chance de colisao bem mais alta (estimativa ~1-(11/12)^15 ~ 71% por
 * posicao) -- o ramo de match/escrita passa a disparar na MAIORIA das
 * iteracoes externas, exercitando de fato o `break`/incremento, mantendo a
 * inicializacao 100% DETERMINISTICA (mesmo hash multiplicativo de semente
 * fixa da v1, so com o modulo reduzido).
 * ============================================================================ */

/* ---- registro de trace (arquivo texto) + captura em memoria (para a
 *      analise de disputa de tags, ver analyze_contention() no fim) -------- */
static FILE     *g_trace;
static long      g_count;
static uint32_t *g_addr_buf = NULL;
static long      g_addr_cap = 0;

static void rec(char cmd, uint32_t addr) {
    fprintf(g_trace, "%c %08X\n", cmd, addr);
    if (g_count >= g_addr_cap) {
        g_addr_cap = g_addr_cap ? g_addr_cap * 2 : 4096;
        g_addr_buf = (uint32_t *)realloc(g_addr_buf, (size_t)g_addr_cap * sizeof(uint32_t));
    }
    g_addr_buf[g_count] = addr;
    g_count++;
}
#define REC_R(addr) rec('R', (uint32_t)(addr))
#define REC_W(addr) rec('W', (uint32_t)(addr))

static void trace_open(const char *path) {
    g_trace = fopen(path, "w");
    if (!g_trace) {
        fprintf(stderr, "ERRO: nao foi possivel abrir '%s' para escrita\n", path);
        exit(1);
    }
    g_count = 0; /* g_addr_buf/g_addr_cap persistem e sao reaproveitados entre benchmarks */
}

static long trace_close(void) {
    fclose(g_trace);
    g_trace = NULL;
    return g_count;
}

/* ============================================================================
 * run_streaming -- Streaming + HotSet (antagonista ao LRU)
 * Estrutura IDENTICA ao original: `array[i] += i;` (R+W no mesmo endereco) e,
 * a cada 64 elementos, `*hot_data += array[i];` (R hot, R array[i], W hot).
 * Working set (STREAM_ARRAY_SIZE) e repeticoes (STREAM_OUTER_ITERS) ver bloco
 * de ESCALA acima.
 * ============================================================================ */
static void run_streaming_instrumented(void) {
    uint32_t array_addr, hot_addr = BASE_HOT;
    int it, i;

    for (it = 0; it < STREAM_OUTER_ITERS; it++) {
        for (i = 0; i < STREAM_ARRAY_SIZE; i++) {
            array_addr = BASE_ARRAY + (uint32_t)i * 4u;

            /* array[i] += i; */
            REC_R(array_addr);
            REC_W(array_addr);

            if (i % 64 == 0) {
                /* *hot_data += array[i]; */
                REC_R(hot_addr);
                REC_R(array_addr);
                REC_W(hot_addr);
            }
        }
    }
}

/* ============================================================================
 * run_matrix_conv -- Convolucao 2D (reuso em janela)
 * Estrutura de acesso IDENTICA ao original (3 leituras de img + 1 escrita em
 * out por pixel interno); MATRIX_WIDTH/HEIGHT reduzidos e MATRIX_OUTER_ITERS
 * (repeticao da passada inteira, NOVO nesta revisao) adicionados -- ver bloco
 * de ESCALA acima.
 * ============================================================================ */
static void run_matrix_conv_instrumented(void) {
    const int width  = MATRIX_WIDTH;
    const int height = MATRIX_HEIGHT;
    int rep, y, x;

    for (rep = 0; rep < MATRIX_OUTER_ITERS; rep++) {
        for (y = 1; y < height - 1; y++) {
            for (x = 1; x < width - 1; x++) {
                uint32_t a_up   = BASE_ARRAY + (uint32_t)((y - 1) * width + x) * 4u;
                uint32_t a_mid  = BASE_ARRAY + (uint32_t)(y * width + x) * 4u;
                uint32_t a_down = BASE_ARRAY + (uint32_t)((y + 1) * width + x) * 4u;
                uint32_t o_addr = BASE_OUT   + (uint32_t)(y * width + x) * 4u;

                REC_R(a_up);
                REC_R(a_mid);
                REC_R(a_down);
                REC_W(o_addr);
            }
        }
    }
}

/* ============================================================================
 * run_linked_list -- Ponteiros/saltos de memoria (2 CURSORES entrelacados,
 * ver DECISAO DE PROJETO #6). Lista circular unica de NUM_NODES nos
 * (nodes[i].next=&nodes[i+1], ultimo->primeiro, IDENTICO ao encadeamento do
 * Apendice A original); cursor A comeca no no 0, cursor B comeca no no
 * LL_CURSOR_B_OFFSET (=NUM_NODES/2+8, ver prova de dessincronizacao real na
 * DECISAO DE PROJETO #6 -- NAO e mais NUM_NODES/2 puro, que provou-se
 * travado no mesmo set o tempo todo) -- ambos avancam 1 no por "tick",
 * intercalados (A, B, A, B...).
 * ============================================================================ */
static void run_linked_list_instrumented(void) {
    int curr_a = 0;
    int curr_b = LL_CURSOR_B_OFFSET % NUM_NODES;
    long total_ticks = (long)NUM_NODES * LL_LAPS;
    long t;

    for (t = 0; t < total_ticks; t++) {
        uint32_t node_a  = BASE_NODES + (uint32_t)curr_a * NODE_SIZE_BYTES;
        uint32_t data_a  = node_a + 0u;
        uint32_t next_a  = node_a + 4u;

        uint32_t node_b  = BASE_NODES + (uint32_t)curr_b * NODE_SIZE_BYTES;
        uint32_t data_b  = node_b + 0u;
        uint32_t next_b  = node_b + 4u;

        /* cursor A: curr->data += i; curr = curr->next; */
        REC_R(data_a);
        REC_W(data_a);
        REC_R(next_a);

        /* cursor B (entrelacado, mesmo tick): curr->data += i; curr = curr->next; */
        REC_R(data_b);
        REC_W(data_b);
        REC_R(next_b);

        curr_a = (curr_a + 1) % NUM_NODES;
        curr_b = (curr_b + 1) % NUM_NODES;
    }
}

/* ============================================================================
 * run_pattern_search -- Pattern Search (estresse de L2 unificada)
 * blob inicializado deterministicamente com alfabeto PEQUENO (DECISAO #7),
 * garantindo que o ramo de match dispare de fato. Laco externo com
 * PATTERN_I_STRIDE (=64, ver revisao 1); laco interno com janela
 * PATTERN_MAX_J (=16). Mesma logica de match: blob[i]==blob[i-j] ->
 * blob[i]++ (R+W) e break.
 * ============================================================================ */
static void run_pattern_search_instrumented(void) {
    static uint8_t blob[PATTERN_BLOB_BYTES];
    int i, j;

    /* hash multiplicativo deterministico (semente fixa), alfabeto reduzido
       (ver DECISAO DE PROJETO #7) -- em vez de memoria nao inicializada (UB
       no Apendice A original). */
    for (i = 0; i < PATTERN_BLOB_BYTES; i++) {
        blob[i] = (uint8_t)(((uint32_t)i * 2654435761u) >> 24) % PATTERN_ALPHABET;
    }

    for (i = 1024; i < PATTERN_BLOB_BYTES; i += PATTERN_I_STRIDE) {
        uint32_t addr_i = BASE_BLOB + (uint32_t)i;
        for (j = 1; j < PATTERN_MAX_J; j++) {
            uint32_t addr_ij = BASE_BLOB + (uint32_t)(i - j);

            REC_R(addr_i);
            REC_R(addr_ij);

            if (blob[i] == blob[i - j]) {
                blob[i]++;
                REC_W(addr_i);
                break;
            }
        }
    }
}

/* ============================================================================
 * analyze_contention -- ferramenta de VALIDACAO pedida pelo rtl-analyst:
 * conta, para os enderecos capturados de um benchmark (g_addr_buf[0..n-1]),
 * quantas tags DISTINTAS visitam cada um dos SETS sets ao longo do trace,
 * usando a MESMA formula de INDEX/TAG de rtl/cache_datapath.v (index a
 * partir dos bits [offset_w +: index_w] do endereco, tag = o restante).
 * Reporta max tags/set, quantos sets tem tags>WAYS (piso minimo necessario
 * -- ver insight central no topo do arquivo) e a media de tags/set.
 * ============================================================================ */
static int ilog2_pow2(int v) {
    int r = 0;
    while (v > 1) { v >>= 1; r++; }
    return r;
}

static void analyze_contention(const char *bench_name, const uint32_t *addrs, long n,
                                const char *cfg_name, int blk_b, int sets, int ways,
                                FILE *report) {
    int offset_w = ilog2_pow2(blk_b);
    int index_w  = ilog2_pow2(sets);
    uint32_t **tags = (uint32_t **)calloc((size_t)sets, sizeof(uint32_t *));
    int *counts    = (int *)calloc((size_t)sets, sizeof(int));
    int *caps      = (int *)calloc((size_t)sets, sizeof(int));
    long i;
    int s, max_tags = 0, sets_over_ways = 0;
    long sum_tags = 0;

    for (i = 0; i < n; i++) {
        uint32_t a   = addrs[i];
        uint32_t idx = (a >> offset_w) & (uint32_t)(sets - 1);
        uint32_t tag = a >> (offset_w + index_w);
        int found = 0;
        for (int k = 0; k < counts[idx]; k++) {
            if (tags[idx][k] == tag) { found = 1; break; }
        }
        if (!found) {
            if (counts[idx] == caps[idx]) {
                caps[idx] = caps[idx] ? caps[idx] * 2 : 8;
                tags[idx] = (uint32_t *)realloc(tags[idx], (size_t)caps[idx] * sizeof(uint32_t));
            }
            tags[idx][counts[idx]++] = tag;
        }
    }

    for (s = 0; s < sets; s++) {
        if (counts[s] > max_tags) max_tags = counts[s];
        if (counts[s] > ways) sets_over_ways++;
        sum_tags += counts[s];
        free(tags[s]);
    }
    free(tags);
    free(counts);
    free(caps);

    printf("  %-16s %-4s SETS=%3d WAYS=%2d BLK_B=%3d : max_tags/set=%4d  sets_com_tags>WAYS=%3d/%3d (%.1f%%)  media_tags/set=%.2f\n",
           bench_name, cfg_name, sets, ways, blk_b, max_tags, sets_over_ways, sets,
           100.0 * sets_over_ways / sets, (double)sum_tags / sets);
    fprintf(report, "%-16s %-4s SETS=%3d WAYS=%2d BLK_B=%3d : max_tags/set=%4d  sets_com_tags>WAYS=%3d/%3d (%.1f%%)  media_tags/set=%.2f\n",
            bench_name, cfg_name, sets, ways, blk_b, max_tags, sets_over_ways, sets,
            100.0 * sets_over_ways / sets, (double)sum_tags / sets);
}

/* ============================================================================
 * main -- roda cada benchmark isoladamente (sem menu interativo), gera 1
 * trace por benchmark em tb/traces/, e valida a disputa de via (tags/set)
 * em L1 e L2 ANTES de qualquer simulacao RTL.
 * ============================================================================ */
int main(void) {
    long n;
    FILE *report = fopen("resultados/tag_dispute_analysis.txt", "w");
    if (!report) {
        fprintf(stderr, "ERRO: nao foi possivel abrir resultados/tag_dispute_analysis.txt\n");
        return 1;
    }
    fprintf(report,
        "Analise de disputa de via (tags distintas por set) -- Fase 9, revisao 2\n"
        "Config L1: ADDR_W=32 BLK_B=32 SETS=64 WAYS=2\n"
        "Config L2: ADDR_W=32 BLK_B=64 SETS=64 WAYS=8\n"
        "'sets_com_tags>WAYS' = piso minimo necessario (NAO suficiente sozinho -- ver\n"
        "insight central no cabecalho de bench/apendice_a_instrumented.c) para que a\n"
        "politica de substituicao tenha, em algum momento, mais candidatos vivos do\n"
        "que vias disponiveis naquele set.\n\n");

    printf("Analise de disputa de via (tags distintas por set):\n");

    trace_open("tb/traces/bench_streaming.txt");
    run_streaming_instrumented();
    n = trace_close();
    printf("bench_streaming.txt      : %ld acessos\n", n);
    analyze_contention("streaming", g_addr_buf, n, "L1", 32, 64, 2, report);
    analyze_contention("streaming", g_addr_buf, n, "L2", 64, 64, 8, report);

    trace_open("tb/traces/bench_matrix_conv.txt");
    run_matrix_conv_instrumented();
    n = trace_close();
    printf("bench_matrix_conv.txt    : %ld acessos\n", n);
    analyze_contention("matrix_conv", g_addr_buf, n, "L1", 32, 64, 2, report);
    analyze_contention("matrix_conv", g_addr_buf, n, "L2", 64, 64, 8, report);

    trace_open("tb/traces/bench_linked_list.txt");
    run_linked_list_instrumented();
    n = trace_close();
    printf("bench_linked_list.txt    : %ld acessos\n", n);
    analyze_contention("linked_list", g_addr_buf, n, "L1", 32, 64, 2, report);
    analyze_contention("linked_list", g_addr_buf, n, "L2", 64, 64, 8, report);

    trace_open("tb/traces/bench_pattern_search.txt");
    run_pattern_search_instrumented();
    n = trace_close();
    printf("bench_pattern_search.txt : %ld acessos\n", n);
    analyze_contention("pattern_search", g_addr_buf, n, "L1", 32, 64, 2, report);
    analyze_contention("pattern_search", g_addr_buf, n, "L2", 64, 64, 8, report);

    fclose(report);
    printf("\nRelatorio de disputa de via salvo em resultados/tag_dispute_analysis.txt\n");

    return 0;
}
