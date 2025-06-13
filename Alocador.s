#Malloc em assembly - Giovanna Fioravante Dalledone GRR:20232370


#Constantes de offset -----------------------------------------
.equ STATUS, 0
.equ TAMANHO, 8
.equ PROX_LIVRE, 16
.equ PRO_OCUPADO, 24
.equ DADOS, 32
#--------------------------------------------------------------

.section	.data
#Variáveis Globais - Inicializações ---------------------------
	topoInicialHeap .quad 0	
	topoHeap		.quad 0
	inicioHeap		.quad 0
	listaLivres		.quad 0			#Lista dos nós livres
	listaOcupados	.quad 0			#Lista dos nós ocupadosi
#--------------------------------------------------------------

.section	.text
.globl		_start

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
	movq %rax, -8(rbp)				#salva rax em -8 x rbp
	movq $0, -16(rbp)				#salva 0 em -16 x rbp (proximo = NULL)

while:
	testq %rax, %rax				#while (bloco)
	jle	fim_while
	
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

	jmp while
	
nao_fundiu:
	#Não fundiu, então avança para o próximo bloco da lista de blocos livres
	movq 16(%rax), %rdx			#acessa o campo do prox_livre(bloco)
	movq %rdx, -8(%rbp)			#salva o próximo bloco na variável local reservada para ele

	jmp while

fim_while:
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
	subq 32, %rcx					#acessa o início do bloco auxiliar
	movq %rcx, -24(%rbp)			#coloca o parâmetro no registrador rcx

	cmpq %rax, %rcx					#Se o bloco auxiliar é o primeiro da lista de ocupados
	jne proximo_lista				#se forem diferentes, pula para o else

	#É o primeiro
	movq $0, 0(%rcx)				#libera o bloco selecionado - status = 0 - OBS: CUIDADOO
	
	#Adiciona na lista de blocos livres
	movq listaLivres, 16(%rax)		#faz o prox_livre do bloco_aux apontar para o início da lista de livres
	movq %rax, listaLivres(%rip)	#faz a lista de livres apontar para o primeiro livre (bloco_aux)

	#Remove da lista de ocupados
	movq 24(%rax), %rdx				#pega o próximo ocupado do bloco selecionado
	movq %rdx, listaOcupados(%rip)	#atualiza a lista de ocupados

	jmp junta_e_desmonta_ra			#salta para desmontar o registro de ativação
	
proximo_lista:
	#Não é o primeiro

	#Procura o bloco na lista
while:
	cmpq %rax, %rcx					#enquando bloco_aux != bloco_selecionado
	je fim_while
	movq %rax, %rbx					#bloco anterior (rbx) = bloco auxiliar
	movq 24(%rax), %rax				#bloco auxiliar (rax) = prox_ocupado(bloco_auxiliar) e mantém em rax
	jmp while

fim_while:
	#Agora, achou os blocos

	movq $0, 0(%rax)				#libera o bloco

	#Adiciona na lista de livres
	movq listaLivres, 16(%rax)		#faz o prox_livre(bloco_aux) apontar para o início da lista de livres
	movq %rax, listaLivres(%rip)	#faz a lista de livres apontar para o primeiro livre (bloco_aux)

	#Remove da lista de ocupados
	movq 24(%rax), 24(%rbx)			#prox_ocupado do bloco_aux para dentro do prox_ocupado do bloco anterior

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
	movq listaLivres, %rax		#ptr_livres = listaLivres
	movq %rax, -8(%rbp)			#ptr_livres vai ficar em rax
	movq $0, %rbx				#bloco_anterior = NULL
	movq %rbx, -16(%rbp)		#blco_anterior vai ficar em rbx
	movq $0, %rcx				#bloco = NULL
	movq %rcx, -24(%rbp)		#bloco vai ficar em rcx

	#Parâmetro da função
	movq 8(%rbp), %rdx			#rdx tem num_bytes

	#Procura o bloco na lista de livres
while:
	testq %rax, %rax			#testa se %rax não é nulo
	je fim_laco
	movq 0(%rax), %r8			#guarda o status(ptr_livre) em r8
	cmpq $0, %r8				#compara se o conteúdo do status é zero
	jne else					#se não forem iguais, vai para o else atualizar os ponteiros
	movq 8(%rax), %r9			#coloca tamanho(ptr_livre) em r9
	cmpq %rdx, %r9				#compara tamanho com num_bytes (tamanho >= num_bytes)
	jl else						#salta se o tamanho for menor do que num_bytes
	movq %rax, %rcx				#encontrou o bloco, então coloca em rcx e sai do laço
	jmp fim_laco

else:
	#Atlualiza os ponteiros
	movq %rax, %rbx						#move ptr_livres para bloco_anterior
	movq 16(%rax), %rax					#ptr_livres = prox_livre(ptr_livres)

	jmp while
fim_laco:
	#Altera as listas
	testq %rcx, %rcx					#testa se bloco (rcx) é nulo
	je aloca_novo_bloco				#se for nulo, salta para alocar um novo bloco

	#Bloco não é nulo
	movq $1, 0(%rcx)					#altera o estado do bloco para ocupado

testa_bloco_anterior:
	#Atualiza ponteiros
	testq %rbx, %rbx					#testa se o bloco anterior é nulo
	je	eh_nulo							#é nulo, então salta para eh_nulo
	movq 16(%rcx), 16(%rbx)				#remove da lista de livres
	jmp lista_ocupados					#vai ajustar a lista de ocupados
	
eh_nulo:								#É nulo, então não tem anterior
	movq 16(%rcx), listaLivres(%rip)	#remove o bloco rcx da lista de livres

lista_ocupados:
	movq $0, 16(%rcx)					#prox_livre(bloco) = 0

	#Ajusta os ponteiros dos blocos ocupados
	testq listaOcupados, listaOcupados
	je lista_nula						#se for nulo, salta para lista_nula
	movq listaOcupados(%rip), 24(%rcx)	#prox_ocupado(bloco) = listaOcupados
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
