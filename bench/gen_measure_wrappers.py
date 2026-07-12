#!/usr/bin/env python3
# =============================================================================
# gen_measure_wrappers.py
# PI4 UNIPAMPA - Fase 9 (bench_traces + run comparativo)
#
# Gera PROGRAMATICAMENTE os 16 wrappers de topo (tb/measure_bench_*_tb.v) e
# os 16 scripts do ModelSim (sim/run_measure_bench_*.do) para a matriz
# 4 benchmarks x 2 configs (L1/L2) x 2 politicas (LRU/DRRIP), seguindo
# EXATAMENTE o mesmo padrao "wrapper fino + .do" ja estabelecido nas Fases 8
# (ver tb/measure_l1_lru_tb.v, tb/measure_l1_drrip_tb.v, etc. e os
# sim/run_measure_l1_lru.do correspondentes) -- este script so evita ter que
# escrever/copiar-colar 16 arquivos manualmente (risco de erro), mas os
# arquivos GERADOS ficam gravados no repo como artefatos versionados de
# verdade (nao e um passo "por fora" da simulacao).
#
# Uso (a partir da raiz do repo, /home/miguel/verilog):
#   python3 bench/gen_measure_wrappers.py
#
# Isso (re)escreve os 16 arquivos tb/measure_bench_*_tb.v e os 16
# sim/run_measure_bench_*.do. Rodar de novo e idempotente (mesma saida).
# =============================================================================

import os

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TB_DIR = os.path.join(REPO_ROOT, "tb")
SIM_DIR = os.path.join(REPO_ROOT, "sim")

# ---- config das caches de ENTREGA (Apendice B) -----------------------------
CONFIGS = {
    "l1": dict(
        label="L1 (dados): 4KB, bloco 32B, 2-way -> SETS=64, WAYS=2, OFFSET=5 INDEX=6 TAG=21",
        ADDR_W=32, BLK_B=32, SETS=64, WAYS=2,
    ),
    "l2": dict(
        label="L2 (unif.): 32KB, bloco 64B, 8-way -> SETS=64, WAYS=8, OFFSET=6 INDEX=6 TAG=20",
        ADDR_W=32, BLK_B=64, SETS=64, WAYS=8,
    ),
}

# ---- parametros de FABRICA do DRRIP (fieis ao paper, Jaleel et al. ISCA
#      2010) -- Fase 9 usa estes, NAO os valores reduzidos das fases
#      anteriores (que eram so p/ rastreamento manual). ----------------------
DRRIP_FACTORY = dict(
    RRPV_BITS=2,
    BRRIP_THROTTLE_BITS=5,   # 1/32
    PSEL_BITS=10,
    SDM_SEL_BITS=4,          # 1/16 de cada lado (SETS=64 -> INDEX_W=6)
)

# ---- os 4 benchmarks do Apendice A (gerados por
#      bench/apendice_a_instrumented.c em tb/traces/bench_*.txt) ------------
BENCHMARKS = {
    "streaming":      dict(trace="tb/traces/bench_streaming.txt",
                            label="Streaming + HotSet (antagonista ao LRU)"),
    "matrix_conv":    dict(trace="tb/traces/bench_matrix_conv.txt",
                            label="Convolucao 2D (reuso em janela)"),
    "linked_list":    dict(trace="tb/traces/bench_linked_list.txt",
                            label="Linked List (ponteiros/saltos de memoria)"),
    "pattern_search": dict(trace="tb/traces/bench_pattern_search.txt",
                            label="Pattern Search (estresse de L2 unificada)"),
}

POLICIES = ["lru", "drrip"]


def tb_module_name(bench, cfg, pol):
    return f"measure_bench_{bench}_{cfg}_{pol}_tb"


def gen_tb_file(bench, cfg, pol):
    cfg_p = CONFIGS[cfg]
    bmeta = BENCHMARKS[bench]
    modname = tb_module_name(bench, cfg, pol)
    fname = os.path.join(TB_DIR, f"{modname}.v")

    if pol == "lru":
        policy_params = "        .USE_DRRIP  (0),\n"
        policy_note = ("politica LRU (repl_lru_nway.v, matricial, "
                        "unico modulo LRU do projeto que cobre tanto 2-way "
                        "quanto 8-way)")
    else:
        policy_params = (
            "        .USE_DRRIP           (1),\n"
            f"        .RRPV_BITS           ({DRRIP_FACTORY['RRPV_BITS']}),\n"
            f"        .BRRIP_THROTTLE_BITS ({DRRIP_FACTORY['BRRIP_THROTTLE_BITS']}),\n"
            f"        .PSEL_BITS           ({DRRIP_FACTORY['PSEL_BITS']}),\n"
            f"        .SDM_SEL_BITS        ({DRRIP_FACTORY['SDM_SEL_BITS']}),\n"
        )
        policy_note = ("politica DRRIP (repl_drrip.v) com parametros de "
                        "FABRICA fieis ao paper (Jaleel et al. ISCA 2010): "
                        f"RRPV_BITS={DRRIP_FACTORY['RRPV_BITS']}, "
                        f"BRRIP_THROTTLE_BITS={DRRIP_FACTORY['BRRIP_THROTTLE_BITS']} (1/32), "
                        f"PSEL_BITS={DRRIP_FACTORY['PSEL_BITS']}, "
                        f"SDM_SEL_BITS={DRRIP_FACTORY['SDM_SEL_BITS']} (1/16 de cada lado)")

    content = f"""\
// =============================================================================
// {modname}.v
// GERADO por bench/gen_measure_wrappers.py -- Fase 9 (bench_traces + run
// comparativo). NAO EDITAR A MAO: para mudar algo, edite o gerador e rode
// `python3 bench/gen_measure_wrappers.py` de novo (idempotente).
//
// Mede hit rate do benchmark real do Apendice A "{bmeta['label']}"
// na config de ENTREGA {cfg.upper()} do Apendice B
// ({cfg_p['label']}) com {policy_note}.
//
// Trace: {bmeta['trace']} (gerado por bench/apendice_a_instrumented.c, ver
// cabecalho la para o esquema de enderecamento sintetico e as escalas
// usadas). EXPECTED_ACCESSES/EXPECTED_HITS ficam nos defaults -1 (sem
// checagem automatica) -- o resultado desta rodada E o dado comparativo
// (ver resultados/hit_rate_comparativo.md).
//
// Como compilar/simular: vsim -c -do sim/run_{modname[:-len('_tb')]}.do
// (executar a partir da raiz do repo, /home/miguel/verilog)
// =============================================================================

`timescale 1ns/1ps

module {modname};

    measure_harness #(
        .ADDR_W     ({cfg_p['ADDR_W']}),
        .BLK_B      ({cfg_p['BLK_B']}),
        .SETS       ({cfg_p['SETS']}),
        .WAYS       ({cfg_p['WAYS']}),
{policy_params}        .TRACE_FILE ("{bmeta['trace']}")
    ) u_measure ();

endmodule
"""
    with open(fname, "w") as f:
        f.write(content)
    return fname


def gen_do_file(bench, cfg, pol):
    modname = tb_module_name(bench, cfg, pol)
    # mesma convencao ja usada nas Fases 8 (ex. modulo "measure_l1_lru_tb" ->
    # script "run_measure_l1_lru.do", i.e. "run_" + nome do modulo SEM o
    # sufixo "_tb"):
    do_name = f"run_{modname[:-len('_tb')]}.do"  # run_measure_bench_<b>_<cfg>_<pol>.do
    fname = os.path.join(SIM_DIR, do_name)

    content = f"""\
# {do_name}
# GERADO por bench/gen_measure_wrappers.py -- Fase 9. NAO EDITAR A MAO.
# Script do ModelSim: mede hit rate do benchmark '{bench}' do Apendice A na
# config de ENTREGA {cfg.upper()} com a politica {pol.upper()}, via measure_harness.v.
# Assume cwd = /home/miguel/verilog (raiz do projeto).
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/{do_name}

if {{[file exists work]}} {{
    vdel -lib work -all
}}

vlib work
vlog rtl/cache_datapath.v rtl/repl_lru_nway.v rtl/psel_dueling.v rtl/repl_drrip.v tb/measure_harness.v tb/{modname}.v
vsim -c work.{modname}
run -all
quit -f
"""
    with open(fname, "w") as f:
        f.write(content)
    return fname


def main():
    generated = []
    for bench in BENCHMARKS:
        for cfg in CONFIGS:
            for pol in POLICIES:
                generated.append(gen_tb_file(bench, cfg, pol))
                generated.append(gen_do_file(bench, cfg, pol))
    print(f"{len(generated)} arquivos gerados ({len(generated)//2} wrappers .v + {len(generated)//2} scripts .do):")
    for g in generated:
        print(" ", os.path.relpath(g, REPO_ROOT))


if __name__ == "__main__":
    main()
