# Plano — DRRIP vs LRU em RTL (PI4, Caches Inteligentes RISC-V)

Algoritmo escolhido (AIRA): **DRRIP** — item 1 da seção 3 da spec.
Baseline a superar: **LRU**. Métrica que dá nota: **hit rate** (seção 1 + Ap. B).
Escopo: RTL + simulação em ModelSim. **Integração ao FPGA foi cortada**
(sem Quartus, sem SignalTap, sem síntese/área/Fmax, sem inserção no core
RISC-V). O foco é a comparação funcional de taxa de acerto DRRIP vs LRU.

## Estratégia em duas etapas

1. **Validar as políticas** numa config PEQUENA, rastreável na mão (fases 1-5).
2. **Montar a cache real + medição** e rodar os benchmarks nas configs de
   entrega (fases 6-9).

Tudo SEMPRE parametrizado (parameter). Trocar de config = trocar parameters.

### Config de VALIDAÇÃO (brinquedo, pra conferir RRPV/LRU no lápis)
    ADDR_W=8, BLK_B=4, SETS=4, WAYS=2, RRPV_BITS=2  ->  OFFSET=2 INDEX=2 TAG=4

### Configs de ENTREGA (Apêndice B — endereço RV32I de 32 bits)
    L1 (dados): 4KB, bloco 32B, 2-way  -> 64 sets, OFFSET=5 INDEX=6 TAG=21
    L2 (unif.): 32KB, bloco 64B, 8-way -> 64 sets, OFFSET=6 INDEX=6 TAG=20

## Regras de processo (siga à risca)

- Construa UMA mecânica por vez, na ordem abaixo.
- Depois de CADA fase, use o **rtl-analyst** pra revisar antes de seguir.
- Veredito REPROVADO (ou APROVADO COM RESSALVAS de severidade crítica):
  o **verilog-cache-dev** corrige e manda revisar de novo. Só avance com APROVADO.
- Pare e me mostre o veredito ao fim de cada fase antes da próxima.
- Todo módulo vem com: (a) .v parametrizado, (b) testbench com valores
  ESPERADOS calculados na mão, (c) comandos vlog/vsim pro ModelSim.

---

## ETAPA 1 — Validação das políticas (config brinquedo)

### Fase 1 — cache_addr
verilog-cache-dev implementa o split TAG/INDEX/OFFSET + storage por way
(tag/valid/data) na config de validação. Testbench conferindo o split em
vários endereços. rtl-analyst revisa.

### Fase 2 — repl_lru (2-way)
verilog-cache-dev implementa LRU de 1 bit por set (atualiza em hit e em
miss/eviction). rtl-analyst revisa.

### Fase 3 — repl_srrip
verilog-cache-dev implementa SRRIP: insere com RRPV=2, hit->0, despejo busca
RRPV=3 e incrementa todos se não achar. rtl-analyst revisa.

### Fase 4 — repl_brrip
verilog-cache-dev implementa BRRIP: insere quase sempre com RRPV=3, raro em 2
(throttle bimodal). rtl-analyst revisa.

### Fase 5 — psel_dueling
Valide SEPARADO da cache pequena (4 sets não comportam SDMs reais).
verilog-cache-dev implementa o PSEL saturante + bench dedicado que alimenta
sequência conhecida de miss-SRRIP / miss-BRRIP e confere subida, descida,
saturação e a virada do MSB. rtl-analyst revisa.

---

## ETAPA 2 — Cache real + medição de hit rate

### Fase 6 — cache_datapath
verilog-cache-dev implementa a CACHE parametrizável de verdade em volta da
política: comparação de tag, sinal hit/miss, read/write, bits valid e dirty
(política de escrita = a atual, seção 4). Interface de substituição PLUGÁVEL,
pra encaixar LRU ou DRRIP sem reescrever o datapath. Testbench de hit/miss
básico. rtl-analyst revisa (foco: corretude do hit/miss e da interface).

### Fase 7 — repl_lru_nway
O LRU de 1 bit da fase 2 só serve pra 2-way. Pro L2 (8-way) precisa de LRU
matricial OU tree-PLRU PARAMETRIZÁVEL por WAYS. verilog-cache-dev implementa
e valida em 2-way (bate com a fase 2) e em 8-way. rtl-analyst revisa.

### Fase 8 — measure_tb
verilog-cache-dev cria o harness de medição: carrega um trace de endereços de
um arquivo, aplica na cache e CONTA hits e misses, cuspindo hit rate no fim.
Parametrizável pra rodar L1 e L2 nas configs de entrega. rtl-analyst revisa.

### Fase 9 — bench_traces + run comparativo
verilog-cache-dev gera os traces dos 4 benchmarks do Apêndice A
(streaming+hotset, convolução de matriz, linked list, pattern search).
Sugestão no Ubuntu: compilar o C do Apêndice A e extrair os endereços de
acesso com `valgrind --tool=lackey --trace-mem=yes` (não precisa do core
RISC-V pra isso). Depois roda LRU e DRRIP em cada config do Apêndice B e
monta a tabela comparativa (hit rate baseline vs DRRIP, por benchmark) no
formato do Apêndice B. rtl-analyst faz a revisão final de consistência.

---

## Fora de escopo (FPGA cortado)
Síntese Quartus, Área/LEs/BRAMs, Fmax, SignalTap, e inserção no
riscv_core/. Se voltar ao escopo depois, é só acrescentar as fases de síntese.

Comece pela Fase 1.
