#Script para compilar e rodar o código Alocador.s
#Aluna: Giovanna Fioravante Dalledone

#Compilação (Montagem) e Linkagem
#as Alocador.s -o Alocador.o -no-pie

gcc Alocador.s -o Alocador.o Alocador -no-pie

#Execução
./Alocador
