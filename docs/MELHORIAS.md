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

Sugestões pensadas para o conteúdo clássico. O que o Leatrix Plus e o Leatrix Maps já fazem ficou de fora nesse primeiro momento (venda e reparo automáticos, automação de missões, mapas e coordenadas). Parte disso entrou depois: veja a seção 8.

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

### Chat, feito em 05/11/2026

- [x] **Leitura e links**: dica ao passar o mouse em links; ícone, nível e melhoria ao lado dos links de itens (o link fica intacto); canais abreviados (`[2. Comércio - Cidade]` vira `[C]`) ([Chat.lua](../Chat.lua), [ChatFrames.lua](../ChatFrames.lua)).
- [x] **Avisos**: seu nome e palavras escolhidas aparecem em laranja, com som (no máximo um a cada 2 s).
- [x] **Comodidades**: as últimas 80 linhas de cada janela e o que foi digitado voltam depois de `/reload` e login; setas ↑ ↓ sem Alt; Alt+clique no nome convida.
- [x] **Visual**: botões laterais escondidos, abas só com o mouse em cima. O chat e a caixa de digitar ficam com o visual do jogo (um fundo e borda próprios foram testados e descartados).
- [x] **Barra de canais**: letras coloridas na linha das abas (Dizer, Gritar, Grupo, Instância, Raide, Guilda e cada canal) que abrem a caixa de texto no canal ([ChatBar.lua](../ChatBar.lua)).
- [x] **Chat inteiro no visual da barra de canais** ([ChatSkin.lua](../ChatSkin.lua)), feito em 08/11/2026, a pedido do usuário (que antes tinha preferido o visual do jogo): abas numa faixa só com linhas finas entre elas, a selecionada com texto dourado; janela e caixa de digitar na caixa escura com borda dourada; a borda da caixa de digitar fica da cor do canal. As texturas do jogo só ficam vazias (posições e tamanhos continuam valendo); o brilho de mensagem nova das abas fica.
- [x] **Barra de canais numa faixa só**, feito em 08/11/2026: fundo escuro com a borda dourada fina das janelas do jogo, os canais separados por linhas finas, todos com a mesma largura e brilho suave sob o mouse. (Copiar a arte das abas não deu certo: o Forever não guarda as peças onde o addon procurava, e as caixas separadas ficaram feias.)
- [x] **Abas de um canal** ([ChatTabs.lua](../ChatTabs.lua)), feito em 08/11/2026: o botão "+" no canto de cada janela de chat (menu com os canais) ou clique direito numa letra da barra de canais abre uma aba do próprio jogo, com o nome inteiro (Grupo, Guilda, Sussurros, Comércio...), que recebe só aquele canal e já abre com as últimas linhas dele. O jogo guarda a aba como as outras. Uma primeira versão filtrava a janela por cima do texto; o usuário preferiu abas.
- [x] **Glossário de termos** ([ChatTerms.lua](../ChatTerms.lua)), feito em 08/11/2026: siglas do WoW (LFM, LoS, WTS, BoE, MS/OS, SR, RFC, BRD, UBRS...) viram links com o significado ao passar o mouse ou clicar. Nomes de masmorras, raides e campos de batalha vêm do próprio jogo. Siglas que são palavras comuns em português (OS, MS, SR, AH, TB, BB...) só valem em maiúsculas.
- [ ] **Anti-spam** e **saque compacto**: ideias que ficaram para depois.

### Brilhos e interação, feito em 06/11/2026

- [x] **Substitui o ForeverLootSparkles** (e o Lueur), escrito do zero ([Sparkles.lua](../Sparkles.lua)). Fica desligado enquanto um deles estiver ativo; `/fh disableold` desativa.
- [x] **Brilho nos itens de missão**: mantém ligado o brilho do próprio jogo, que os presets gráficos desligam.
- [x] **Ícone da ação** acima do objeto utilizável mais próximo (alvo suave do jogo).
- [x] **Brilhos dourados** em minério, ervas e corpos com saque: fracos fora de alcance, fortes ao alcance, cinza sem perícia.

### Farol de missão, feito em 08/11/2026

- [x] **Farol nas criaturas de missão** ([QuestGlow.lua](../QuestGlow.lua)): em todas as placas de nome da tela, a criatura com objetivo ainda não concluído ganha aura pulsante no corpo, estrela girando, marca de missão com o progresso (3/8) e feixe de luz. Lido da dica da unidade (só os objetivos do próprio personagem, mesmo em grupo); se a dica não disser nada, compara o nome com os objetivos de matar do registro. Mais fraco quando outro jogador marcou a criatura.
- [x] **Farol no objeto de missão mais próximo**, no lugar dos brilhos dourados (o jogo só dá placa de nome ao objeto do alvo suave, então é um por vez; o brilho do próprio jogo continua marcando todos).
- [x] **Desempenho**: só eventos (placas de nome e registro de missões, com as atualizações agrupadas), cache por criatura, faróis reaproveitados e animações feitas pelo motor do jogo (nenhum código roda por quadro; param sozinhas fora da tela).
- [x] Testado no jogo: a dica das criaturas do Forever traz as linhas de missão (`/fh glow` com o alvo mostra as linhas). A luz ficou forte demais e ganhou a opção de intensidade (padrão 50%), que não apaga a marca nem o progresso.

### Brilho dos objetos no formato do Lueur, feito em 11/11/2026

- [x] **Módulo novo** ([Glow/](../Glow/)), escrito do zero, no lugar dos brilhos dourados e do farol no objeto de missão. O Lueur serviu só de referência do comportamento do jogo (alvo suave e placa de nome); nenhum código nem imagem dele foi copiado. As texturas foram geradas por um script próprio.
- [x] **Categorias** com caixa e cor próprias: minério, ervas, missões (com o progresso), baús (pelo nome ou por já ter saqueado), boia de pesca (alcance de 60 m enquanto a linha está na água), saque (corpos) e outros objetos.
- [x] **15 efeitos** e aparência por categoria ou para todos: tamanho, intensidade, altura, sumir com a placa, passar atrás do personagem, nome, ícone, tamanho do texto e fonte.
- [x] **Janela** com faixa de categorias, prévia 3D, grade de efeitos e página de ajustes (alcance, direção, modo exclusivo, tecla de interagir, ignorar objeto, esconder em combate/instância/sem profissão, área da silhueta). Também abre pelas opções e por `/fh glow`.
- [x] **Desempenho**: as animações são grupos do motor do jogo; o Lua só roda nas transições (0,3 s) e quando uma partícula recomeça. A checagem do alvo é a cada 0,1 s com alvo e 0,5 s sem; a classificação fica em cache por objeto; a pesca é detectada por evento.
- [x] **Ajustes do jogo** guardados e devolvidos ao desligar e ao sair (os valores salvos pelo módulo antigo foram migrados).
- [x] **Revisão de desempenho** (11/11/2026): checagem rápida (0,1 s) só com objeto aceso ou à espera da placa, senão 0,5 s; placas novas só reavaliam quando a placa é esperada; nome, GUID e "ignorado" guardados com a classificação (sem `gsub` nem closure por checagem); varredura das placas só até a busca direta funcionar; instância lida por evento; dica do cursor ignorada sobre unidades e sem missões no registro; máscara da silhueta só movida quando muda e campo de visão em cache; uma pintura ao acender e, nas transições, só as camadas que mudam de forma são redimensionadas; flash e anel de travar escondidos fora da animação; farol das criaturas só relê as dicas quando o progresso do registro muda.
- [ ] Testar no jogo: efeitos (principalmente os caminhos de Órbita/Espírito e o Gêiser), a máscara da silhueta e a prévia 3D (o corpo do personagem para "Saque").

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

## 8. Trazido de outros addons (05/11/2026)

Reescrito no padrão do ForeverHub, sem copiar nem alterar os addons originais.

- [x] **DisenchantBuddy** ([Disenchant.lua](../Disenchant.lua)): resultados de desencantar na dica de armaduras e armas verdes, azuis e roxas (chance e quantidade), e nos materiais de Encantamento os níveis de item que os dão. Só o conteúdo clássico (níveis até 92). Pode exigir Shift, Ctrl ou Alt. Fica desligado enquanto o DisenchantBuddy estiver carregado.
- [x] **Leatrix Plus, mercador** ([Bags/Merchant.lua](../Bags/Merchant.lua)): venda de lixo e reparo automáticos, com fundos da guilda primeiro. Ordem: vender, reparar, reabastecer. Shift ao abrir o mercador pula tudo.
- [x] **Leatrix Plus, automação** ([Automation.lua](../Automation.lua)): saque mais rápido, aceitar ressurreição (exceto de quem está em combate e em Zul'Gurub) e esconder os erros vermelhos, mantendo os importantes.
- [x] **Aviso de limite no saque**: o jogo não divide uma pilha do saque. Com 29/30 de um item "Único (30)" e uma pilha de 2 no corpo, nada é pego. O ForeverHub explica no chat por que o item ficou, e o saque rápido pula esse espaço. Destruir um da bolsa não resolve: em item de missão, pode descartar a pilha toda. Limitação do servidor; ticket aberto com a Blizzard.
- Cada opção do Leatrix que estiver ligada nele tem prioridade; o ForeverHub não faz o mesmo trabalho duas vezes. `/fh disableold` agora também desliga o DisenchantBuddy e o Leatrix Plus.
- Fora, por pedido: aceitar e entregar missões automaticamente.
- [x] **Marcar na bolsa os itens que valem desencantar**: ícone de desencantar no canto superior esquerdo de equipamentos que podem ser desencantados, que o personagem tem perícia para desencantar e que não são melhoria sobre o equipado. Opção para mostrar também em personagens sem Encantamento. A dica mostra a perícia exigida (verde, vermelho ou cinza). Perícia exigida por nível de item: valores clássicos, aproximados para épicos.

## 9. Linha de desempenho (05/11/2026)

- [x] **Desempenho sempre visível** ([Performance.lua](../Performance.lua)): FPS e latência coloridos (verde, amarelo, vermelho), com memória da interface e relógio como opções. A latência mostrada é a pior entre casa e mundo. Atualiza uma vez por segundo, só com chamadas baratas, e para quando a linha está escondida.
- A dica mostra média de FPS do último minuto, mínimo, tempo por quadro, latência de casa e de mundo, banda e os addons que mais usam memória. A memória por addon é cara de ler: só com a dica aberta, no máximo a cada 10 s e nunca em combate. O mínimo ignora telas de carregamento.
- Arrastar move, clique direito zera média e mínimo, Shift+clique libera memória sem uso (fora de combate). `/fh perf` mostra ou esconde.

## 10. Barras de ações (05/11/2026)

- [x] **Custo de mana nos botões** ([ActionBars.lua](../ActionBars.lua)): número azul no canto superior esquerdo de cada botão das barras da Blizzard, também em macros (segue a magia que a macro lançaria, com modificador e alvo). Só adiciona texto aos botões, sem ganchos nem atributos, então não contamina as barras seguras. Os eventos são agrupados em uma passada no quadro seguinte.

## 11. Profissões, com foco em Couraria (05/11/2026)

Arquivos em [Professions/](../Professions/). Valem para qualquer profissão; os itens de vendedor conhecidos de antemão são os de Couraria (linhas, sal, tinturas) e alguns comuns. As receitas são lidas ao abrir a janela da profissão (só a própria, não a de link ou da guilda) e ficam salvas para todos os personagens.

- [x] **Guia para subir nível** ([Guide.lua](../Professions/Guide.lua)): painel ao lado da janela da profissão com as receitas que ainda dão pontos (laranja, amarela, verde). Primeiro as que dá para fazer com bolsas + banco, depois pelo custo estimado por ponto (preço no vendedor ou preço de venda dos materiais). Mostra quanto dá para fazer ou o que falta, e avisa quando a perícia chegou ao máximo do nível. Clique abre a receita; Shift põe 1 na lista, Ctrl põe 5. Pode ser recolhido.
- [x] **Lista de compras** ([Shopping.lua](../Professions/Shopping.lua)): botão "Adicionar à lista" ao lado de "Criar tudo", com a quantidade do campo de criar. Janela sempre visível (arrastável) com as receitas e os materiais, o que tem (bolsas + banco) de quanto precisa, e marca "(vendedor)", "(você fabrica)" ou "(banco)". Cada criação tira uma da lista. No mercador que vende algo que falta, um botão acima da janela compra tudo (com o custo na dica). `/fh lista` mostra ou esconde, `/fh lista limpar` esvazia.
- [x] **Dica dos materiais** ([Tooltip.lua](../Professions/Tooltip.lua)): em quais receitas conhecidas (de todos os personagens do reino) o item é usado e quantos cada uma pede, na cor de dificuldade vista por último, e quanto a lista de compras precisa.
- [x] **Esfolar na dica**: em feras e em criaturas mortas que o jogo marca como esfoláveis, a perícia de Esfolamento necessária (regra clássica: até nível 10, 1; de 11 a 20, (nível - 10) x 10; depois, nível x 5), na cor de chance de ponto.
- O código de compra do reabastecimento virou `Merchant:PlanPurchase` e `Merchant:Buy`, usados pelos dois.

## Ordem sugerida

1. Grupo 1 inteiro: é pequeno e evita um ciclo de teste perdido.
2. Do grupo 2: nível do item, itens novos e busca por espaço, que são os que mais se sentem no dia a dia.

### Qualidade de vida, feito em 06/11/2026

- [x] **Nível das missões** antes do nome, na cor da dificuldade, no rastreador e no registro ([Quests.lua](../Quests.lua)).
- [x] **XP das missões prontas** na linha de experiência ("Prontas +38%") e na dica, com quanto falta depois de entregar.
- [x] **Melhor recompensa**: moeda na mais valiosa e "+12%" na melhor melhoria, e uma linha no chat (o DialogueUI mostra a própria janela).
- [x] **Correio**: "Pegar tudo" (só se o jogo não tiver o próprio), seus personagens e destinatários recentes ao lado do destinatário, e o último já preenchido ([Mail.lua](../Mail.lua)).
- [x] **Abrir caixas** com um clique por item e **munição/fragmentos** no rodapé das bolsas, com aviso ([BagExtras.lua](../BagExtras.lua)).
- [x] **Nível do item** (cor da qualidade), no alto dos espaços do personagem e de inspecionar ([ItemSlots.lua](../ItemSlots.lua)).
- [x] **Lembretes** de buff da classe faltando ou acabando e do ajudante (chamar, reviver, alimentar, invocar o último demônio), clicáveis, só fora de combate ([Reminders.lua](../Reminders.lua)).
- [ ] **Nível de pesca das zonas**: falta uma fonte confiável dos valores.
