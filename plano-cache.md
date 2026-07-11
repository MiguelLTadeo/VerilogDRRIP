# Plano — simulador de cache RTL (validação)

Objetivo: implementar e validar em RTL um simulador de cache com políticas
LRU e RRIP (SRRIP/BRRIP/DRRIP), começando por uma config PEQUENA e rastreável
na mão. O foco agora é validação, não a config final de FPGA.

## Config de validação (SEMPRE via parameter, nunca hardcoded)

    ADDR_W=8, BLK_B=4, SETS=4, WAYS=2, RRPV_BITS=2
    -> OFFSET=2, INDEX=2, TAG=4

Escalar pra config real depois deve ser só trocar os parameters.

## Regras de processo (siga à risca)

- Construa UMA mecânica por vez, na ordem abaixo.
- Depois de CADA módulo, use o rtl-analyst pra revisar antes de seguir.
- Se o veredito for REPROVADO (ou APROVADO COM RESSALVAS de severidade
  crítica), o verilog-cache-dev corrige e manda revisar de novo. Só avance
  com APROVADO.
- Pare e me mostre o veredito ao fim de cada fase antes de iniciar a próxima.

## Ordem de construção

1. cache_addr: peça ao verilog-cache-dev pra implementar o split
   TAG/INDEX/OFFSET + storage por way (tag/valid/data), com testbench.
   Depois peça ao rtl-analyst pra revisar. Só avance com APROVADO.

2. repl_lru: verilog-cache-dev implementa o LRU de 1 bit por set (atualiza
   em hit e em miss/eviction). rtl-analyst revisa.

3. repl_srrip: verilog-cache-dev implementa (insere com RRPV=2, hit->0,
   despejo busca RRPV=3 e incrementa todos se não achar). rtl-analyst revisa.

4. repl_brrip: verilog-cache-dev implementa (insere quase sempre com RRPV=3,
   raro em 2 -- throttle bimodal). rtl-analyst revisa.

5. psel_dueling: valide SEPARADO da cache pequena (4 sets não comportam SDMs
   reais). verilog-cache-dev implementa o PSEL saturante + bench dedicado que
   alimenta uma sequência conhecida de miss-SRRIP / miss-BRRIP e confere
   subida, descida, saturação e a virada do MSB. rtl-analyst revisa.

## Cada entrega precisa ter

- (a) .v sintetizável e parametrizado;
- (b) testbench com os valores ESPERADOS calculados na mão (sequência de
  acessos -> hit/miss e estado de RRPV/LRU de cada way por ciclo);
- (c) comandos vlog/vsim pra rodar no ModelSim.

Comece pela fase 1.
