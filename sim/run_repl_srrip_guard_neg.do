# run_repl_srrip_guard_neg.do
# Script do ModelSim para o teste NEGATIVO dedicado do guard de elaboracao
# de repl_srrip.v (RRPV_BITS < 1), ressalva MENOR #2 da revisao rtl-analyst
# da Fase 3.
#
# *** ESTE TESTE PASSA QUANDO A ELABORACAO FALHA. ***
# Ao contrario de todos os outros scripts .do deste projeto (que esperam
# "RESULTADO: PASS" apos uma simulacao normal), este script instancia
# DELIBERADAMENTE uma configuracao invalida (RRPV_BITS=0, ver
# tb/repl_srrip_guard_neg_tb.v) e o CRITERIO DE SUCESSO e a propria
# elaboracao FALHAR com erro fatal -- ou pelo guard explicito de
# repl_srrip.v (instancia de modulo-guard proposital inexistente
# repl_srrip_requires_rrpv_bits_ge_1_do_not_instantiate_with_other_config),
# ou pelo proprio erro nativo de "replication multiplier" do Verilog ao
# calcular RRPV_MAX/RRPV_INSERT com RRPV_BITS=0 (ver comentario detalhado no
# cabecalho de rtl/repl_srrip.v sobre qual dos dois dispara primeiro nesta
# toolchain -- verificado experimentalmente: o proprio calculo falha antes
# do bloco `generate` do guard ser avaliado).
#
# COMO VERIFICAR O RESULTADO (2 formas, ambas validas):
#   1) exit code do PROCESSO vsim: quando a elaboracao falha dentro do -do,
#      o `vsim -c -do sim/run_repl_srrip_guard_neg.do` inteiro termina com
#      exit code != 0 (comprovado experimentalmente: 12, nao 0). Rodar:
#        vsim -c -do sim/run_repl_srrip_guard_neg.do ; echo "exit=$?"
#      e conferir exit != 0  ==>  GUARD OK (teste negativo PASSOU).
#      exit == 0  ==>  GUARD QUEBRADO (teste negativo FALHOU).
#   2) inspecao do log: a mensagem "Error loading design" (ou os erros de
#      "Replication multiplier"/instancia nao encontrada) deve aparecer, e
#      NENHUMA linha "RESULTADO: PASS" (esse texto so existe no testbench
#      NORMAL de repl_srrip.v, nao no negativo) -- ver
#      tb/repl_srrip_guard_neg_tb.v: se a elaboracao (contra toda a
#      expectativa) suceder, o proprio testbench imprime "FALHA DO GUARD"
#      de forma explicita, nunca "PASS".
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_repl_srrip_guard_neg.do ; echo "exit code: $?"
# ou, dentro do ModelSim GUI (com cwd = /home/miguel/verilog):
#   do sim/run_repl_srrip_guard_neg.do
#
# NAO faz parte do fluxo normal de simulacao -- run_repl_srrip.do (o script
# do dia a dia) NUNCA compila tb/repl_srrip_guard_neg_tb.v, exatamente para
# nao misturar um teste que deve falhar com a suite normal que deve passar.
# Este script tambem NUNCA e chamado por run_repl_srrip.do.

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/repl_srrip.v tb/repl_srrip_guard_neg_tb.v
vsim -c work.repl_srrip_guard_neg_tb

# Se a linha `vsim` acima nao abortar o script inteiro (ou seja, se a
# elaboracao da config invalida "vazou" e sucedeu), chegamos aqui -- rodamos
# mesmo assim para deixar o proprio testbench imprimir seu veredito negativo
# explicito ("FALHA DO GUARD..."), e o script termina normalmente (exit 0),
# sinalizando corretamente que o guard NAO bloqueou a config invalida.
run -all
quit -f
