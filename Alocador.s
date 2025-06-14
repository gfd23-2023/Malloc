#Malloc em assembly - Giovanna Fioravante Dalledone GRR:20232370


#Constantes de offset -----------------------------------------
.equ STATUS, 0
.equ TAMANHO, 8
.equ PROX_LIVRE, 16
.equ PRO_OCUPADO, 24
.equ DADOS, 32
#--------------------------------------------------------------

.section	.rodata
hash_symbol:
	.asciz "#"						#string com '#' + terminador nulo

newline:
	.asciz "\n"						#string para quebra de linha (usada no fim do mapa)

.section	.data
#Variáveis Globais - Inicializações ---------------------------
	topoInicialHeap:.quad 0	
	topoHeap:		.quad 0
	inicioHeap:		.quad 0
	listaLivres:	.quad 0			#Lista dos nós livres
	listaOcupados:	.quad 0			#Lista dos nós ocupadosi
#--------------------------------------------------------------

.section	.text
.globl		iniciaAlocador, finalizaAlocador, juntaBloco, liberaMem, alocaMem, imprimeMapa, main

#----------------------------------------------------------------------------------------------------------------------
#Executa syscall brk para obter o endereço do topo da pilha e o armazena em uma variável global
iniciaAlocador:
	pushq %rbp						#antiga posição da pilha - montagem RA
	movq %rsp, %rbp					#passa a nova altura da pinha - montagem RA
	movq $12, %rax					#move o número da syscall brk para rax
	xorq %rdi, %rdi					#zera o registrador %rdi (argumento da syscall brk) - topoInicialHeap = sbrk(0)
	syscall
	movq %rax, topoHeap				#topoHeap = topoInicialHeap
	movq %rax, inicioHeap			#inicioHeap = topoInicialHeap
	ret
#----------------------------------------------------------------------------------------------------------------------
#Executa syscall brk para restaurar o topo inicial da Heap	
finalizaAlocador:
	pushq %rbp						#antiga posição da pilha
	movq %rsp, %rbp					#passa a nova altura da pilha - montagem RA
	movq $12, %rax					#move o npumero da syscall brk para rax
	movq topoInicialHeap, %rdi		#passa o topo inicial como argumento da sbrk
	syscall
	movq %rax, topoHeap				#topoHeap = endereço restaurado da heap
	ret
#----------------------------------------------------------------------------------------------------------------------
#Realiza a fusão de dois blocos livres
juntaBloco:
	pushq %rbp						#antiga posição da pilha - montagem RA
	movq %rsp, %rbp					#passa a nova altura da pilha - montagem RA
	subq $16, %rsp					#espaço para 'bloco = listaLivres' e 'proximo = NULL' - montagem RA

	#Inicialização das variáveis
	movq listaLivres(%rip), %rax	#rax -> bloco = listaLivres
	movq %rax, -8(%rbp)				#salva rax em -8 x rbp
	movq $0, -16(%rbp)				#salva 0 em -16 x rbp (proximo = NULL)

while1:
	testq %rax, %rax				#while (bloco)
	jle	fim_while1
	
	#proximo = PROX_LIVRE(bloco)
	movq -8(%rbp), %rax			#pega o valor local da variável bloco e guarda em rax
	movq 16(%rax), %rdx			#move bloco + 16 para proximo (rdx)
	movq %rdx, -16(%rbp)		#armazena em 'proximo'
	
	#Verifica se o próximo bloco não é nulo (bloco em rax e rdx, proximo em rbx e rcx)
	movq -16(%rbp), %rcx		#pega 'proximo' e coloca em rcx
	testq %rcx, %rcx			#testa se rcx não é nulo
	je nao_fundiu				#se for nulo, não funde nada e cai fora

	#Verifica se os blocos são vizinhos fisicamente na memória
	movq -16(%rbp), %rbx		#coloca o 'proximo' em rbx
	movq 8(%rax), %rdx			#acessa o campo de tamanho(bloco) e guarda em rdx
	addq $32, %rdx				#soma 32 para acessar o campo de dados do bloco
	cmpq %rbx, %rdx				#verifica se os endereços são iguais, caso sejam, vai fundir os blocos
	jne nao_fundiu

	#Fundiu, então, atualiza o tamanho do blocão (bloco em rax e rdx, proximo em rbx e rcx)
	movq 8(%rbx), %rcx			#acessa o campo de tamanho(proximo) e guarda em rcx
	movq 8(%rax), %rdx			#acesse o campo de tamanho(bloco) e guarda em rdx
	addq %rdx, %rcx				#soma os dois campos de tamanho
	addq $32, %rcx				#soma o campo dos dados
	movq %rcx, 8(%rax)			#salva o novo tamanho dentro do bloco

fim_fusao:
	#Atualiza os ponteiros do blocão fundido
	movq 16(%rax), %rdx			#acessa o campo do prox_livre(bloco)
	movq 16(%rbx), %rcx			#acessa o campo do prox_livre(prox)
	movq %rdx, 16(%rax)			#salva o novo valor do prox_livre
	
	movq %rdx, -8(%rbp)			#avança para o próximo bloco

	jmp while1
	
nao_fundiu:
	#Não fundiu, então avança para o próximo bloco da lista de blocos livres
	movq 16(%rax), %rdx			#acessa o campo do prox_livre(bloco)
	movq %rdx, -8(%rbp)			#salva o próximo bloco na variável local reservada para ele

	jmp while1

fim_while1:
	addq $16, %rsp				#libera o espaço das VL - desmontagem RA
	popq %rbp					#restaura o topo da pilha - desmontagem RA
	ret
#----------------------------------------------------------------------------------------------------------------------
#Recebe como parâmetro o endereço dos dados do bloco e o marca como livre
#Lembre-se, o parâmetro é empilhado no código principal
liberaMem:
	pushq %rbp					#antiga posição na pilha - montagem RA
	movq %rsp, %rbp				#passa a nova altura da pilha - montagem RA
	subq $24, %rbp				#separa espaço para as variáveis - montagem RA

	#Inicialização das variáveis
	movq listaOcupados(%rip), %rax	#bloco_aux vai ficar em rax
	movq %rax, -8(%rbp)				#bloco_aux
	movq $0, -16(%rbp)				#bloco_anterior (vai ficar em rbx)
	movq 8(%rbp), %rcx				#carrega o parâmetro para rcx
	subq $32, %rcx					#acessa o início do bloco auxiliar
	movq %rcx, -24(%rbp)			#coloca o parâmetro no registrador rcx

	cmpq %rax, %rcx					#Se o bloco auxiliar é o primeiro da lista de ocupados
	jne proximo_lista				#se forem diferentes, pula para o else

	#É o primeiro
	movq $0, 0(%rcx)				#libera o bloco selecionado - status = 0 - OBS: CUIDADOO
	
	#Adiciona na lista de blocos livres
	movq listaLivres(%rip), %rcx	#faz o prox_livre do bloco_aux apontar para o início da lista de livres
	movq %rcx, 16(%rax)             # Atualiza prox_livre do novo bloco
	movq %rax, listaLivres(%rip)	#faz a lista de livres apontar para o primeiro livre (bloco_aux)

	#Remove da lista de ocupados
	movq 24(%rax), %rdx				#pega o próximo ocupado do bloco selecionado
	movq %rdx, listaOcupados(%rip)	#atualiza a lista de ocupados

	jmp junta_e_desmonta_ra			#salta para desmontar o registro de ativação
	
proximo_lista:
	#Não é o primeiro

	#Procura o bloco na lista
while2:
	cmpq %rax, %rcx					#enquando bloco_aux != bloco_selecionado
	je fim_while
	movq %rax, %rbx					#bloco anterior (rbx) = bloco auxiliar
	movq 24(%rax), %rax				#bloco auxiliar (rax) = prox_ocupado(bloco_auxiliar) e mantém em rax
	jmp while2

fim_while2:
	#Agora, achou os blocos

	movq $0, 0(%rax)				#libera o bloco

	#Adiciona na lista de livres
	movq listaLivres(%rip), %r9		#faz o prox_livre(bloco_aux) apontar para o início da lista de livres
	movq %r9, 16(%rax)
	movq %rax, listaLivres(%rip)	#faz a lista de livres apontar para o primeiro livre (bloco_aux)

	#Remove da lista de ocupados
	movq 24(%rax), %r9
	movq %r9, 24(%rbx)

junta_e_desmonta_ra:
	#Junta os blocos livres
	call juntaBloco

	addq 24, %rbp				#libera o espaço reservado para as variáveis - desmontagem RA
	popq %rbp					#restaura o valor da pilha
	ret
#----------------------------------------------------------------------------------------------------------------------
#Procura um bloco livre com tamanho maior ou igual a num_bytes
#Caso encontre, marca como ocupado e retorna o ponteiro para o endereço inicial do bloco
#Se não encontrar, abre espaço para um novo bloco, com a syscall brk, marca como ocupado e devolve o ponteiro para ele
alocaMem:
	pushq %rbp					#antiga posição da pilha - montagem RA
	movq %rsp, %rbp				#passa a nova altura da pilha - montagem RA
	subq $24, %rbp				#aloca espaço para as variáveis locais

	#Inicialização das variáveis locais
	movq listaLivres(%rip), %rax#ptr_livres = listaLivres
	movq %rax, -8(%rbp)			#ptr_livres vai ficar em rax
	movq $0, %rbx				#bloco_anterior = NULL
	movq %rbx, -16(%rbp)		#blco_anterior vai ficar em rbx
	movq $0, %rcx				#bloco = NULL
	movq %rcx, -24(%rbp)		#bloco vai ficar em rcx

	#Parâmetro da função
	movq 8(%rbp), %rdx			#rdx tem num_bytes

	#Procura o bloco na lista de livres
while3:
	testq %rax, %rax			#testa se %rax não é nulo
	je fim_laco3
	movq 0(%rax), %r8			#guarda o status(ptr_livre) em r8
	cmpq $0, %r8				#compara se o conteúdo do status é zero
	jne else					#se não forem iguais, vai para o else atualizar os ponteiros
	movq 8(%rax), %r9			#coloca tamanho(ptr_livre) em r9
	cmpq %rdx, %r9				#compara tamanho com num_bytes (tamanho >= num_bytes)
	jl else						#salta se o tamanho for menor do que num_bytes
	movq %rax, %rcx				#encontrou o bloco, então coloca em rcx e sai do laço
	jmp fim_laco3

else:
	#Atlualiza os ponteiros
	movq %rax, %rbx						#move ptr_livres para bloco_anterior
	movq 16(%rax), %rax					#ptr_livres = prox_livre(ptr_livres)

	jmp while3
fim_laco3:
	#Altera as listas
	testq %rcx, %rcx					#testa se bloco (rcx) é nulo
	je aloca_novo_bloco				#se for nulo, salta para alocar um novo bloco

	#Bloco não é nulo
	movq $1, 0(%rcx)					#altera o estado do bloco para ocupado

testa_bloco_anterior:
	#Atualiza ponteiros
	testq %rbx, %rbx					#testa se o bloco anterior é nulo
	je	eh_nulo							#é nulo, então salta para eh_nulo
	movq 16(%rcx), %r10					#remove da lista de livres
	movq %r10, 16(%rbx)
	jmp lista_ocupados					#vai ajustar a lista de ocupados
	
eh_nulo:								#É nulo, então não tem anterior
	movq 16(%rcx), %r9					#remove o bloco rcx da lista de livres
	movq %r9, listaLivres(%rip)

lista_ocupados:
	movq $0, 16(%rcx)					#prox_livre(bloco) = 0

	#Ajusta os ponteiros dos blocos ocupados
	movq listaOcupados(%rip), %r10
	testq %r10, %r10
	je lista_nula						#se for nulo, salta para lista_nula
	movq listaOcupados(%rip), %r9		#prox_ocupado(bloco) = listaOcupados
	movq %r9, 24(%rcx)
	movq %rcx, listaOcupados(%rip)		#insere no início

	jmp retorno							#bloco alocado, ponteiros ajustados, então pode retornar

lista_nula:
	movq %rcx, listaOcupados			#então bloco é o primeiro ocupado
	movq $0, 24(%rcx)					#prox_ocupado(bloco) = null

	jmp retorno							#bloco alocado, ponteiros ajustados então pode retornar

aloca_novo_bloco:
	#Abre espaço para o novo bloco
	movq topoHeap, %rdi					#pega o tamanho atual da heap
	movq topoHeap, %rcx					#bloco = topoHeap

	movq $32, %rsi						#auxiliar recebe 32
	addq $rdx, %rsi						#soma 32 com num_bytes e guarda no auxiliar
	addq %rsi, %rdi						#heap recebe o novo topo
	movq $12, %rax						#coloca o número da syscall em rax
	syscall
	movq %rax, topoHeap					#move o novo bloco para o topo da heap para dentro de topoHeap
	
	#Atualiza os campos do novo bloco que está em rcx

	movq $1, 0(%rcx)					#status ocupado
	movq %rdx, 8(%rcx)					#tamanho = num_bytes
	movq $0, 16(%rcx)					#prox_livre = nulo

	#Ponteiro de prox_ocupado
	jmp testa_bloco_anterior

retorno:
	addq $32, %rcx				#pega o ponteiro para os dados
	movq %rcx, %rax				#armazena o bloco em rax (retorno da função)
	addq $24, %rbp				#libera o espaço reservado para as variáveis locais - desmontagem RA
	popq %rbp					#restaura o valor da altura da pilha - desmontagem - RA
	ret
#----------------------------------------------------------------------------------------------------------------------
#Imprime o mapa da heap
#Blocos gerenciais impressos com '#'
#Se o bloco estiver livre, imprime '-', caso contrário, imprime '+'
imprimeMapa:
	pushq %rbp							#antiga posição da pilha - montagem RA
	movq %rsp, %rbp						#salva nova altura da pilha - montagem RA
	pushq %rbx							#preserva rbx (vai ser ptr_bloco)
	pushq %r12							#vai ser usado para contadores
	subq $8, %rsp						#alinha a pilha para 16 bytes 

	#Inicializa o ponteiro dos blocos
	movq inicioHeap(%rip), %rbx			#prt_bloco = inicioHeap

mapa_loop:
	#Verifica se chegou ao final da heap
	cmpq topoHeap(%rip), %rbx			#compara prt_bloco com topoHeap
	jge fim_mapa						#se for maior ou igual que topoHeap, termina

	#Imprime dados gerenciais '#'
	movq $32, %r12						#inicializa contador com i = 32
cabecalho_loop:
	#Configura syscall write (1, '#', 1)
	movq $1, %rax						#número da syscall write
	movq $1, %rdi						#stdout = 1
	leaq hash_symbol(%rip), %rsi		#endereço do caractere '#'
	movq $1, %rdx						#número de bytes para escrever

	pushq %r12							#preserva o contador, porque a syscall pode alterar o valor
	syscall								#executa a escrita
	popq %r12							#restaura o contador

	decq %r12							#decrementa o contador i--
	jnz cabecalho_loop

	#Determina o símbolo para imprimir '+' ou '-'
	cmpq $0, 0(%rbx)					#verifica o status do bloco
	je bloco_livre						#se não saltar, é porque está ocupado
	movq $'+', %r12						#símbolo de ocupado
	jmp imprime_dados					#pula para a impressão

bloco_livre:
	movq $'-', %r12						#símbolo de livre em r12

imprime_dados:
	#Tamanho vezes símbolo
	movq 8(%rbx), %rcx					#carrega o tamanho do bloco em rcx
	testq %rcx, %rcx					#verifica se o tamanho não é nulo
	jz proximo_bloco					#se o tamanho for zero, pula para o próximo bloco

dados_loop:
	#Imprime o símbolo
	movq %r12, %rsi						#coloca o símbolo em rsi
	movq $1, %rax						#write
	movq $1, %rdi						#stdout
	movq $1, %rdx						#tamanho 1
	syscall

	loop dados_loop						#decrementa o tamanho (rcx) e repeta se rcx > 0

proximo_bloco:
	#Avança para o próximo bloco na heap
	movq 8(%rbx), %rax					#carrega o tamanho do bloco
	addq $32, %rax						#soma ao tamanho do cabeçalho
	addq %rax, %rbx						#avança prt_bloco para o próximo bloco

	jmp mapa_loop						#volta para o início do bloco

fim_mapa:
	#Finalização: imprime nova linha e restaura os registradores
	movq $'\n', %rdi					#carrega o caractere nova linha
	movq %rdi, %rsi						#coloca o símbolo em rsi
	movq $1, %rax						#write
	movq $1, %rdi						#stdout
	movq $1, %rdx						#tamanho 1
	syscall

	#Desmontagem do RA
	addq $8, %rsp						#remove o espaço de alinhamento
	popq %r12							#restaura r12
	popq %rbx							#restaura rbx
	popq %rbp							#restaura rbp
	ret
#----------------------------------------------------------------------------------------------------------------------
#Código Principal
main:
    pushq %rbp
    movq %rsp, %rbp
    subq $16, %rsp              # Espaço para variáveis locais (a e b)

    # iniciaAlocador()
    call iniciaAlocador

    # imprimeMapa() - vazio
    call imprimeMapa

    # a = alocaMem(10)
    movq $10, %rdi
    call alocaMem
    movq %rax, -8(%rbp)         # Armazena 'a' na stack

    # imprimeMapa() - ################**********
    call imprimeMapa
    # b = alocaMem(4)
    movq $4, %rdi
    call alocaMem
    movq %rax, -16(%rbp)        # Armazena 'b' na stack

    # imprimeMapa() - ################**********##############****
    call imprimeMapa

    # liberaMem(a)
    movq -8(%rbp), %rdi
    call liberaMem

    # imprimeMapa() - ################----------##############****
    call imprimeMapa

    # liberaMem(b)
    movq -16(%rbp), %rdi
    call liberaMem

    # imprimeMapa() - resultado final
    call imprimeMapa

    # finalizaAlocador()
    call finalizaAlocador

    # return 0
    xorq %rax, %rax
    addq $16, %rsp
    popq %rbp
    ret
#----------------------------------------------------------------------------------------------------------------------

