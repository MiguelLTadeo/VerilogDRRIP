# Guia — Rodando este projeto no ModelSim e no Quartus

Este guia cobre as duas ferramentas usadas pelo projeto de cache RTL
(DRRIP vs LRU, PI4 UNIPAMPA): **ModelSim** (simulação — já testado e
funcional nesta máquina) e **Quartus** (síntese — projeto pronto, mas
com uma limitação real de ambiente explicada abaixo).

Todos os comandos assumem `cd /home/miguel/verilog` como diretório
corrente, salvo indicação contrária.

---

## 1. ModelSim (simulação) — testado e funcionando

### 1.1 Colocar as ferramentas no PATH

```bash
export PATH=/home/miguel/intelFPGA_lite/20.1/modelsim_ase/linuxaloem:$PATH
```

Adicione essa linha ao seu `~/.bashrc` (ou rode toda vez antes de usar
`vlog`/`vsim`) se for usar com frequência.

### 1.2 Rodar UM testbench específico

Cada módulo tem um script `.do` pronto em `sim/`. Padrão de uso, a
partir da raiz do repo:

```bash
vsim -c -do sim/<nome_do_script>.do
```

O `-c` roda em modo texto (sem GUI), compila, simula e sai sozinho —
ideal pra CI/terminal. Se preferir a GUI do ModelSim, abra o `vsim`
normalmente e rode `do sim/<nome_do_script>.do` dentro dele.

Cada script já limpa a `work/` de uma rodada anterior antes de
recompilar (evita rodar binário obsoleto por engano), compila o(s)
`.v` do RTL + testbench, e termina imprimindo `RESULTADO: PASS` ou
`RESULTADO: FAIL (N erro(s))`.

### 1.3 Referência — todos os scripts, por fase do plano

**Etapa 1 — validação das políticas (config brinquedo, ADDR_W=8/SETS=4/WAYS=2)**

| Fase | Script | O que testa |
|---|---|---|
| 1 | `sim/run_cache_addr.do` | split TAG/INDEX/OFFSET + storage por via |
| 2 | `sim/run_repl_lru.do` | LRU de 1 bit por set (só 2-way) |
| 3 | `sim/run_repl_srrip.do` | SRRIP (RRPV, aging, busca de vítima) |
| 3 | `sim/run_repl_srrip_guard_neg.do` | guarda de elaboração (RRPV_BITS inválido deve falhar) |
| 4 | `sim/run_repl_brrip.do` | BRRIP (throttle bimodal) |
| 4 | `sim/run_repl_brrip_guard_neg.do` | guarda de elaboração do BRRIP |
| 5 | `sim/run_psel_dueling.do` | PSEL saturante (set-dueling) |
| 5 | `sim/run_psel_dueling_guard_neg.do` | guarda de elaboração do PSEL |

**Etapa 2 — cache real + medição**

| Fase | Script | O que testa |
|---|---|---|
| 6 | `sim/run_cache_datapath.do` | cache real (hit/miss, valid/dirty, write-back) |
| 7 | `sim/run_repl_lru_nway.do` | LRU matricial (valida 2-way e 8-way) |
| 8 | `sim/run_repl_drrip.do` | DRRIP unificado (set-dueling completo, config de entrega) |
| 8 | `sim/run_measure_val_lru.do` / `run_measure_val_drrip.do` | harness de medição, config de validação (autoverificado) |
| 8 | `sim/run_measure_l1_lru.do` / `run_measure_l1_drrip.do` | harness, config L1 do Apêndice B, trace smoke sintético |
| 8 | `sim/run_measure_l2_lru.do` / `run_measure_l2_drrip.do` | harness, config L2 do Apêndice B, trace smoke sintético |
| 9 | `sim/run_measure_bench_<benchmark>_<l1\|l2>_<lru\|drrip>.do` (16 scripts) | os 4 benchmarks do Apêndice A × 2 configs × 2 políticas |

Os 16 scripts da Fase 9 seguem o padrão
`run_measure_bench_{streaming,matrix_conv,linked_list,pattern_search}_{l1,l2}_{lru,drrip}.do`.

### 1.4 Rodar TUDO de uma vez

```bash
export PATH=/home/miguel/intelFPGA_lite/20.1/modelsim_ase/linuxaloem:$PATH
cd /home/miguel/verilog
for f in sim/*.do; do
  echo "=== $f ==="
  vsim -c -do "$f" 2>&1 | grep -E "RESULTADO|Errors:"
done
```

Isso roda as 33 simulações do projeto e imprime só a linha de
resultado de cada uma (bem mais rápido de ler do que o log completo).
Rodei esse loop inteiro pra validar este guia: **30 terminam com
`RESULTADO: PASS`**, e os outros **3 são testes NEGATIVOS por
desenho** (`sim/run_repl_srrip_guard_neg.do`,
`sim/run_repl_brrip_guard_neg.do`, `sim/run_psel_dueling_guard_neg.do`)
— eles instanciam uma configuração de parâmetro INVÁLIDA de propósito
pra provar que a guarda de elaboração do módulo bloqueia (erro fatal
`Error loading design` / `Errors: N` é o resultado ESPERADO e
CORRETO desses 3; eles nunca imprimem `RESULTADO: PASS` porque a
simulação nem chega a rodar — a elaboração já falha antes). Não é
regressão nem bug — é o comportamento documentado no cabeçalho de cada
um desses 3 scripts.

### 1.5 Onde ver os resultados da Fase 9 (comparativo DRRIP vs LRU)

Já rodados e versionados:
- `resultados/logs/run_measure_bench_*.log` — saída bruta de cada uma das 16 simulações.
- `resultados/hit_rate_comparativo.md` — tabela final consolidada, com a investigação de cada resultado.
- `resultados/tag_dispute_analysis.txt` — evidência de que os traces geram disputa real de vítima entre vias.

---

## 2. Quartus (síntese) — projeto pronto, mas com limitação real de ambiente

### 2.1 O que já está pronto

Criei o projeto em `quartus/` (`cache_pi4.qpf`/`cache_pi4.qsf`), com
**todos** os módulos de `rtl/*.v` já adicionados e o dispositivo alvo
real do projeto configurado (`Cyclone III`, `EP3C25F324C6`). O script
que gera esse projeto (`quartus/setup_project.tcl`) é reexecutável:

```bash
export PATH=/home/miguel/intelFPGA_lite/20.1/quartus/bin:$PATH
cd /home/miguel/verilog/quartus
quartus_sh -t setup_project.tcl
```

### 2.2 Limitação de ambiente encontrada (testei antes de escrever isto)

Tentei rodar a síntese de verdade (`quartus_map cache_pi4`) e ela
**falha nesta máquina**, não por causa do RTL, mas porque:

1. **Nenhum pacote de suporte de dispositivo está instalado** — o
   diretório `/home/miguel/intelFPGA_lite/20.1/devdata` está
   **vazio**. O Quartus Prime aqui instalado é só o software base;
   nenhuma família de FPGA (nem Cyclone III, nem nenhuma outra) tem
   os dados de dispositivo necessários pra `quartus_map` rodar.
   Confirmei isso tentando tanto `Cyclone III` (o alvo real) quanto
   `Cyclone IV E` (uma família mais nova, só pra teste) — as duas
   falham com o mesmo erro (`Error (20004)`).
2. **Mesmo com o pacote de dispositivo certo instalado, o Quartus
   Prime 20.1 (esta versão) NÃO suporta Cyclone III** — a Intel
   descontinuou essa família a partir do Quartus Prime (~18.x em
   diante). O EP3C25F324C6 exige o **Quartus II legado** (até a
   versão 13.0sp1, "Web Edition", que ainda é a que suporta
   Cyclone III/II e séries mais antigas).

Ou seja: **o projeto e o RTL estão prontos**, mas rodar a síntese de
verdade pro chip alvo (EP3C25F324C6) requer instalar outra ferramenta
(Quartus II 13.0sp1), não é algo que dá pra resolver só com o que já
está instalado aqui.

### 2.3 Como prosseguir (duas opções)

**Opção A — instalar o Quartus II 13.0sp1 (recomendado, é o alvo real do projeto)**

Baixe o "Quartus II Web Edition 13.0sp1" no site de downloads legados
da Intel/Altera (procure por "Quartus II 13.0 Service Pack 1
Downloads" — inclui o pacote de dispositivos Cyclone III como parte do
instalador Web Edition, ou como device pack separado). Depois de
instalado:

```bash
export PATH=<caminho-do-quartus-ii-13.0sp1>/quartus/bin:$PATH
cd /home/miguel/verilog/quartus
quartus_sh -t setup_project.tcl   # recria o projeto com essa toolchain
quartus_map cache_pi4              # Analysis & Synthesis
quartus_fit cache_pi4              # Fitter (place & route)
quartus_asm cache_pi4              # Assembler (gera o .sof/.pof)
quartus_sta cache_pi4              # Timing Analysis (Fmax real)
```

Ou, na GUI: `File > Open Project > cache_pi4.qpf`, depois
`Processing > Start Compilation`.

**Opção B — validar só a sintetizabilidade agora, com uma família suportada nesta máquina**

Se você só quer confirmar que o RTL sintetiza sem erro (sem se
importar com área/Fmax reais do Cyclone III ainda), instale o pacote
de dispositivo de uma família suportada pelo Quartus Prime 20.1 (ex.
Cyclone IV E) via `Tools > Install Devices` na GUI, ou o instalador
offline de dispositivos da Intel. Depois edite as 2 linhas de família/
dispositivo em `quartus/setup_project.tcl` (já tem um comentário lá
indicando onde) e rode os mesmos comandos da Opção A.

### 2.4 Trocando qual módulo é o topo da síntese

O projeto **não tem um único "top" que integra tudo** — como o
próprio `cache_datapath.v` documenta (ver "DECISÃO DE PROJETO #2" no
cabeçalho do arquivo), a integração cache+política é feita hoje só em
nível de testbench (`tb/measure_harness.v`), que **não é
sintetizável** (usa `$fopen`/`$fscanf`, exclusivo de simulação).

Por padrão o projeto Quartus está configurado com
`TOP_LEVEL_ENTITY cache_datapath`. Pra sintetizar outro módulo
isoladamente, troque essa linha (na GUI: `Assignments > Settings >
General`, ou editando `quartus/cache_pi4.qsf` direto):

| Módulo (top-level) | O que é |
|---|---|
| `cache_addr` | split de endereço + storage por via (Fase 1, hoje só referência — não usado pelo datapath real) |
| `cache_datapath` | cache completa (tag compare, hit/miss, valid/dirty, write-back) — **default** |
| `repl_lru` | LRU de 1 bit (só 2-way) |
| `repl_lru_nway` | LRU matricial parametrizável por WAYS |
| `repl_srrip` | SRRIP isolado |
| `repl_brrip` | BRRIP isolado |
| `repl_drrip` | DRRIP unificado (set-dueling completo) |
| `psel_dueling` | PSEL saturante isolado |

Todos os arquivos de `rtl/*.v` já estão adicionados ao projeto, então
trocar o `TOP_LEVEL_ENTITY` é suficiente — não precisa readicionar
nada.

**Nunca** aponte `TOP_LEVEL_ENTITY` pra nada em `tb/` — são
testbenches, não sintetizáveis, e a síntese vai falhar (ou pior, vai
tentar sintetizar constructs de simulação de forma incorreta).

### 2.5 Se quiser sintetizar a cache "completa" (datapath + política)

Hoje isso só existe fiado junto num testbench (`measure_harness.v`).
Se quiser um TOP sintetizável de verdade (datapath + LRU, ou datapath
+ DRRIP, prontos pra virar bitstream), é preciso escrever um módulo
novo `cache_top_lru.v`/`cache_top_drrip.v` que replica a mesma "glue
logic" de `measure_harness.v` (fios diretos entre `cache_datapath` e
`repl_lru_nway`/`repl_drrip`, documentados na seção "GLUE LOGIC de
política" do cabeçalho de `tb/measure_harness.v`) só que sem nenhum
construct de simulação. Isso não foi feito ainda — avise se quiser que
eu crie esse módulo.

---

## Resumo rápido

- **ModelSim**: funciona 100% nesta máquina, todos os ~33 testbenches
  já rodam PASS. Use a tabela da seção 1.3 ou o loop da seção 1.4.
- **Quartus**: projeto pronto (`quartus/cache_pi4.qpf`), mas a síntese
  de verdade pro chip alvo (Cyclone III EP3C25F324C6) exige instalar o
  Quartus II 13.0sp1 (legado) — o Quartus Prime 20.1 instalado aqui
  não tem NENHUM pacote de dispositivo instalado, e mesmo instalando
  um, não suporta mais Cyclone III.
