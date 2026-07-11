# run_repl_brrip_guard_neg.do
# Script do ModelSim para o teste NEGATIVO dedicado do guard de elaboracao
# (NOVO neste modulo) de repl_brrip.v: BRRIP_THROTTLE_BITS < 1.
#
# *** ESTE TESTE PASSA QUANDO A ELABORACAO FALHA. ***
# Ao contrario de todos os outros scripts .do deste projeto (que esperam
# "RESULTADO: PASS" apos uma simulacao normal), este script instancia
# DELIBERADAMENTE uma configuracao invalida (BRRIP_THROTTLE_BITS=0, ver
# tb/repl_brrip_guard_neg_tb.v) e o CRITERIO DE SUCESSO e a propria
# elaboracao FALHAR com erro fatal -- pelo guard explicito de repl_brrip.v
# (instancia de modulo-guard proposital inexistente
# repl_brrip_requires_throttle_bits_ge_1_do_not_instantiate_with_other_config).
#
# COMO VERIFICAR O RESULTADO (2 formas, ambas validas, mesmo padrao de
# sim/run_repl_srrip_guard_neg.do da Fase 3):
#   1) exit code do PROCESSO vsim: quando a elaboracao falha dentro do -do,
#      o `vsim -c -do sim/run_repl_brrip_guard_neg.do` inteiro termina com
#      exit code != 0. Rodar:
#        vsim -c -do sim/run_repl_brrip_guard_neg.do ; echo "exit=$?"
#      e conferir exit != 0  ==>  GUARD OK (teste negativo PASSOU).
#      exit == 0  ==>  GUARD QUEBRADO (teste negativo FALHOU).
#   2) inspecao do log: a mensagem "Error loading design" (apontando para o
#      nome do modulo-guard inexistente) deve aparecer, e NENHUMA linha
#      "RESULTADO: PASS" (esse texto so existe no testbench NORMAL de
#      repl_brrip.v, nao no negativo) -- ver tb/repl_brrip_guard_neg_tb.v:
#      se a elaboracao (contra toda a expectativa) suceder, o proprio
#      testbench imprime "FALHA DO GUARD" de forma explicita, nunca "PASS".
#
# Uso (a partir de /home/miguel/verilog):
#   vsim -c -do sim/run_repl_brrip_guard_neg.do ; echo "exit code: $?"
# ou, dentro do ModelSim GUI (com cwd = /home/miguel/verilog):
#   do sim/run_repl_brrip_guard_neg.do
#
# NAO faz parte do fluxo normal de simulacao -- run_repl_brrip.do (o script
# do dia a dia) NUNCA compila tb/repl_brrip_guard_neg_tb.v, exatamente para
# nao misturar um teste que deve falhar com a suite normal que deve passar.
# Este script tambem NUNCA e chamado por run_repl_brrip.do.

if {[file exists work]} {
    vdel -lib work -all
}

vlib work
vlog rtl/repl_brrip.v tb/repl_brrip_guard_neg_tb.v
vsim -c work.repl_brrip_guard_neg_tb

# Se a linha `vsim` acima nao abortar o script inteiro (ou seja, se a
# elaboracao da config invalida "vazou" e sucedeu), chegamos aqui -- rodamos
# mesmo assim para deixar o proprio testbench imprimir seu veredito negativo
# explicito ("FALHA DO GUARD..."), e o script termina normalmente (exit 0),
# sinalizando corretamente que o guard NAO bloqueou a config invalida.
run -all
quit -f
