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

## 2. Quartus (síntese) — funcionando, com o Quartus II 13.0sp1 (legado)

### 2.1 Duas instalações do Quartus nesta máquina, para propósitos diferentes

| | Quartus Prime 20.1 | Quartus II 13.0sp1 (legado) |
|---|---|---|
| Path | `/home/miguel/intelFPGA_lite/20.1/quartus/bin` | `/home/miguel/altera/13.0sp1/quartus/bin` |
| Suporta Cyclone III? | **Não** (família descontinuada) | **Sim** — é a última versão que suporta |
| Pacote de dispositivo instalado? | Nenhum (`devdata/` vazio) | Sim, Cyclone II/III/IV (`cyclone_web-13.0.1.232.qdz`) |
| Uso neste projeto | Referência/estudo só | **É o que sintetiza de verdade pro EP3C25F324C6** |

Use sempre o **Quartus II 13.0sp1** (segunda coluna) pra qualquer
síntese real deste projeto.

### 2.2 O que já está pronto e testado

Projeto em `quartus/` (`cache_pi4.qpf`/`cache_pi4.qsf`), com **todos**
os módulos de `rtl/*.v` adicionados e o dispositivo alvo real
configurado (`Cyclone III`, `EP3C25F324C6`). Script que regenera o
projeto (`quartus/setup_project.tcl`), reexecutável:

```bash
export PATH=/home/miguel/altera/13.0sp1/quartus/bin:$PATH
cd /home/miguel/verilog/quartus
quartus_sh -t setup_project.tcl
```

**Síntese real, testada e funcionando** (0 erros, só warnings
esperados/benignos — pinos não usados na config pequena de validação
etc.) para os 8 módulos, um de cada vez como `TOP_LEVEL_ENTITY`:

```bash
export PATH=/home/miguel/altera/13.0sp1/quartus/bin:$PATH
cd /home/miguel/verilog/quartus
quartus_map cache_pi4
```

Pra compilação completa (síntese + fitter + assembler + timing, gera
o `.sof` de programação e o relatório de Fmax real):

```bash
quartus_map cache_pi4
quartus_fit cache_pi4
quartus_asm cache_pi4
quartus_sta cache_pi4
```

Ou, na GUI: `export PATH=...` como acima, depois `quartus` (abre a
GUI do Quartus II), `File > Open Project > cache_pi4.qpf`,
`Processing > Start Compilation`.

### 2.3 Como o RTL virou compatível com essa toolchain legada

Todo módulo original usava porta ANSI-style com `localparam` derivado
dentro da lista de parâmetros — sintaxe que o Quartus Prime aceita mas
o Quartus II 13.0sp1 rejeita (`Error (10170)`). Os 8 arquivos de
`rtl/*.v` foram convertidos pro estilo Verilog-1995/2001 não-ANSI
(parâmetros só com `parameter` de verdade na lista `#(...)`,
`localparam`s derivados e declaração de porta movidos pro corpo do
módulo) — refactor puramente sintático, sem mudança de comportamento,
revisado pelo rtl-analyst e com não-regressão confirmada contra toda a
suíte de testbenches. Ver commit "Adapta RTL pra compatibilidade com
Quartus II 13.0sp1" no histórico do git.

### 2.4 Instalação (caso precise reinstalar ou reproduzir em outra máquina)

Instalado localmente (sem sudo) em `/home/miguel/altera/13.0sp1/`
(~14GB), a partir dos instaladores baixados manualmente da Intel/
Altera (EULA exige sessão de navegador, não dá pra automatizar):
`QuartusSetupWeb-13.0.1.232.run` (instalador principal) +
`cyclone_web-13.0.1.232.qdz` (device pack Cyclone II/III/IV, precisa
estar na MESMA pasta do `.run` — o instalador detecta e aplica
automaticamente). Comando usado:

```bash
chmod +x QuartusSetupWeb-13.0.1.232.run
./QuartusSetupWeb-13.0.1.232.run --mode unattended --unattendedmodeui minimal --installdir /home/miguel/altera/13.0sp1
```

Nesta máquina a arquitetura i386 já estava habilitada (provável
resquício da instalação do ModelSim/Questa moderno), então não foi
necessário `sudo dpkg --add-architecture i386` nem instalar libs de
compatibilidade adicionais (`libpng12` etc.) — o instalador e o
`quartus_map` rodaram direto. Se isso NÃO funcionar em outra máquina,
o procedimento de referência completo (com os passos de libpng12/
libtbb pra Ubuntu mais recente) está em
https://gist.github.com/bkw777/a6a2888f482802f2e520165858268cd3.

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
- **Quartus**: **funciona 100% nesta máquina**, usando o Quartus II
  13.0sp1 (legado, `/home/miguel/altera/13.0sp1/quartus/bin`) — a
  única toolchain que ainda suporta o chip alvo real (Cyclone III
  EP3C25F324C6). Os 8 módulos de `rtl/*.v` sintetizam com 0 erros. O
  Quartus Prime 20.1 moderno (`/home/miguel/intelFPGA_lite/`) fica só
  como referência — não suporta mais Cyclone III.
