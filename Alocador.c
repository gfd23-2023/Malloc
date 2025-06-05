/*ESTRUTURA DO BLOCO:
 * 8 Bytes para marcar se está livre ou ocupado
 * 8 Bytes para dizer o tamanho do bloco
 *
 *Tópicos do trabalho:
 * 6.1
 * 6.2 a)
 * 6.2 d)
 * 6.4
*/

/*DÚVIDAS:
 * 1. Como funciona a fusão dos nós livres sendo que precisamos implementar uma lista
 com os nós livres e outra com os nós ocupados?
 * 2. A fusão dos nós livres deve ser implementada dentro da função de liberar memória? Se for o caso,
 como podemos fazer para chamar a função liberaMem() sem liberar um bloco, apenas para fundir os livres?
 Ou precisamos criar uma função nova?
 * 3. Precisamos tratar os casos de erro em assembly? Por exemplo, não conseguiu alocar ou não encontrou o bloco 
 para liberar.*/


#include <stdio.h>
#include <stdint.h>	//para int64
#include <unistd.h>
#include <sys/syscall.h>

#define _GNU_SOURCE

/*Macros para navegação*/

/*------------------ BLOCO ------------------*/
#define STATUS(ptr)			(*(int64_t*)(ptr))					//ponteiro para o stauts do bloco
#define TAMANHO(ptr)		(*(int64_t*)((char*)(ptr) + 8))		//8 bytes depois do ponteiro do status do bloco
#define PROX_LIVRE(ptr)		(*(void**)((char*)(ptr) + 16))		//ponteiro para um endereço de memória
#define PROX_OCUPADO(ptr)	(*(void**)((char*)(ptr) + 24))		//ponteiro para um endereço de memória
#define DADOS(ptr)			((void*)((char*)(ptr) + 32))		//ponteiro para o início da área de dados
/*-------------------------------------------*/

/*Variáveis globais*/
void* topoInicialHeap = NULL;
void* inicioHeap = NULL;
void* topoHeap = NULL;
void* listaLivres = NULL;		//lista dos nós livres
void* listaOcupados = NULL;		//lista dos nós ocupados

//Executa Syscall brk para obter o endereço do topo da heap e o armazena em uma variável global
//variável global: topoInicialHeap
//Executada no iício do código
void iniciaAlocador()
{
	topoInicialHeap = sbrk(0);
	topoHeap = topoInicialHeap;
	inicioHeap = topoInicialHeap;

	//tratar caso de erro

	//Para debugar
	printf("Endereço incial da heap: %p\n", topoInicialHeap);
}

//Executa a syscall brk para restaurar o valor original da heap (contido em topoInicialHeap)
void finalizaAlocador()
{
	topoHeap = (void*) syscall(SYS_brk, topoInicialHeap);

	//tratar caso de erro

	//Para debugar
	printf("Endereço do topo da heap: %p\n", topoHeap);
}

//Recebe o endereço do primeiro bloco da lista de blocos livres que podemos fundir
//Retorna o endereço do blocão fundido - ou não precisa?
//Testa até fundir todos os nós livres adjacentes que encontrar
void juntaBloco()
{
	void* bloco = listaLivres;
	void* proximo = NULL;

	while (bloco)
	{
		proximo = PROX_LIVRE(bloco);

		//Se o próximo não for nulo e os blocos estão fisicamente lado a lado na memória
		if (proximo && (char*)bloco + TAMANHO(bloco) + 32 == (char*)proximo)
		{
			TAMANHO(bloco) = TAMANHO(bloco) + TAMANHO(proximo) + 32;	//Junta os blocos e o cabeçalhod do segundo
			PROX_LIVRE(bloco) = PROX_LIVRE(proximo);					//Ajusta os ponteiros
		}
		else
			bloco = PROX_LIVRE(bloco);			//Somente se não houve fusão
	}

	return;
}

//Marca o bloco como livre
//Recebe o endereço dos DADOS do bloco
void liberaMem(void* bloco)
{
	void* bloco_aux = listaOcupados;
	void* bloco_anterior = NULL;
	void* bloco_selecionado = (void*)((char*)bloco - 32);	//subtrai 32 bytes do ponteiro para chegar no início do bloco

	//Se for o primeiro bloco da lista
	if (bloco_aux == bloco_selecionado)
	{
		//libera o bloco
		STATUS(bloco_selecionado) = 0;

		//Remove da lista de ocupados
		listaOcupados = PROX_OCUPADO(bloco_aux);		//é o primeiro

		//Adiciona na lista de livres
		PROX_LIVRE(bloco_aux) = listaLivres;
		listaLivres = bloco_aux;

		return;
	}

	//Procura o bloco na lista
	while (bloco_aux != bloco_selecionado)
	{
		bloco_anterior = bloco_aux;
		bloco_aux = PROX_OCUPADO(bloco_aux);
	}

	//Libera o bloco
	STATUS(bloco_aux) = 0;

	//Remove da lista de ocupados
	PROX_OCUPADO(bloco_anterior) = PROX_OCUPADO(bloco_aux);

	//Adiciona na lista de livres
	PROX_LIVRE(bloco_aux) = listaLivres;
	listaLivres = bloco_aux;

	//Junta os blocos livres
	juntaBloco();

	return;
}

//1. Procura um bloco livre com tamanho maior ou igual a num_bytes
//2. Caso encontre, marca ele como ocupado e retorna o endereço incial do bloco
//3. Se não encontrar, abre espaço para um novo bloco (mexendo no topo da pilha), marca-o como ocupado e retorna o endereço
//incial do bloco
//Percorre o início da lista
void* alocaMem(int num_bytes)
{
	void* ptr_livre = listaLivres;
	void* bloco_anterior = NULL;
	void* bloco = NULL;

	while (ptr_livre)
	{
		if (STATUS(ptr_livre) == 0 && TAMANHO(ptr_livre) >= num_bytes)
		{
			bloco = ptr_livre;
			break;				//Achou o bloco, então sai do laço
		}
		
		bloco_anterior = ptr_livre;
        ptr_livre = PROX_LIVRE(ptr_livre);
	}

	//Altera as listas
	if (bloco)
	{
		STATUS(bloco) = 1;									//ocupado
		
		//Remove o bloco da lista de livres
		if (!bloco_anterior)								//é o primeiro
			listaLivres = PROX_LIVRE(bloco);
		else												//é o último ou está no meio
			PROX_LIVRE(bloco_anterior) = PROX_LIVRE(bloco);

		//Adiciona o bloco na lista de ocupados
		if (!listaOcupados)									//se a lista estiver vazia
			listaOcupados = bloco;
		else												//já tem blocos na lista
		{
			PROX_OCUPADO(bloco) = listaOcupados;
			listaOcupados = bloco;
		}

		return DADOS(bloco);
	}

	//Caso não tenha encontrado o bloco
	bloco = topoHeap;

	int64_t tamanho_final = num_bytes + 32;					//num_bytes + cabeçalho
	
	topoHeap = (void*)((char*)topoHeap + tamanho_final);	//atualiza o topo da heap
	syscall(SYS_brk, topoHeap);								//aloca espaço para o bloco

	STATUS(bloco) = 1;
	TAMANHO(bloco) = num_bytes;
	PROX_LIVRE(bloco) = NULL;
	PROX_OCUPADO(bloco) = NULL;

	//Adiciona na lista de ocupados
	if (!listaOcupados)                                 //se a lista estiver vazia
        listaOcupados = bloco;
    else                                                //já tem blocos na lista
    {
		PROX_OCUPADO(bloco) = listaOcupados;
        listaOcupados = bloco;
    }

    return DADOS(bloco);

}

//Imprime um mapa da memória da região da heap.
//Cada byte da parte gerencial do bloco deve ser impresso com o caractere '#'
//Se o bloco estiver livre, imprime o caractere '-', se estiver ocupado imprime '+'
void imprimeMapa()
{
	void* ptr_bloco = inicioHeap;

	while (ptr_bloco < topoHeap)
	{
		//Imprime cabeçalho
		for (int i = 0; i < 32; i++)
			printf("#");

		//Imprime - se estiver livre e + se estiver ocupado
		char simbolo = (STATUS(ptr_bloco) == 0) ? '-' : '+';
		for (int i = 0; i < TAMANHO(ptr_bloco); i++)
			printf("%c", simbolo);

		//Avança para o próximo bloco de memória física
		ptr_bloco = (void*)(char*)(ptr_bloco + 32 + TAMANHO(ptr_bloco));
	}

	printf("\n");
}

int main()
{
	printf("Testando o Alocador de Memória!\n");

	iniciaAlocador();

	void* bloco1 = alocaMem(10);
	void* bloco2 = alocaMem(41);
	void* bloco3 = alocaMem(130);

	imprimeMapa();

	liberaMem(bloco2);
	liberaMem(bloco1);

	imprimeMapa();

	liberaMem(bloco3);

	imprimeMapa();

	finalizaAlocador();
}
