# Melhorias planejadas – !ForeverHub

Levantamento feito em 31/10/2026, antes do primeiro teste no jogo.
Regra do projeto: alterar apenas os arquivos do `!ForeverHub`, nunca os addons originais.

## 1. Antes ou logo no primeiro teste (prioridade)

Ninguém rodou o addon no jogo ainda; estes itens ajudam a encontrar e corrigir problemas mais rápido.

- [ ] **Comando de diagnóstico `/fh debug`.** Mostra o que o addon detectou no cliente: banco com abas ou bolsas clássicas, quantas bolsas existem, se `HasKey` e `TooltipDataProcessor` existem, quais módulos estão ativos e quais conflitos foram encontrados. Junto com um erro, essa saída permite corrigir sem adivinhar.
- [ ] **Chaveiro provavelmente nunca aparece.** Em [Bags/Data.lua:35](../Bags/Data.lua#L35), `HasKey()` é chamado quando o arquivo carrega, antes do login, quando o jogo costuma responder "não". A checagem precisa ir para o login.
- [ ] **Plural nas mensagens.** Hoje aparece "1 erros nesta sessão". Separar singular e plural nas traduções.
- [ ] **Proteção no `Defer`.** Em [Core.lua:247](../Core.lua#L247), se uma das funções agendadas der erro, as outras agendadas no mesmo quadro não rodam. Envolver cada chamada em proteção evita que um erro numa parte trave a atualização das bolsas.

## 2. Qualidade de vida nas bolsas

- [ ] **Nível do item** escrito no canto dos equipamentos (opcional).
- [ ] **Brilho em itens novos**, que some ao passar o mouse.
- [ ] **Busca melhor:** por espaço de equipamento ("pés", "dedo"), por "vinculado" e, opcionalmente, pelo texto da dica (mais pesado).
- [ ] **Bolsas de profissão** com espaços coloridos (erva, encantamento, munição, aljava).
- [ ] **Contar itens do correio** na dica do item, lendo a caixa de correio quando ela é aberta.
- [ ] **Ver equipamento de outros personagens.** Os dados já são salvos (`player.equip`); falta uma janela para mostrar.
- [ ] **Teclas de atalho** (`Bindings.xml`) para abrir o banco offline e a janela de erros.

## 3. Mover janelas

- [ ] **Modo "destravar"** (`/fh move`) que destaca as janelas que podem ser movidas.
- [ ] **Mover janelas fora da lista**, por exemplo segurando `Alt` sobre qualquer janela. Precisa de cuidado com janelas protegidas.
- [ ] **Ícone de cadeado** nas janelas movidas, para restaurar sem `Shift`+clique direito.

## 4. Capturador de erros

- [ ] **Filtrar por addon.**
- [ ] **Copiar todos** os erros de uma vez, para mandar um relatório completo.
- [ ] **Contador no ícone do minimapa** (botão de addons), vermelho quando há erros novos.
- [ ] **Ignorar um erro** específico já conhecido.

## 5. Maiores (mais trabalho)

- [ ] **Banco da guilda** no mesmo estilo das bolsas (hoje continua a janela da Blizzard).
- [ ] **Perfis por personagem** (hoje as configurações valem para a conta toda).
- [ ] **Medidor de desempenho** `/fh perf`: tempo e memória usados por módulo.
- [ ] **Mais idiomas** além de inglês e português.

## Ordem sugerida

1. Grupo 1 inteiro: é pequeno e evita um ciclo de teste perdido.
2. Do grupo 2: nível do item, itens novos e busca por espaço, que são os que mais se sentem no dia a dia.
