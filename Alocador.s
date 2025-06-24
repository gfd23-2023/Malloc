#Malloc em assembly - Giovanna Fioravante Dalledone GRR:20232370


#Constantes de offset -----------------------------------------
.equ STATUS, 0
.equ TAMANHO, 8
.equ PROX_LIVRE, 16
.equ PROX_OCUPADO, 24
.equ DADOS, 32
#--------------------------------------------------------------

.section	.rodata
hash_symbol:
	.asciz "#"						#string com '#' + terminador nulo

newline:
	.asciz "\n"						#string para quebra de linha (usada no fim do mapa)

.section	.data
#Variáveis Globais - Inicializações ---------------------------
	.align 16
	topoInicialHeap:.quad 0	
	topoHeap:		.quad 0
	inicioHeap:		.quad 0
	listaLivres:	.quad 0			#Lista dos nós livres
	listaOcupados:	.quad 0			#Lista dos nós ocupadosi
#--------------------------------------------------------------

.section .bss
.align 8
char_buffer:
    .space 1


.section	.text
.globl		iniciaAlocador, finalizaAlocador, juntaBloco, liberaMem, alocaMem, imprimeMapa, main

#----------------------------------------------------------------------------------------------------------------------
#Executa syscall brk para obter o endereço do topo da pilha e o armazena em uma variável global
iniciaAlocador:
    pushq %rbp
    movq %rsp, %rbp
    
    # Obtém o topo atual da heap
    movq $12, %rax      # syscall brk
    xorq %rdi, %rdi     # argumento 0 (obter topo atual)
    syscall
    movq %rax, topoInicialHeap
    movq %rax, inicioHeap
    movq %rax, topoHeap
    
    popq %rbp
    ret
    
erro_inicializacao:
    # Tratamento de erro
    movq $-1, %rax
    popq %rbp
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
	popq %rbp
	ret
#----------------------------------------------------------------------------------------------------------------------
#Realiza a fusão de dois blocos livres
juntaBloco:
	pushq %rbp						#antiga posição da pilha - montagem RA
	movq %rsp, %rbp					#passa a nova altura da pilha - montagem RA
	subq $16, %rsp					#espaço para 'bloco = listaLivres' e 'proximo = NULL' - montagem RA

	#Inicialização das variáveis
	movq listaLivres, %rax	#rax -> bloco = listaLivres
	movq %rax, -8(%rbp)				#salva rax em -8 x rbp
	movq $0, -16(%rbp)				#salva 0 em -16 x rbp (proximo = NULL)

while1:
	testq %rax, %rax				#while (bloco)
	jz	fim_while1
	
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
	movq 8(%rbx), %rcx          # tamanho do proximo
	movq 8(%rax), %rdx          # tamanho do bloco
	addq %rdx, %rcx
	addq $32, %rcx              # soma cabeçalho do proximo
	movq %rcx, 8(%rax)          # atualiza novo tamanho no bloco fundido

fim_fusao:
	#Atualiza os ponteiros do blocão fundido
	movq 16(%rbx), %rcx         # pega prox_livre do proximo
	movq %rcx, 16(%rax)         # atualiza no bloco fundido

	movq %rdx, -8(%rbp)			#avança para o próximo bloco

	jmp while1
	
nao_fundiu:
	#Não fundiu, então avança para o próximo bloco da lista de blocos livres
	movq 16(%rax), %rdx			#acessa o campo do prox_livre(bloco)
	movq %rdx, -8(%rbp)			#salva o próximo bloco na variável local reservada para ele
	movq -8(%rbp), %rax

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
	subq $24, %rsp				#separa espaço para as variáveis - montagem RA

	#Inicialização das variáveis
	movq listaOcupados, %rax	#bloco_aux vai ficar em rax
	movq %rax, -8(%rbp)				#bloco_aux
	movq $0, -16(%rbp)				#bloco_anterior (vai ficar em rbx)
	movq %rdi, %rcx				#carrega o parâmetro para rcx
	subq $32, %rcx					#acessa o início do bloco auxiliar
	movq %rcx, -24(%rbp)			#coloca o parâmetro no registrador rcx

	cmpq %rax, %rcx					#Se o bloco auxiliar é o primeiro da lista de ocupados
	jne proximo_lista				#se forem diferentes, pula para o else

	#É o primeiro
	movq $0, 0(%rcx)				#libera o bloco selecionado - status = 0 - OBS: CUIDADOO
	
	#Adiciona na lista de blocos livres
	movq listaLivres, %rcx	#faz o prox_livre do bloco_aux apontar para o início da lista de livres
	movq %rcx, 16(%rax)             # Atualiza prox_livre do novo bloco
	movq %rax, listaLivres	#faz a lista de livres apontar para o primeiro livre (bloco_aux)

	#Remove da lista de ocupados
	movq 24(%rax), %rdx				#pega o próximo ocupado do bloco selecionado
	movq %rdx, listaOcupados	#atualiza a lista de ocupados

	jmp junta_e_desmonta_ra			#salta para desmontar o registro de ativação
	
proximo_lista:
	#Não é o primeiro

	#Procura o bloco na lista
while2:
	cmpq %rcx, %rax					#enquando bloco_aux != bloco_selecionado
	je fim_while2
	
	#cmpq $0, %rax                       # NOVO: checa se bloco_aux é NULL
    #je fim_while2                       # Evita acessar memória inválida

	movq %rax, %rbx					#bloco anterior (rbx) = bloco auxiliar
	movq %rax, %r12
	movq 24(%rax), %r10				#bloco auxiliar (rax) = prox_ocupado(bloco_auxiliar) e mantém em rax
	movq %r10, %rax

	testq %rax, %rax
    jz fim_while2

	jmp while2

fim_while2:
	#Agora, achou os blocos
    # Achou o bloco: rax = bloco_aux, rbx = bloco_anterior

    movq $0, 0(%rax)                # libera o bloco corretamente

    # Adiciona na lista de livres
    movq listaLivres, %r9     # r9 = início da lista de livres
    movq %r9, 16(%rax)              # prox_livre(bloco) = listaLivres
    movq %rax, listaLivres    # listaLivres = bloco

    # Remove da lista de ocupados
    movq 24(%rax), %r9              # r9 = próximo ocupado
    movq %r9, 24(%rbx)              # prox_ocupado(bloco_anterior) = prox_ocupado(bloco)
	

junta_e_desmonta_ra:
	#Junta os blocos livres
	call juntaBloco

	addq $24, %rsp				#libera o espaço reservado para as variáveis - desmontagem RA
	popq %rbp					#restaura o valor da pilha
	ret
#----------------------------------------------------------------------------------------------------------------------
#Procura um bloco livre com tamanho maior ou igual a num_bytes
#Caso encontre, marca como ocupado e retorna o ponteiro para o endereço inicial do bloco
#Se não encontrar, abre espaço para um novo bloco, com a syscall brk, marca como ocupado e devolve o ponteiro para ele
alocaMem:
    pushq %rbp
    movq %rsp, %rbp
    subq $32, %rsp              # Espaço para variáveis locais

    # Inicialização
    movq listaLivres, %rax
    movq %rax, -8(%rbp)         # ptr_livres
    movq $0, -16(%rbp)          # bloco_anterior
    movq $0, -24(%rbp)          # bloco
    #movq 16(%rbp), %rdx         # num_bytes (parâmetro)
	movq %rdi, %rdx

while3:
    cmpq $0, -8(%rbp)
    je fim_laco3
    
    movq -8(%rbp), %rax
    cmpq $0, STATUS(%rax)       # Verifica se está livre
    jne else
    movq TAMANHO(%rax), %r9
    cmpq %rdx, %r9              # Verifica se tem tamanho suficiente
    jl else
    movq %rax, -24(%rbp)        # Bloco encontrado
    jmp fim_laco3

else:
    movq -8(%rbp), %rax                # rax = ptr_livre
    movq %rax, -16(%rbp)               # bloco_anterior = ptr_livre 
    movq PROX_LIVRE(%rax), %rax
    movq %rax, -8(%rbp)                # ptr_livre = ptr_livre->prox_livre
    jmp while3

fim_laco3:
    cmpq $0, -24(%rbp)
    je aloca_novo_bloco

    # Usar bloco existente
    movq -24(%rbp), %rcx
    movq $1, STATUS(%rcx)       # Marca como ocupado

    cmpq $0, -16(%rbp)
    je eh_nulo
    
    movq -16(%rbp), %rbx               # rbx = bloco_anterior
    movq PROX_LIVRE(%rcx), %r10
    movq %r10, PROX_LIVRE(%rbx)
    jmp lista_ocupados

eh_nulo:
    movq PROX_LIVRE(%rcx), %r9
    movq %r9, listaLivres

lista_ocupados:
    movq $0, PROX_LIVRE(%rcx)
    
    movq listaOcupados, %r10
    cmpq $0, %r10
    je lista_nula
    
    movq listaOcupados, %r9
    movq %r9, PROX_OCUPADO(%rcx)
    movq %rcx, listaOcupados
    jmp retorno

lista_nula:
    movq %rcx, listaOcupados
    movq $0, PROX_OCUPADO(%rcx)
    jmp retorno

aloca_novo_bloco:
    # Calcula tamanho total necessário (alinhado para 16 bytes)
    movq %rdx, %rsi             # num_bytes
    addq $32, %rsi              # tamanho do cabeçalho
    addq $15, %rsi              # alinhamento
    andq $-16, %rsi             # garante múltiplo de 16

    # Obtém endereço atual do topo
    movq topoHeap, %rcx
	movq topoHeap, %r12

    # Calcula novo topo
    movq %rcx, %rdi
    addq %rsi, %rdi

    # Chama brk para alocar espaço
    movq $12, %rax
    syscall

    # Verifica erro
    cmpq %rdi, %rax
    jne erro_alocacao

    # Atualiza topoHeap
    movq %rax, topoHeap

	movq %r12, %rcx
	movq %rcx, -24(%rbp)

    # Inicializa o novo bloco
    movq $1, STATUS(%rcx)       # status = ocupado
    movq %rdx, TAMANHO(%rcx)    # tamanho original (sem cabeçalho)
    movq $0, PROX_LIVRE(%rcx)
    movq $0, PROX_OCUPADO(%rcx)

    # Adiciona à lista de ocupados
    movq listaOcupados, %rdx
    movq %rdx, PROX_OCUPADO(%rcx)
    movq %rcx, listaOcupados

	movq %rcx, -24(%rbp)

    jmp retorno

retorno:
    movq -24(%rbp), %rax
    addq $32, %rax             # Retorna ponteiro para dados
    addq $32, %rsp
    popq %rbp
    ret

erro_alocacao:
    movq $0, %rax              # Retorna NULL em caso de erro
    addq $32, %rsp
    popq %rbp
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

	movq inicioHeap, %rbx
	#Inicimapa_loop:
    #Verifica se chegou ao final da heap
    cmpq topoHeap, %rbx         #compara prt_bloco com topoHeap
    jge fim_mapa                        #se for maior ou igual que topoHeap, termina

mapa_loop:
	#Verifica se chegou ao final da heap
	cmpq topoHeap, %rbx			#compara prt_bloco com topoHeap
	jge fim_mapa						#se for maior ou igual que topoHeap, termina

	#Imprime dados gerenciais '#'
	movq $32, %r12						#inicializa contador com i = 32
cabecalho_loop:
	#Configura syscall write (1, '#', 1)
	movq $1, %rax						#número da syscall write
	movq $1, %rdi						#stdout = 1
	leaq hash_symbol, %rsi		#endereço do caractere '#'
	movq $1, %rdx						#número de bytes para escrever

	pushq %r12							#preserva o contador, porque a syscall pode alterar o valor
	syscall								#executa a escrita
	popq %r12							#restaura o contador

	decq %r12							#decrementa o contador i--
	jnz cabecalho_loop  
saiu_laco_cabecalho:

	cmpq topoHeap, %rbx
    jge fim_mapa

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

	testq %rcx, %rcx
	jz proximo_bloco

dados_loop:
	movb %r12b, char_buffer

	pushq %rcx
    movq $1, %rax            # syscall write
    movq $1, %rdi            # stdout
    leaq char_buffer, %rsi   # endereço do caractere
    movq $1, %rdx            # tamanho 1 byte
    syscall
	popq %rcx

	decq %rcx
	jnz dados_loop    

proximo_bloco:
	#Avança para o próximo bloco na heap
	movq 8(%rbx), %rax					#carrega o tamanho do bloco
	addq $32, %rax						#soma ao tamanho do cabeçalho
	addq %rax, %rbx						#avança prt_bloco para o próximo bloco

	jmp mapa_loop						#volta para o início do bloco

fim_mapa:
	#Finalização: imprime nova linha e restaura os registradores
	pushq $'\n' # imprime uma nova linha
	movq $1, %rax
	movq $1, %rdi
	movq %rsp, %rsi
	movq $1, %rdx
	syscall
	addq $8, %rsp

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
    #pushq $5
	movq $5, %rdi
    call alocaMem
    addq $8, %rsp
    movq %rax, -8(%rbp)

    # imprimeMapa() - #################**********
    call imprimeMapa
    
	# b = alocaMem(4)
    #movq $4, %rdi
	pushq $4
    call alocaMem
	addq $8, %rsp
    movq %rax, -16(%rbp)        # Armazena 'b' na stack

    #imprimeMapa() - ################**********##############****
    call imprimeMapa

    # liberaMem(a)
    movq -8(%rbp), %rdi
	#pushq -8(%rbp)
    call liberaMem
    movq $'-', %r12 

    # imprimeMapa() - ################----------##############****
    call imprimeMapa

    # liberaMem(b)
    movq -16(%rbp), %rdi
	#pushq -16(%rbp)
    call liberaMem

    #imprimeMapa() - resultado final
    call imprimeMapa

    # finalizaAlocador()
    call finalizaAlocador

    # return 0
    xorq %rax, %rax
    addq $16, %rsp
    popq %rbp
    ret
#----------------------------------------------------------------------------------------------------------------------

