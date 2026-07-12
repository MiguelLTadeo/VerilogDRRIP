# Hit rate comparativo — LRU vs DRRIP (Fase 9)

PI4 UNIPAMPA — cache RTL DRRIP vs LRU. Tabela de entrega da Fase 9 (bench_traces
+ run comparativo), inspirada na estrutura do Apêndice B da especificação,
porém **restrita à métrica de hit rate** (Área/Fmax/Latência de decisão são de
síntese FPGA, fora de escopo deste projeto — ver `plano-cache.md`, seção "Fora
de escopo").

Todas as 16 combinações (4 benchmarks × 2 configs × 2 políticas) foram
**executadas de fato** via `vsim -c` (ModelSim, Intel FPGA Starter Edition
2020.1), contra os traces da **revisão 3** de `bench/apendice_a_instrumented.c`
(revisão 2 corrigiu a reprovação inicial do rtl-analyst — working sets fracos
demais/pattern_search sem escritas; revisão 3 corrigiu um achado Médio da
rodada seguinte de revisão — os 2 cursores da linked_list estavam
matematicamente travados no mesmo set, ver seção dedicada abaixo. Ver
histórico do arquivo e `resultados/tag_dispute_analysis.txt` para a
evidência de disputa real de via). 0 erros, 0 warnings, `RESULTADO: PASS` em
todas as 16 rodadas. Logs completos em
`resultados/logs/run_measure_bench_*.log`.

Políticas: **LRU** = `repl_lru_nway.v` (matricial). **DRRIP** = `repl_drrip.v`
com os parâmetros de **fábrica**, fiéis ao paper (Jaleel et al., ISCA 2010):
`RRPV_BITS=2`, `BRRIP_THROTTLE_BITS=5` (1/32), `PSEL_BITS=10`,
`SDM_SEL_BITS=4` (1/16 dos sets para cada lado do set-dueling, SETS=64 nas
duas configs — sets {0,16,32,48}=SDM-SRRIP, sets {15,31,47,63}=SDM-BRRIP,
demais 56 sets = seguidores).

Configs (Apêndice B): **L1** = 4KB, bloco 32B, 2-way (ADDR_W=32, BLK_B=32,
SETS=64, WAYS=2). **L2** = 32KB, bloco 64B, 8-way (ADDR_W=32, BLK_B=64,
SETS=64, WAYS=8).

## Validação metodológica desta análise

Além da execução real no ModelSim (evidência primária), esta revisão do
relatório usa um **modelo de software bit-exato** (`replay_model.py`,
reimplementação em Python, linha a linha, das regras documentadas em
`rtl/repl_lru_nway.v`/`rtl/repl_srrip.v`/`rtl/repl_drrip.v`/
`rtl/psel_dueling.v`) para investigar os fenômenos abaixo com granularidade
que os `$display` do testbench não expõem (contagem de hit/miss **por set
individual**, e separação dos votos do PSEL por SDM). O modelo foi
**validado cruzado contra os 16 resultados reais do vsim antes de ser usado
para qualquer conclusão**: hits/misses agregados do modelo bateram
**exatamente (bit a bit)** com os 16 logs reais em todas as 16 combinações
(nenhuma divergência) — evidência forte de que tanto o modelo quanto o
próprio RTL estão corretos, e que as explicações abaixo refletem o
mecanismo real do hardware, não uma interpretação aproximada.

## Tabela única (benchmark × config × política)

| Benchmark | Config | Acessos | Hit Rate LRU | Hit Rate DRRIP | Impacto (pp) | Impacto (%rel.) |
|---|---|---:|---:|---:|---:|---:|
| Streaming + HotSet | L1 | 100608 | 93.892% | 93.892% | 0.000 | 0.000% |
| Streaming + HotSet | L2 | 100608 | 96.946% | 96.946% | 0.000 | 0.000% |
| Convolução 2D (matrix_conv) | L1 | 127008 | 93.600% | 93.441% | **-0.159** | -0.170% |
| Convolução 2D (matrix_conv) | L2 | 127008 | 96.800% | 96.645% | **-0.155** | -0.160% |
| Linked List (2 cursores) | L1 | 98304 | 91.667% | 91.667% | 0.000 | 0.000% |
| Linked List (2 cursores) | L2 | 98304 | 95.833% | 95.833% | 0.000 | 0.000% |
| Pattern Search | L1 | 14235 | 85.838% | 85.838% | 0.000 | 0.000% |
| Pattern Search | L2 | 14235 | 92.912% | 92.912% | 0.000 | 0.000% |

"Impacto" = Hit Rate DRRIP − Hit Rate LRU (pontos percentuais e variação
relativa). Valor negativo = DRRIP pior que LRU nesse cenário.

## Evidência de disputa real de via (pré-requisito de validade destes números)

Todos os 4 traces foram calibrados (revisão 2, working sets de ~64KB, 2x a
L2 real) para garantir disputa genuína de via — não apenas "tags distintas
por set > WAYS" (necessário, mas não suficiente por si só, ver cabeçalho de
`bench/apendice_a_instrumented.c`), mas tags **entrelaçadas no tempo**. Piso
mínimo confirmado (`resultados/tag_dispute_analysis.txt`): **100% dos sets,
em L1 E em L2, veem mais tags distintas que WAYS, nos 4 benchmarks** — sem
isso, um empate exato entre LRU e DRRIP seria suspeito de trace fraco (como
ocorreu na 1ª submissão, reprovada); com isso confirmado, os empates exatos
documentados abaixo são investigados e explicados como um resultado real do
mecanismo, não como ausência de disputa.

## Por que 3 dos 4 benchmarks empatam EXATAMENTE (LRU == DRRIP, bit a bit)

Esta seção responde à investigação pedida: o empate nos 3 casos (streaming,
linked_list, pattern_search) foi verificado em **dois níveis** com o modelo
de software, e a causa raiz é a MESMA nos dois níveis — ambas as políticas
tomam, acesso a acesso, a **mesma decisão de vítima**, não porque a disputa
esteja ausente, mas porque a estrutura destes 3 benchmarks faz LRU e
RRIP-baseado convergirem para o mesmo veredito.

### Nível 1 — o PSEL preso perto do reset (512) é esperado, não é bug

Contagem real de votos (misses observados nos sets SDM dedicados,
extraída do modelo, idêntica à lógica de `psel_dueling.v`):

| Benchmark | Config | Misses SDM-SRRIP | Misses SDM-BRRIP | Diferença | PSEL final |
|---|---|---:|---:|---:|---:|
| streaming | L1 | 385 | 384 | -1 | 511 |
| streaming | L2 | 193 | 192 | -1 | 511 |
| linked_list | L1 | 512 | 512 | **0 (empate exato)** | 512 |
| linked_list | L2 | 256 | 256 | **0 (empate exato)** | 512 |
| pattern_search | L1 | 126 | 126 | **0 (empate exato)** | 512 |
| pattern_search | L2 | 63 | 64 | +1 | 513 |
| matrix_conv | L1 | 508 | 534 | **+26** | 538 |
| matrix_conv | L2 | 254 | 283 | **+29** | 541 |

**Confirmação (pergunta 1 do coordenador):** o mapeamento SDM está correto
e os votos ESTÃO sendo contabilizados — a prova é que o modelo de software,
que implementa a MESMA regra de mapeamento/voto de `repl_drrip.v`/
`psel_dueling.v` de forma independente, reproduz o `PSEL final` reportado
pelo vsim exatamente (511↔511, 512↔512, 513↔513). O PSEL ficar perto do
reset em streaming/linked_list/pattern_search é o comportamento CORRETO do
mecanismo: SRRIP puro e BRRIP puro estão genuinamente missando a taxas
quase idênticas nesses 3 workloads (diferença de 0 a 1 miss em centenas de
votos) — não há sinal para o set-dueling arbitrar, e o PSEL CORRETAMENTE se
recusa a convergir para um lado. Em contraste, matrix_conv mostra um
desequilíbrio real e consistente (+26/+29, SDM-BRRIP sempre missando mais
que SDM-SRRIP) — é esse desequilíbrio que move o PSEL para >512 e explica
por que só matrix_conv produz uma diferença agregada (ver seção seguinte).

**Por que SRRIP e BRRIP empatam em votos nesses 3 benchmarks:** os padrões
de acesso de streaming/linked_list/pattern_search, nesta escala, são
varreduras estruturalmente uniformes e de reuso essencialmente nulo dentro
de cada set (blocos entram, nunca são reacessados antes de sair, thrashing
quase puro por set — ver também a seção de disputa por set abaixo). Quando
uma linha é inserida e será evictada no PRÓXIMO miss daquele set de
qualquer forma (sem nenhum hit entre a inserção e a evicção), o valor de
inserção (MID=2 do SRRIP vs FAR=3 do BRRIP-comum) não muda o resultado
observável — os dois só adiam por 1 rodada de aging interna (invisível do
lado de fora, sem efeito em hit/miss) qual via é escolhida, mas SEMPRE a
MESMA via (a única "outra" via do set 2-way, ou a mais antiga do set
8-way). Esse é o motivo estrutural de SRRIP e BRRIP produzirem
estatisticamente a mesma contagem de misses no SDM, e por extensão o motivo
de LRU (que evictaria essa mesma via por recência, pela mesma ausência de
reuso) empatar com DRRIP no agregado.

### Nível 2 — o set 0 (onde `hot_data` mora) isolado: LRU e SRRIP tomam a MESMA decisão, sempre

Resposta direta à pergunta 2 do coordenador. `BASE_HOT=0x00020000` mapeia
para o **set 0**, que é justamente um dos 4 sets fixos SDM-SRRIP — ou seja,
esse set roda SRRIP puro o tempo todo, independente do PSEL (nunca é
seguidor). Isolando hits/misses SÓ desse set (streaming, L1, n=3168 acessos
àquele set específico):

| Set 0 isolado | LRU | DRRIP (=SRRIP puro nesse set) |
|---|---:|---:|
| hits | 3071 | 3071 |
| Hit Rate | 96.938% | 96.938% |

**Idêntico, acesso a acesso — não é um efeito pequeno demais para aparecer
na média, é ausência real de divergência.** Verificado de forma ainda mais
direta: comparando a contagem de misses por set entre LRU e DRRIP em TODOS
os 64 sets de cada config, **0 de 64 sets divergem** em streaming,
linked_list e pattern_search (nas duas configs) — nenhum set, não só o 0,
produz uma decisão diferente entre as duas políticas nesses 3 benchmarks.

**Por quê:** a colisão estrutural hot_data-vs-array existe (confirmada), mas
a frequência de retorno é assimétrica o suficiente para que a disputa nunca
seja "de verdade" ambígua. `hot_data` é tocado a cada 64 elementos do
streaming; o set 0 só volta a receber uma NOVA linha do array a cada 512
elementos (8x mais raro, já que streaming varre os 64 sets em rodízio e o
set 0 só reaparece depois de uma volta inteira). Ou seja, entre duas visitas
consecutivas do array ao set 0, `hot_data` já foi retocado ~8 vezes — em
QUALQUER política minimamente sensível a recência/reuso (LRU por
definição, e SRRIP porque hit sempre zera o RRPV), a via de `hot_data` está
sempre "quente" demais para ser escolhida vítima quando o array finalmente
volta a bater naquele set; a vítima é sempre a via do array (a única
genuinamente fria). Existe disputa real (2 vias competindo, não um
descarte trivial de residente único como no bug da linked_list original),
mas o VEREDITO da disputa nunca é ambíguo o bastante para separar LRU de
SRRIP nesse desenho específico de endereçamento.

## linked_list: achado Médio da rodada 2 (2 cursores travados no mesmo set) — investigado e corrigido

Antes de aceitar o empate exato do linked_list como "regime sem
sensibilidade real" (mesma explicação dos outros 2 casos), o rtl-analyst
apontou um problema estrutural real nos "2 cursores entrelaçados": o offset
original entre eles (`NUM_NODES/2`, "meia lista de distância") **parecia**
desincronizar os cursores, mas é algebricamente equivalente a nenhuma
dessincronização — prova (ver `bench/apendice_a_instrumented.c`, DECISÃO DE
PROJETO #6, para a versão completa):

```
set(idx) = floor(idx / K) mod SETS,  K = nodes-por-bloco (4 na L1, 8 na L2)
idx_b(t) = idx_a(t) + OFFSET (mod NUM_NODES)
OFFSET múltiplo exato de K  =>  set_b(t) - set_a(t) = (OFFSET/K) mod SETS   (constante p/ todo t)

OFFSET = NUM_NODES/2 = 4096:
  L1: 4096/4 = 1024;  1024 mod 64 = 0  ->  set_b(t) == set_a(t) SEMPRE
  L2: 4096/8 = 512;   512  mod 64 = 0  ->  set_b(t) == set_a(t) SEMPRE
```

Ou seja, os 2 cursores nunca disputavam sets diferentes ao mesmo tempo —
lockstep permanente, só defasados em fase (cursor B repetindo o mesmo ciclo
de tags do cursor A, "atrasado" meia lista). Consistente com o sinal
diagnóstico que o rtl-analyst identificou: `tag_dispute_analysis.txt` já
mostrava média 32.00 tags/set (não maior) para linked_list.

**Correção**: `LL_CURSOR_B_OFFSET = NUM_NODES/2 + 8 = 4104` (ainda múltiplo
de K nas duas configs, preservando a fórmula fechada acima, sem
ambiguidade de fase):

```
L1: 4104/4 = 1026;  1026 mod 64 = 2   (!= 0)  -> cursor B SEMPRE 2 sets à frente de A
L2: 4104/8 = 513;   513  mod 64 = 1   (!= 0)  -> cursor B SEMPRE 1 set à frente de A
```

Dessincronização real, constante e provada, válida para o trace inteiro nas
duas configs simultaneamente. O trace foi regerado (só `bench_linked_list.txt`
mudou — confirmado por hash: os outros 3 traces ficaram byte-idênticos) e as
4 combinações (L1/L2 × LRU/DRRIP) foram rodadas de novo no vsim.

**Resultado**: o empate exato **persiste, bit a bit** (LRU e DRRIP:
90112 hits / 8192 misses em L1, 94208 hits / 4096 misses em L2 — idêntico
aos números pré-correção). Verificado com o modelo de software: PSEL final
ainda exatamente balanceado (SDM-SRRIP=512 vs SDM-BRRIP=512 em L1; 256 vs
256 em L2) e **0 de 64 sets** divergem entre LRU e DRRIP nas duas configs,
mesmo com a dessincronização real confirmada.

**Nota sobre a força desta evidência (revisão do rtl-analyst)**: o lado LRU
da igualdade bit-a-bit (90112/8192 e 94208/4096, idênticos antes e depois
da correção) não é, por si só, uma confirmação empírica independente —
para uma lista circular homogênea sem estrutura tipo `hot_data`, o
agregado de hits do LRU é matematicamente invariante por qualquer offset
múltiplo de K (a decisão de vítima do LRU não depende do índice absoluto
do set, só do padrão local de chegada; um offset alinhado a bloco apenas
permuta QUAL set recebe qual fatia do padrão, sem mudar o agregado). Essa
parte da igualdade era, portanto, esperada de qualquer forma, com ou sem
sincronização acidental.

A evidência que de fato decide a questão é a checagem **per-set** (não o
agregado): **0 de 64 sets** divergem entre LRU e DRRIP nas duas configs,
sob o offset corrigido — essa comparação é entre duas políticas diferentes
rodando sobre o MESMO trace dessincronizado, então não sofre do problema
de simetria acima, e é o que sustenta a tese de "regime sem sensibilidade
real": mesmo com os 2 cursores genuinamente competindo por sets diferentes
a cada instante (não mais um artefato de sincronização), cada set individual
continua sendo, na prática, um padrão de chegadas esparsas sem reuso entre
inserção e evicção — a mesma condição estrutural que já explica o empate em
streaming/pattern_search (ver Nível 1 acima): sem nenhum hit entre a
inserção de uma linha e sua evicção, o valor de inserção (MID do SRRIP vs
FAR do BRRIP) não muda qual via é escolhida, e LRU concorda pela mesma
ausência de reuso. A média de tags/set em `tag_dispute_analysis.txt`
continua 32.00/16.00 após a correção (não dobra) — isso também é esperado,
não um sinal de falha do fix: os 2 cursores percorrem a MESMA lista
circular subjacente, então o conjunto de tags que um set vê ao longo do
trace inteiro é determinado por `NUM_NODES/K` (quantos blocos existem no
total), não pelo offset de fase entre os cursores — o offset muda QUANDO
cada tag chega (o que afeta hit/miss), não QUAIS tags chegam (o que essa
métrica mede). A prova de que o fix funcionou é a álgebra acima + a
checagem per-set (0/64 divergem), não a igualdade do agregado por si.

## matrix_conv: onde a diferença REAL vem, quantificada set a set

A diferença agregada de -0.159pp (L1) vem inteiramente de **15 sets
específicos** (de 64) que divergem entre LRU e DRRIP — os demais 49 sets
empatam exatamente, mesmo padrão dos outros 3 benchmarks:

| Sets divergentes (L1) | Papel | LRU misses (cada) | DRRIP misses (cada) |
|---|---|---:|---:|
| 17,19,21,23,25,27,29 (7 sets) | seguidor | 128 | 143 (+15 cada) |
| 18,20,22,24,26,28,30 (7 sets) | seguidor | 128 | 138 (+10 cada) |
| 31 (1 set) | SDM-BRRIP (fixo) | 128 | 154 (+26) |

Soma dos excessos de miss nesses 15 sets = **203**, que bate EXATO com a
diferença agregada de misses (DRRIP 8331 − LRU 8128 = 203) — toda a
diferença do benchmark vem só desses 15 sets, nada dos outros 49.

Isso reforça e refina a hipótese já registrada: os 14 sets seguidores
divergentes (17–30) receberam um pequeno número de inserções sob a regra
BRRIP (226 fills no total, medido pelo modelo) durante uma janela **inicial
breve** do trace, antes do PSEL cruzar para >512 e os seguidores passarem a
usar SRRIP pelo resto da simulação (`follower_use_brrip_o final=0` nos
logs). Cada uma dessas ~226 inserções, por cair no padrão de reuso de
curtíssimo prazo da convolução (janela deslizante de 3 linhas — a mesma
linha lida como `img[y-1]` nesta iteração volta a ser lida como `img[y]` na
próxima), teve uma chance maior de ser evictada por inserção "far" antes de
ser reaproveitada — exatamente o mecanismo já hipotetizado (BRRIP sacrifica
proteção de dados de reuso iminente em troca de resistência a scans, uma
aposta ruim quando o dado *é* reusado logo em seguida). O set 31 (SDM-BRRIP
fixo) reforça o mesmo efeito de forma permanente (sempre BRRIP,
independente do PSEL), daí o maior desvio individual (+26).

## Confirmação de execução real (evidência)

Todas as 16 rodadas foram executadas via `vsim -c` (ModelSim 2020.1,
Intel FPGA Starter Edition) contra os traces corrigidos de
`bench/apendice_a_instrumented.c` — 12 combinações (streaming, matrix_conv,
pattern_search) contra os traces da revisão 2, e as 4 combinações de
linked_list (L1/L2 × LRU/DRRIP) re-executadas contra o trace da revisão 3
(offset dos 2 cursores corrigido, ver seção dedicada acima). 0 combinações
falharam (16/16 `RESULTADO: PASS`, `Errors: 0` em todas). Logs completos em
`resultados/logs/run_measure_bench_*.log`.

Exemplo de saída real (matrix_conv, L1, DRRIP —
`resultados/logs/run_measure_bench_matrix_conv_l1_drrip.log`):

```
==================================================================
measure_harness: trace='tb/traces/bench_matrix_conv.txt'
  config: ADDR_W=32 BLK_B=32 SETS=64 WAYS=2 policy=DRRIP
==================================================================
------------------------------------------------------------------
  acessos totais = 127008
  hits           = 118677
  misses         = 8331
  HIT RATE       = 93.441 %
------------------------------------------------------------------
  PSEL final (debug)            = 538
  follower_use_brrip_o final     = 0
------------------------------------------------------------------
==================================================================
RESULTADO: PASS (0 erros)
==================================================================
```

## Conclusão

Os 4 benchmarks, na escala calibrada para criar disputa real de via
(validada por `tag_dispute_analysis.txt` e pelo modelo de software
bit-exato — incluindo, para linked_list, uma dessincronização de cursores
provada algebricamente e confirmada empiricamente na revisão 3), produzem
majoritariamente **paridade** entre DRRIP e LRU — resultado real da
simulação, investigado e explicado, não escondido: os padrões sintéticos
gerados (streaming/linked_list/pattern_search) são, estruturalmente,
varreduras de reuso quase nulo por set, regime em que SRRIP e BRRIP
genuinamente empatam entre si (e por extensão com LRU) — o próprio
set-dueling reconhece isso corretamente (PSEL permanece perto do reset).
Para linked_list especificamente, esse empate foi colocado à prova por uma
dessincronização real dos 2 cursores (que antes estavam, sem querer,
travados no mesmo set) e persistiu bit a bit — reforçando, não enfraquecendo,
a conclusão. O único benchmark com reuso de curtíssimo prazo genuíno
(matrix_conv, janela deslizante de convolução) é também o único em que a
escolha de inserção realmente importa, e nele o resultado é consistente com
a literatura: BRRIP penaliza dados reusados em breve, produzindo uma
pequena desvantagem agregada para DRRIP (-0.16pp) explicada, set a set, por
inserções regidas por BRRIP durante a janela de convergência inicial do
PSEL mais o set SDM-BRRIP fixo.
