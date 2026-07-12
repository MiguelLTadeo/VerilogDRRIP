#!/usr/bin/env python3
# =============================================================================
# replay_model.py -- modelo de SOFTWARE (nao-RTL) fiel ao comportamento de
# rtl/cache_datapath.v + rtl/repl_lru_nway.v + rtl/repl_drrip.v +
# rtl/psel_dueling.v, escrito para INVESTIGAR (sem precisar rodar vsim de
# novo) um achado da Fase 9: 3 dos 4 benchmarks (streaming, linked_list,
# pattern_search) empatam EXATAMENTE entre LRU e DRRIP no hit rate agregado.
# Duas perguntas motivaram este script:
#
#   1) O PSEL final ficar preso perto do reset (512, ponto medio de um
#      contador de 10 bits) nesses 3 benchmarks e esperado (SDM-SRRIP e
#      SDM-BRRIP missam a taxas quase identicas) ou sintoma de bug (votos
#      nao contabilizados, mapeamento SDM errado)?
#   2) A colisao estrutural confirmada entre hot_data e o array (mesmo set,
#      streaming -- BASE_HOT=0x00020000 mapeia pro mesmo set que blocos do
#      array a cada 512 indices) produz alguma divergencia REAL entre LRU e
#      SRRIP naquele set especifico, mesmo que a media agregada empate?
#
# As respostas (documentadas em detalhe em resultados/hit_rate_comparativo.md,
# secoes "Por que 3 dos 4 benchmarks empatam EXATAMENTE" e "matrix_conv: onde
# a diferenca REAL vem"): (1) SIM, esperado -- nao e bug: o modelo reproduz o
# PSEL final reportado pelo vsim EXATAMENTE, confirmando que os votos estao
# corretos, e mostra que SDM-SRRIP e SDM-BRRIP genuinamente empatam em misses
# nesses 3 workloads (streaming/linked_list/pattern_search sao varreduras de
# reuso quase nulo por set, regime em que o VALOR de insercao MID vs FAR nao
# muda o resultado observavel). (2) NAO ha divergencia oculta -- 0 de 64 sets
# produzem contagens de miss diferentes entre LRU e DRRIP nesses 3
# benchmarks (incluindo o set 0 do hot_data, isolado e verificado): a
# colisao estrutural existe, mas hot_data e retocado ~8x mais frequente que
# o retorno do array aquele set, entao QUALQUER politica sensivel a
# recencia/reuso (LRU ou SRRIP) protege a via de hot_data sem ambiguidade.
#
# -----------------------------------------------------------------------
# METODOLOGIA -- por que confiar num modelo em Python em vez de so no RTL
# -----------------------------------------------------------------------
# Reimplementa em Python, FIEL linha a linha as regras documentadas em
# rtl/repl_lru_nway.v / rtl/repl_srrip.v / rtl/repl_drrip.v /
# rtl/psel_dueling.v (mesmo reset, mesma regra de vitima -- inclusive o
# detalhe de que uma via "vazia" apos reset ja se comporta como candidata a
# vitima natural, sem necessidade de um caminho especial de "primeiro fill",
# mesmo mapeamento SDM, mesma convencao de voto/saturacao do PSEL), 3
# simuladores:
#   sim_lru()   -- true LRU por set (bate com repl_lru_nway.v)
#   sim_srrip() -- SRRIP puro por set (bate com repl_srrip.v, nao usado
#                  diretamente na analise principal mas mantido para
#                  completude/reuso futuro)
#   sim_drrip() -- DRRIP completo + PSEL (bate com repl_drrip.v+psel_dueling.v)
#
# Os resultados agregados (hits/misses) de sim_lru()/sim_drrip() sao
# comparados contra os numeros REAIS reportados pelo vsim (constantes
# REAL_VSIM abaixo, extraidas de resultados/logs/run_measure_bench_*.log)
# como VALIDACAO EXTERNA CRUZADA -- rodado uma vez e conferido: bateram
# EXATAMENTE (bit a bit) nas 16 combinacoes benchmark x config x politica,
# sem nenhuma divergencia. Isso e evidencia forte de que tanto o modelo
# quanto o proprio RTL estao corretos, e que as conclusoes tiradas dele
# (per-set, por SDM) refletem o mecanismo real do hardware.
#
# Alem do agregado, sim_drrip()/sim_lru() expoem contagem de hit/miss por
# SET INDIVIDUAL e, no caso do DRRIP, contagem de votos por SDM
# (srrip_sdm_misses/brrip_sdm_misses) e quantos fills de seguidor usaram
# cada regra (follower_srrip_fills/follower_brrip_fills) -- granularidade
# que os $display de tb/measure_harness.v nao expoem (o harness so conta
# hit/miss GLOBAL da cache inteira, nao por set).
#
# -----------------------------------------------------------------------
# Uso: python3 bench/replay_model.py   (a partir de qualquer diretorio --
# o script faz os.chdir para a raiz do repo internamente)
# =============================================================================

import sys

def ilog2(v):
    r = 0
    while v > 1:
        v >>= 1
        r += 1
    return r

def load_trace(path):
    addrs = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            addrs.append(int(parts[1], 16))
    return addrs

def sim_lru(addrs, blk_b, sets, ways):
    offset_w = ilog2(blk_b)
    index_w = ilog2(sets)
    tag_of = [[None]*ways for _ in range(sets)]
    order = [list(range(ways)) for _ in range(sets)]  # front=MRU, reset: way0 MRU..wayN-1 LRU
    hits = 0
    misses = 0
    per_set_hits = [0]*sets
    per_set_misses = [0]*sets
    for a in addrs:
        idx = (a >> offset_w) & (sets - 1)
        tag = a >> (offset_w + index_w)
        tags = tag_of[idx]
        found = None
        for w in range(ways):
            if tags[w] == tag:
                found = w
                break
        od = order[idx]
        if found is not None:
            hits += 1
            per_set_hits[idx] += 1
            od.remove(found)
            od.insert(0, found)
        else:
            misses += 1
            per_set_misses[idx] += 1
            victim = od[-1]
            tags[victim] = tag
            od.remove(victim)
            od.insert(0, victim)
    return dict(hits=hits, misses=misses, per_set_hits=per_set_hits, per_set_misses=per_set_misses)

def sim_srrip(addrs, blk_b, sets, ways, rrpv_bits=2):
    RRPV_MAX = (1 << rrpv_bits) - 1
    INSERT = RRPV_MAX - 1
    offset_w = ilog2(blk_b)
    index_w = ilog2(sets)
    tag_of = [[None]*ways for _ in range(sets)]
    rrpv = [[RRPV_MAX]*ways for _ in range(sets)]  # reset: todas as vias em RRPV_MAX
    hits = 0
    misses = 0
    per_set_hits = [0]*sets
    per_set_misses = [0]*sets
    for a in addrs:
        idx = (a >> offset_w) & (sets - 1)
        tag = a >> (offset_w + index_w)
        tags = tag_of[idx]
        found = None
        for w in range(ways):
            if tags[w] == tag:
                found = w
                break
        rv = rrpv[idx]
        if found is not None:
            hits += 1
            per_set_hits[idx] += 1
            rv[found] = 0
        else:
            misses += 1
            per_set_misses[idx] += 1
            while RRPV_MAX not in rv:
                for w in range(ways):
                    if rv[w] < RRPV_MAX:
                        rv[w] += 1
            victim = rv.index(RRPV_MAX)
            tags[victim] = tag
            rv[victim] = INSERT
    return dict(hits=hits, misses=misses, per_set_hits=per_set_hits, per_set_misses=per_set_misses)

def sim_drrip(addrs, blk_b, sets, ways, rrpv_bits=2, throttle_bits=5, psel_bits=10, sdm_sel_bits=4):
    RRPV_MAX = (1 << rrpv_bits) - 1
    MID = RRPV_MAX - 1
    FAR = RRPV_MAX
    offset_w = ilog2(blk_b)
    index_w = ilog2(sets)
    tag_of = [[None]*ways for _ in range(sets)]
    rrpv = [[RRPV_MAX]*ways for _ in range(sets)]
    PSEL_MAX = (1 << psel_bits) - 1
    psel = 1 << (psel_bits - 1)  # PSEL_RESET
    throttle_ctr = 0
    THROTTLE_PERIOD = 1 << throttle_bits
    sel_mask = (1 << sdm_sel_bits) - 1

    def role(idx):
        v = idx & sel_mask
        if v == 0:
            return 'SRRIP'
        if v == sel_mask:
            return 'BRRIP'
        return 'FOLLOW'

    hits = 0
    misses = 0
    per_set_hits = [0]*sets
    per_set_misses = [0]*sets
    srrip_sdm_misses = 0
    brrip_sdm_misses = 0
    follower_brrip_fills = 0
    follower_srrip_fills = 0
    psel_history_sample = []  # amostra esparsa p/ inspecao

    for n, a in enumerate(addrs):
        idx = (a >> offset_w) & (sets - 1)
        tag = a >> (offset_w + index_w)
        tags = tag_of[idx]
        found = None
        for w in range(ways):
            if tags[w] == tag:
                found = w
                break
        rv = rrpv[idx]
        if found is not None:
            hits += 1
            per_set_hits[idx] += 1
            rv[found] = 0
        else:
            misses += 1
            per_set_misses[idx] += 1
            r = role(idx)
            if r == 'SRRIP':
                psel = max(0, psel - 1)
                srrip_sdm_misses += 1
            elif r == 'BRRIP':
                psel = min(PSEL_MAX, psel + 1)
                brrip_sdm_misses += 1
            follower_use_brrip = (psel < (1 << (psel_bits - 1)))
            while RRPV_MAX not in rv:
                for w in range(ways):
                    if rv[w] < RRPV_MAX:
                        rv[w] += 1
            victim = rv.index(RRPV_MAX)
            tags[victim] = tag
            if r == 'SRRIP':
                rv[victim] = MID
            elif r == 'BRRIP':
                rare = (throttle_ctr == 0)
                rv[victim] = MID if rare else FAR
                throttle_ctr = (throttle_ctr + 1) % THROTTLE_PERIOD
            else:
                if follower_use_brrip:
                    rare = (throttle_ctr == 0)
                    rv[victim] = MID if rare else FAR
                    throttle_ctr = (throttle_ctr + 1) % THROTTLE_PERIOD
                    follower_brrip_fills += 1
                else:
                    rv[victim] = MID
                    follower_srrip_fills += 1
        if n % max(1, len(addrs)//20) == 0:
            psel_history_sample.append(psel)

    return dict(hits=hits, misses=misses, per_set_hits=per_set_hits, per_set_misses=per_set_misses,
                srrip_sdm_misses=srrip_sdm_misses, brrip_sdm_misses=brrip_sdm_misses,
                follower_brrip_fills=follower_brrip_fills, follower_srrip_fills=follower_srrip_fills,
                psel_final=psel, psel_history_sample=psel_history_sample)


CONFIGS = {
    "L1": dict(blk_b=32, sets=64, ways=2),
    "L2": dict(blk_b=64, sets=64, ways=8),
}

BENCH_TRACES = {
    "streaming":      "tb/traces/bench_streaming.txt",
    "matrix_conv":    "tb/traces/bench_matrix_conv.txt",
    "linked_list":    "tb/traces/bench_linked_list.txt",
    "pattern_search": "tb/traces/bench_pattern_search.txt",
}

# hit/miss REAIS reportados pelo vsim (resultados/logs/run_measure_bench_*.log),
# para validacao cruzada externa do modelo. Todas as 16 combinacoes bateram
# EXATAMENTE quando este script foi rodado (ver resultados/hit_rate_comparativo.md).
REAL_VSIM = {
    ("streaming", "L1", "lru"):   (94463, 6145),
    ("streaming", "L1", "drrip"): (94463, 6145),
    ("streaming", "L2", "lru"):   (97535, 3073),
    ("streaming", "L2", "drrip"): (97535, 3073),
    ("matrix_conv", "L1", "lru"):   (118880, 8128),
    ("matrix_conv", "L1", "drrip"): (118677, 8331),
    ("matrix_conv", "L2", "lru"):   (122944, 4064),
    ("matrix_conv", "L2", "drrip"): (122747, 4261),
    ("linked_list", "L1", "lru"):   (90112, 8192),
    ("linked_list", "L1", "drrip"): (90112, 8192),
    ("linked_list", "L2", "lru"):   (94208, 4096),
    ("linked_list", "L2", "drrip"): (94208, 4096),
    ("pattern_search", "L1", "lru"):   (12219, 2016),
    ("pattern_search", "L1", "drrip"): (12219, 2016),
    ("pattern_search", "L2", "lru"):   (13226, 1009),
    ("pattern_search", "L2", "drrip"): (13226, 1009),
}

def main():
    import os
    os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    print("="*100)
    for bench, path in BENCH_TRACES.items():
        addrs = load_trace(path)
        for cfg_name, cfg in CONFIGS.items():
            lru = sim_lru(addrs, cfg['blk_b'], cfg['sets'], cfg['ways'])
            drrip = sim_drrip(addrs, cfg['blk_b'], cfg['sets'], cfg['ways'])

            lru_hr = 100.0*lru['hits']/len(addrs)
            drrip_hr = 100.0*drrip['hits']/len(addrs)

            print(f"[{bench:15s} {cfg_name}] n={len(addrs)}  "
                  f"LRU: hits={lru['hits']} misses={lru['misses']} HR={lru_hr:.3f}%   "
                  f"DRRIP: hits={drrip['hits']} misses={drrip['misses']} HR={drrip_hr:.3f}%")
            print(f"    PSEL_final={drrip['psel_final']}  "
                  f"SDM-SRRIP misses={drrip['srrip_sdm_misses']}  SDM-BRRIP misses={drrip['brrip_sdm_misses']}  "
                  f"(diff={drrip['brrip_sdm_misses']-drrip['srrip_sdm_misses']:+d})  "
                  f"follower fills: SRRIP-rule={drrip['follower_srrip_fills']} BRRIP-rule={drrip['follower_brrip_fills']}")

            # validacao cruzada com vsim real
            key_lru = (bench, cfg_name, "lru")
            key_drrip = (bench, cfg_name, "drrip")
            if key_lru in REAL_VSIM:
                rh, rm = REAL_VSIM[key_lru]
                match = "OK" if (rh, rm) == (lru['hits'], lru['misses']) else "DIVERGE!!"
                print(f"    [validacao LRU  vs vsim real] real=({rh},{rm}) modelo=({lru['hits']},{lru['misses']}) -> {match}")
            if key_drrip in REAL_VSIM:
                rh, rm = REAL_VSIM[key_drrip]
                match = "OK" if (rh, rm) == (drrip['hits'], drrip['misses']) else "DIVERGE!!"
                print(f"    [validacao DRRIP vs vsim real] real=({rh},{rm}) modelo=({drrip['hits']},{drrip['misses']}) -> {match}")

            # set 0 isolado (SDM-SRRIP, e onde BASE_HOT=0x00020000 mora)
            s = 0
            lru_set0_acc = lru['per_set_hits'][s] + lru['per_set_misses'][s]
            drrip_set0_acc = drrip['per_set_hits'][s] + drrip['per_set_misses'][s]
            if lru_set0_acc > 0:
                lru_set0_hr = 100.0*lru['per_set_hits'][s]/lru_set0_acc
                drrip_set0_hr = 100.0*drrip['per_set_hits'][s]/drrip_set0_acc
                print(f"    [SET 0 isolado, n={lru_set0_acc}] LRU HR={lru_set0_hr:.3f}%  "
                      f"DRRIP(=SRRIP puro nesse set) HR={drrip_set0_hr:.3f}%  "
                      f"hits LRU={lru['per_set_hits'][s]} hits DRRIP={drrip['per_set_hits'][s]}")

            # quantos sets DIVERGEM entre LRU e DRRIP (misses diferentes)?
            diverging_sets = [i for i in range(cfg['sets']) if lru['per_set_misses'][i] != drrip['per_set_misses'][i]]
            print(f"    sets com per-set miss-count DIFERENTE entre LRU e DRRIP: {len(diverging_sets)}/{cfg['sets']}"
                  f"  {diverging_sets[:10]}{'...' if len(diverging_sets)>10 else ''}")
            print("-"*100)

if __name__ == "__main__":
    main()
