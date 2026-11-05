# Melhorias planejadas – !ForeverHub

Levantamento feito em 31/10/2026, antes do primeiro teste no jogo.
Regra do projeto: alterar apenas os arquivos do `!ForeverHub`, nunca os addons originais.

## 1. Antes ou logo no primeiro teste (prioridade)

Ninguém rodou o addon no jogo ainda; estes itens ajudam a encontrar e corrigir problemas mais rápido.

- [ ] **Comando de diagnóstico `/fh debug`.** Mostra o que o addon detectou no cliente: banco com abas ou bolsas clássicas, quantas bolsas existem, se `HasKey` e `TooltipDataProcessor` existem, quais módulos estão ativos e quais conflitos foram encontrados. Junto com um erro, essa saída permite corrigir sem adivinhar.
- [x] **Chaveiro provavelmente nunca aparece.** Corrigido em 05/11/2026: a checagem foi para o login. Em [Bags/Data.lua:35](../Bags/Data.lua#L35), `HasKey()` é chamado quando o arquivo carrega, antes do login, quando o jogo costuma responder "não". A checagem precisa ir para o login.
- [ ] **Plural nas mensagens.** Hoje aparece "1 erros nesta sessão". Separar singular e plural nas traduções.
- [ ] **Proteção no `Defer`.** Em [Core.lua:247](../Core.lua#L247), se uma das funções agendadas der erro, as outras agendadas no mesmo quadro não rodam. Envolver cada chamada em proteção evita que um erro numa parte trave a atualização das bolsas.

## 2. Qualidade de vida nas bolsas

- [x] **Nível do item** escrito no canto dos equipamentos (opcional). Feito em 05/11/2026.
- [x] **Brilho em itens novos**, que some ao passar o mouse. Feito em 05/11/2026.
- [ ] **Busca melhor:** por espaço de equipamento ("pés", "dedo"), por "vinculado" e, opcionalmente, pelo texto da dica (mais pesado).
- [x] **Bolsas de profissão** com espaços coloridos (erva, encantamento, munição, aljava). Feito em 04/11/2026, com grupos separados por tipo e o comando `/fh bagtypes`.
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
- [x] **Contador no ícone do minimapa**, vermelho quando há erros na sessão. Feito em 04/11/2026 no botão próprio do minimapa.
- [ ] **Ignorar um erro** específico já conhecido.

## 5. Maiores (mais trabalho)

- [ ] **Banco da guilda** no mesmo estilo das bolsas (hoje continua a janela da Blizzard).
- [ ] **Perfis por personagem** (hoje as configurações valem para a conta toda).
- [ ] **Medidor de desempenho** `/fh perf`: tempo e memória usados por módulo.
- [ ] **Mais idiomas** além de inglês e português.

## 6. Qualidade de vida (levantamento de 05/11/2026)

Sugestões pensadas para o conteúdo clássico. O que o Leatrix Plus e o Leatrix Maps já fazem ficou de fora (venda e reparo automáticos, automação de missões, mapas e coordenadas).

### Feito em 05/11/2026

- [x] **Ajustes novos em "Gráficos, câmera e interface"**: números de recarga nos botões (`countdownForCooldowns`), distância das placas de nome (`nameplateMaxDistance`), som em segundo plano (`Sound_EnableSoundWhenGameIsInBG`), saque automático (`autoLootDefault`) e ação ao apertar a tecla (`ActionButtonUseKeyDown`).
- [x] **Botão "Vender lixo"** no rodapé das bolsas, visível no mercador, com o valor total do lixo. Vende em lotes pequenos e só enquanto o mercador está aberto ([Bags/Merchant.lua](../Bags/Merchant.lua)).
- [x] **Marcar item como lixo** com `Alt`+clique nas bolsas. Em item cinza, faz o contrário: guarda o item para nunca ser vendido.
- [x] **Durabilidade**: porcentagem nos espaços da janela do personagem e aviso quando algum item chega ao limite, 20% por padrão ([Durability.lua](../Durability.lua)).
- [x] **Linha de experiência**: nível, %, XP por hora, tempo até o nível e descanso. Pode ser arrastada; clique direito recomeça a contagem ([Experience.lua](../Experience.lua)).
- [x] **Reabastecer reagentes e munição** por personagem: `/fh restock [item] [quantidade]` define o que manter nas bolsas, e a compra acontece ao abrir o mercador.

### Pendentes

- [ ] **Contador de munição e fragmentos de alma** no rodapé das bolsas.
- [ ] **Travar espaços na organização**: itens marcados não se mexem com a vassoura.
- [ ] **Nível de item e qualidade** nos espaços da janela do personagem e de inspecionar.
- [ ] **Janela para editar o reabastecimento** (hoje é só por comando).

### Feito em 05/11/2026 (segunda parte)

- [x] **Ouro da sessão e do dia**: ganho, gasto, saldo e saldo por hora, na dica do ouro das bolsas e em `/fh gold` ([Gold.lua](../Gold.lua)).
- [x] **Dicas**: ID do item e do feitiço (desligado por padrão), preço de venda da pilha inteira com o valor de cada unidade, alvo da unidade sob o mouse ([Tooltips.lua](../Tooltips.lua), [Bags/Tooltip.lua](../Bags/Tooltip.lua)).
- [x] **Copiar o chat**: botão no canto de cada janela de chat e `/fh copychat` ([Chat.lua](../Chat.lua)).
- [x] **Links da web no chat**: endereços viram links; clicar abre o endereço pronto para copiar.

## 7. Bolsa: ideias de 05/11/2026

### Feito

- [x] **Itens inutilizáveis em vermelho**: o addon lê as linhas vermelhas da dica do item (classe, nível, tipo de armadura ou arma, profissão), com cache por item, refeito ao subir de nível ou aprender perícias.
- [x] **"BoE"** no canto dos equipamentos vinculados quando equipados (só nas próprias bolsas, porque offline não se sabe se o item já foi vinculado).
- [x] **Contador de espaços separado**: normais e, em verde, os livres das bolsas de profissão. Fica vermelho quando restam poucos espaços (padrão: 4) e mostra "Bolsas cheias!" quando acaba.
- [x] Chaveiro, nível do item e brilho em itens novos (ver seções 1 e 2).
- [x] **% de melhoria sobre o equipado** nos equipamentos das bolsas e na dica do item ([Upgrade.lua](../Upgrade.lua)). Compara por atributos com pesos da classe (estimativa, padrão) ou por nível do item. Anéis, berloques e armas de duas mãos são comparados com a peça mais fraca ou com as duas mãos.

### Pendentes

- [ ] **Juntar os espaços vazios** num único espaço com o número de livres.
- [ ] **Separar por categoria de item** (Consumíveis, Materiais, Equipamento, Missão, Lixo).
- [ ] **Travar espaços na organização** (a organização da Blizzard só permite ignorar bolsas inteiras, não itens).
- [ ] **Buscar por espaço de equipamento, "vinculado" e "inutilizável"**, e **buscas salvas**.
- [ ] **Espaços livres no ícone de cada bolsa**, na barra de bolsas.

## Ordem sugerida

1. Grupo 1 inteiro: é pequeno e evita um ciclo de teste perdido.
2. Do grupo 2: nível do item, itens novos e busca por espaço, que são os que mais se sentem no dia a dia.
