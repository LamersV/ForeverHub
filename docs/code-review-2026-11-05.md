# Revisão de Código (performance): ForeverHub, ForeverMap e ForeverGroups

**Data:** 2026-11-05

**Escopo revisado:**
- Os três addons próprios em `Interface\AddOns`: `!ForeverHub` (cerca de 9,4 mil linhas), `ForeverMap` (cerca de 3,2 mil, sem contar os dados) e `ForeverGroups` (cerca de 3,6 mil).
- O foco foi só **performance**:
  - código que roda a cada quadro (OnUpdate, tickers);
  - eventos frequentes (bolsas, cooldowns, chat, registro de missões, barras de ação, busca de grupos);
  - lixo para o coletor (tabelas e strings criadas em caminhos quentes);
  - ganchos, custo no login e memória.
- **Ficou de fora:** correção de lógica, segurança e estilo. Os dados gerados (`ForeverMap\Data`) e os addons de terceiros também não foram revisados.
- **Nada foi medido no jogo.** As estimativas de custo vêm da leitura do código e precisam ser confirmadas com a linha de desempenho (`/fh perf`, dica com memória por addon).

**Stack:** Lua 5.1 (WoW, cliente Forever 1.60.1 com o motor de interface do retail), XML mínimo.

## Resumo executivo

O estado geral é bom. Os três addons já seguem os padrões que mais importam em WoW:
- um único frame de eventos por addon;
- eventos em rajada agrupados numa passada só no quadro seguinte (`ns:Defer`);
- nada é redesenhado com a janela fechada (as bolsas só marcam `dirty`; o ForeverGroups marca a lista como "velha");
- caches por link nos cálculos caros (melhoria de equipamento, item inutilizável);
- OnUpdate com limite de frequência e saída antecipada.

Não há nenhum caso de trabalho pesado a cada quadro sem limite.

Os riscos reais estão em **eventos frequentes que disparam reconstruções completas**. Os dois maiores:
1. **Registro de missões (ForeverMap):** cada `QUEST_LOG_UPDATE` refaz a avaliação de disponibilidade de todas as missões da zona e reconstrói os ícones do minimapa.
2. **Informação de item (ForeverHub):** cada `GET_ITEM_INFO_RECEIVED` redesenha a bolsa inteira enquanto ela estiver aberta. Esse evento dispara para itens pedidos por **qualquer** addon, não só pelas bolsas.

Nenhum dos dois trava o jogo sozinho. Mas os dois geram picos e lixo em momentos de muita atividade: questing com mobs de missão, login, banco, leilão.

**Recomendação de topo:** separar "o que muda pouco" (posições no mundo, disponibilidade de missões, custo de mana) de "o que muda muito" (posição do jogador, objetivos, um item específico). Hoje vários caminhos recalculam tudo quando só uma parte mudou. Isso resolve os quatro primeiros achados.

## Panorama por severidade

| Severidade | Quantidade |
|------------|-----------|
| 🔴 Crítico | 0 |
| 🟠 Alto    | 2 |
| 🟡 Médio   | 5 |
| 🟢 Baixo   | 5 |

## Achados

### 🟠 [A-01] ForeverMap: cada `QUEST_LOG_UPDATE` reavalia todas as missões da zona e reconstrói os ícones do minimapa

- **Local:**
  - `ForeverMap/Quests.lua:301-310` (`Changed` registrado em `QUEST_LOG_UPDATE`);
  - `ForeverMap/Pins.lua:297-299` (`MarkDirty` dispara `PinsDirty`);
  - `ForeverMap/Minimap.lua:1047-1107` (`RebuildPins`);
  - `ForeverMap/Quests.lua:55-103` (`ReadPlayer`, que termina em `wipe(available)`).
- **Categoria:** Performance
- **Problema:**
  - Desde que os ícones apareceram no minimapa, os dados de missão ficam carregados o tempo todo. Por isso `Changed` sempre chama `Pins:MarkDirty()`, e o minimapa reconstrói tudo 0,5 s depois.
  - A reconstrução chama `Quests:Collect` para a zona, e ele chama `ReadPlayer()`, que faz quatro coisas:
    - percorre o registro de missões inteiro;
    - lê as profissões;
    - monta uma tabela nova de nomes de perícia com 12 chamadas a `C_Spell.GetSpellName`;
    - **apaga o cache `available`**.
  - Com o cache apagado, cada missão de cada NPC da zona é reavaliada do zero. Isso inclui chamadas de API como `C_QuestLog.IsQuestFlaggedCompleted` e consultas de reputação.
  - Em seguida, o minimapa cria uma tabela nova por ícone e por candidato, e chama `C_Map.GetWorldPosFromMapPos` (que devolve um Vector2D novo) para cada um.
- **Impacto:**
  - `QUEST_LOG_UPDATE` dispara muito enquanto se faz missões (cada objetivo, cada item de missão no saque).
  - A espera de 0,5 s evita rodar a cada evento. Mas durante questing contínuo a reconstrução acontece a cada pausa, com centenas de chamadas de API e de tabelas novas em zonas cheias de NPCs.
  - O resultado é lixo para o coletor e pequenos picos de quadro justamente na atividade mais comum.
- **Correção sugerida:**
  1. **Separar disponibilidade de entrega.**
     - A disponibilidade (`available`) só muda com estes eventos: `QUEST_ACCEPTED`, `QUEST_TURNED_IN`, `QUEST_REMOVED`, `PLAYER_LEVEL_UP`, `SKILL_LINES_CHANGED`, `UPDATE_FACTION`, `LEARNED_SPELL_IN_TAB`. Só eles devem apagar o cache.
     - `QUEST_LOG_UPDATE` só altera o que está "pronto para entregar" (`complete`). Nele, basta reler `complete` e, se nada mudou, não reconstruir.
  2. **Ler o que é fixo uma vez só.** Calcular `byName` (nome da perícia → ID) e o lado do jogador uma única vez; eles não mudam na sessão.
  3. **Guardar as posições no mundo, que nunca mudam.** Para NPCs, entradas e portos:

  ```lua
  -- Quests.lua: só reavalia o que mudou
  local function CompleteChanged()
  	local changed = false
  	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
  		local info = C_QuestLog.GetInfo(index)
  		if info and not info.isHeader and info.questID then
  			local done = C_QuestLog.IsComplete(info.questID) or nil
  			if complete[info.questID] ~= done then changed = true; complete[info.questID] = done end
  		end
  	end
  	return changed
  end
  ns:RegisterEvent("QUEST_LOG_UPDATE", function() if GIVERS and CompleteChanged() then Pins:MarkDirty() end end)
  -- ...e só os eventos de disponibilidade fazem wipe(available)

  -- Minimap.lua: posição no mundo por (mapa, x, y), calculada uma vez
  local worldCache = {}
  local function WorldPos(mapID, x, y)
  	local key = mapID * 1e7 + math.floor(x * 1000) * 1000 + math.floor(y * 1000)
  	local pos = worldCache[key]
  	if pos == nil then
  		vector:SetXY(x, y)
  		local continent, world = C_Map.GetWorldPosFromMapPos(mapID, vector)
  		pos = world and {world.x, world.y, continent} or false
  		worldCache[key] = pos
  	end
  	return pos or nil
  end
  ```

### 🟠 [A-02] ForeverHub: qualquer `GET_ITEM_INFO_RECEIVED` redesenha a bolsa inteira

- **Local:**
  - `!ForeverHub/Bags/Data.lua:424-428` (o evento vira `ITEM_INFO` sem filtro);
  - `!ForeverHub/Bags/Container.lua:973-974` (`ITEM_INFO` vira `UpdateAll` das janelas abertas).
- **Categoria:** Performance
- **Problema:**
  - O evento dispara para cada item cujo dado chega do servidor. Isso vale para qualquer pedido: dicas, leilão, as listas de equipamento do GearQuest, a lista de compras de profissões, saque.
  - Com a bolsa ou o banco aberto, cada um agenda um `UpdateAll`, que atualiza todos os espaços: textura, borda, nível, "BoE", melhoria, desencantar, missão e cooldown.
  - O `Defer` agrupa os eventos do mesmo quadro. Mas uma chegada em sequência (abrir o banco, o leilão ou a lista de um vendedor) gera um redesenho completo em vários quadros seguidos.
- **Impacto:** quedas de FPS ao abrir banco, leilão e vendedores com a bolsa aberta. É o mesmo tipo de pico que aparece com Bagnon antigo.
- **Correção sugerida:** só redesenhar quando o item que chegou está nas bolsas, e só os espaços dele. O `Data` já tem o conteúdo ao vivo (`Data.live`); basta um índice de item para espaços, refeito no `Flush`:

  ```lua
  -- Data.lua, dentro de ScanBag: itemSlots[itemID] = {bag, slot, ...}
  ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, itemID, success)
  	if success and Data.itemSlots[itemID] then
  		Fire("ITEM_INFO", itemID) -- Container: atualiza só os espaços desse item
  	end
  end)
  ```

  Se for mais simples: ignorar o evento quando o item não estiver em nenhum espaço visível, e manter o `UpdateAll` só nesse caso raro.

### 🟡 [M-01] ForeverHub: `BAG_UPDATE_COOLDOWN` atualiza todos os espaços na hora, sem agrupar

- **Local:** `!ForeverHub/Bags/Data.lua:417` e `!ForeverHub/Bags/Container.lua:971-972`
- **Categoria:** Performance
- **Problema:**
  - O evento dispara com frequência em combate, a cada recarga ligada a itens e, neste motor, a cada recarga global.
  - Com a bolsa aberta, cada disparo percorre todos os espaços chamando `GetContainerItemCooldown` e `CooldownFrame_Set`, sem passar pelo `ns:Defer`.
  - Vários disparos no mesmo quadro fazem o trabalho repetido.
- **Impacto:** custo baixo por vez, mas multiplicado em combate com a bolsa aberta.
- **Correção sugerida:**
  - Agrupar: `ns:RegisterEvent("BAG_UPDATE_COOLDOWN", function() ns:Defer("bag-cooldowns", function() Fire("COOLDOWNS") end) end)`.
  - Atualizar só os espaços com item usável (`C_Item.IsUsableItem` ou `GetItemSpell` guardados por link no `UpdateLive`).

### 🟡 [M-02] ForeverHub: o filtro de links do chat cria uma closure e roda `gsub` em toda mensagem, uma vez por janela de chat

- **Local:** `!ForeverHub/Chat.lua:136-153` (`Linkify` e `Filter`), registrado em 15 eventos de chat na linha 181.
- **Categoria:** Performance
- **Problema:**
  - Os filtros de mensagem rodam **uma vez para cada janela de chat** que mostra aquele canal.
  - `Linkify` faz `text:gsub("(%S+)", function(word) ... end)` em toda mensagem. Isso cria uma closure nova a cada chamada e chama a função para cada palavra, com até três `match`.
  - Mensagens sem nenhum link (quase todas) pagam o custo inteiro.
- **Impacto:** lixo constante em canais movimentados (Comércio, Procurando Grupo, canal global do Forever), multiplicado pelo número de janelas.
- **Correção sugerida:**
  - Descartar logo com buscas literais, e só então fazer o `gsub` com uma função definida fora.
  - Guardar o último resultado, já que a mesma mensagem passa por várias janelas:

  ```lua
  local function LinkWord(word)
  	if word:find("|", 1, true) then return end
  	if word:match("^https?://%S+") or word:match("^www%.%S+%.%S+") or word:match("^discord%.gg/%S+") then
  		return Link(word)
  	end
  end
  local lastIn, lastOut
  local function Linkify(text)
  	if text == lastIn then return lastOut end
  	local out = text
  	if text:find("://", 1, true) or text:find("www.", 1, true) or text:find("discord.gg", 1, true) then
  		out = text:gsub("(%S+)", LinkWord)
  	end
  	lastIn, lastOut = text, out
  	return out
  end
  ```

### 🟡 [M-03] ForeverHub: barras de ação refeitas por inteiro (96 botões e 96 tabelas) a cada mudança

- **Local:**
  - `!ForeverHub/ActionBars.lua:84-89` (`UpdateAll`);
  - `!ForeverHub/ActionBars.lua:49` (`GetPowerCost` devolve uma tabela nova a cada chamada);
  - `!ForeverHub/ActionBars.lua:126-129` (eventos).
- **Categoria:** Performance
- **Problema:**
  - `ACTIONBAR_SLOT_CHANGED` informa **qual** espaço mudou, mas o handler refaz os 96 botões.
  - `SPELLS_CHANGED` e `UPDATE_SHAPESHIFT_FORM` também disparam a varredura completa. O primeiro dispara bastante neste motor (montar, formas, sobreposições de magia).
  - Cada botão com magia gera uma tabela de custo nova.
- **Impacto:**
  - Picos curtos ao trocar de forma, montar, mudar de página ou arrastar magias.
  - Com macros, o `MODIFIER_STATE_CHANGED` refaz os botões de macro a cada Shift/Ctrl/Alt em combate. Isso já está restrito às macros, o que é bom.
- **Correção sugerida:**
  - **Agrupar por espaço:** guardar os espaços mudados num conjunto e atualizar só eles. Usar `ns:Defer` como hoje, mas sobre o conjunto.
  - **Guardar o custo por magia:** `costCache[spellID]`, apagado em `SPELLS_CHANGED`, `PLAYER_LEVEL_UP` e `UNIT_AURA` do jogador (para custos que dependem de aura). Assim cada passada não cria 96 tabelas.
  - **Mapear espaço para botões:** com `buttonsBySlot[slot]` montado no login e na troca de página, a atualização por espaço fica direta.

### 🟡 [M-04] ForeverMap: os dados de missão (cerca de 480 KB de código) agora carregam no login

- **Local:**
  - `ForeverMap/Minimap.lua:1081-1108` (`SetupPins`, que chama `RefreshPins`);
  - `ForeverMap/Quests.lua:33-42` (`Load`);
  - `ForeverMap/Data/QuestGivers.lua` (6.300 linhas).
- **Categoria:** Performance (login e memória)
- **Problema:**
  - O README do ForeverMap promete que os dados de missão "só viram tabelas na primeira vez que são mostrados".
  - Com os ícones no minimapa ligados, essa primeira vez é logo depois do login: o `PLAYER_ENTERING_WORLD` dispara `RefreshPins`.
  - A tabela inteira fica na memória a sessão toda. Pelo tamanho do código-fonte, é provavelmente na casa de alguns MB; a medir.
- **Impacto:**
  - Um pico extra no carregamento, que já é o momento mais pesado.
  - Memória permanente para quem nem usa os ícones de missão no minimapa.
- **Correção sugerida:**
  - Carregar só se `ns.db.quests` ou `ns.db.turnins` estiver ligado.
  - Adiar o primeiro `RebuildPins` com missões para alguns segundos depois do login e fora de combate (`C_Timer.After(5, ...)`; se em combate, esperar `PLAYER_REGEN_ENABLED`).
  - Atualizar a nota do README.
  - Conferir na dica da linha de desempenho quanto o ForeverMap ocupa antes e depois.

### 🟡 [M-05] ForeverMap: cada reconstrução dos ícones do minimapa cria tabelas novas para todo candidato

- **Local:** `ForeverMap/Minimap.lua:1047-1068` (`RebuildPins`: `entry` vindo do provedor e `{entry = ..., x = ..., y = ...}` por candidato).
- **Categoria:** Performance (lixo para o coletor)
- **Problema:**
  - Os provedores criam uma tabela de entrada por ícone a cada `Collect`, como `NewEntry` em `Points.lua:56` e `add({...})` em `Quests.lua`.
  - O minimapa cria mais uma por candidato, e o `GetWorldPosFromMapPos` cria o vetor.
  - Para o mapa-múndi, que é reconstruído só ao trocar de mapa, tudo bem. No minimapa, isso soma ao [A-01].
- **Impacto:** lixo proporcional ao número de ícones da zona a cada reconstrução.
- **Correção sugerida:**
  - Reaproveitar uma lista de candidatos (como o `groups` de `Pins.lua` já faz) e guardar a posição no mundo, como no [A-01].
  - Para entradas, portos e mestres de voo, que nunca mudam, guardar a lista de candidatos por zona e só remontar a parte das missões.

### 🟢 [B-01] ForeverMap: ícones do minimapa reaplicam escala e dessaturação a cada atualização

- **Local:** `ForeverMap/Minimap.lua:1020-1022`
- **Categoria:** Performance
- **Problema:** com o jogador andando (até 20 vezes por segundo), cada ícone visível recebe `SetDesaturated`, `SetScale`, `ClearAllPoints` e `SetPoint`. Escala e dessaturação quase nunca mudam.
- **Correção sugerida:** guardar `pin.scale` e `pin.desaturated` e só aplicar quando mudarem. `SetScale` em particular força o layout do frame.

### 🟢 [B-02] ForeverMap: `ns:Defer` cria um timer novo a cada chamada

- **Local:** `ForeverMap/Core.lua:62-70`
- **Categoria:** Performance
- **Problema:**
  - Cada chamada faz `Cancel()` e `C_Timer.NewTimer` (um objeto novo).
  - Em eventos em rajada (os ícones a cada `QUEST_LOG_UPDATE`, o passar do mouse no minimapa) são dezenas de objetos descartados.
  - O ForeverHub resolve o mesmo problema sem alocar, com um frame e `OnUpdate` (`!ForeverHub/Core.lua:312-330`).
- **Correção sugerida:** guardar o prazo (`due[key] = GetTime() + delay`) e verificar num único frame com OnUpdate, que só fica visível enquanto houver algo pendente.

### 🟢 [B-03] ForeverMap: `ReadPlayer` monta `byName` e busca 12 nomes de magia a cada chamada

- **Local:** `ForeverMap/Quests.lua:89-95`
- **Categoria:** Performance
- **Problema:** os nomes das perícias não mudam na sessão, mas a tabela é refeita em todo `Collect`, tanto no mapa-múndi quanto no minimapa.
- **Correção sugerida:** montar `byName` uma vez, na primeira chamada.

### 🟢 [B-04] ForeverGroups: atualizar uma linha cria uma closure por evento

- **Local:** `ForeverGroups/UI/List.lua:344-353` (`UpdateResult` com `ForEachFrame(function ... end)`)
- **Categoria:** Performance
- **Problema:** `LFG_LIST_SEARCH_RESULT_UPDATED` dispara uma vez por resultado após cada busca. Cada disparo, com a janela aberta, cria uma closure e percorre os frames visíveis.
- **Correção sugerida:** manter um índice de resultado para frame (preenchido no inicializador das linhas) e atualizar direto, sem percorrer.

### 🟢 [B-05] ForeverHub: dicas de item recalculam contagens e ordenam a cada atualização da dica

- **Local:**
  - `!ForeverHub/Bags/Tooltip.lua:24-50` (`AddCounts`: tabelas novas e `table.sort` por chamada);
  - `!ForeverHub/Professions/Tooltip.lua:31-46` (`table.sort(uses, ...)` por chamada).
- **Categoria:** Performance
- **Problema:** passando o mouse num item da bolsa, o modelo da Blizzard atualiza a dica a cada 0,2 s (`UpdateTooltip`). Cada atualização refaz as tabelas de contagem e as ordenações.
- **Correção sugerida:** guardar o último resultado por itemID e apagá-lo nos eventos que mudam as bolsas. Ordenar a lista de receitas de cada material uma vez, quando o índice é montado em `BuildIndex`.

## Observações positivas

- **Um frame de eventos por addon e trabalho agrupado no quadro seguinte.** `ns:Defer` no ForeverHub, sem alocar, e `Prof:Schedule` nas profissões. Isso evita a armadilha mais comum de addons de bolsa (refazer tudo a cada `BAG_UPDATE`).
- **Nada roda com a janela fechada:**
  - as bolsas só marcam `dirty` (`Bags/Container.lua:941-947`);
  - o ForeverGroups marca a lista como velha;
  - a linha de desempenho e a de experiência param o ticker quando escondidas;
  - os ícones do mapa-múndi só trabalham com o mapa aberto.
- **Caches bem colocados:**
  - melhoria de equipamento por link, zerado ao trocar de equipamento;
  - item inutilizável por link, zerado ao subir de nível ou mudar perícias;
  - retângulos de mapa e posições do jogador sem criar tabelas (`ForeverMap/Core.lua`);
  - memória por addon só com a dica aberta, no máximo a cada 10 s e nunca em combate.
- **OnUpdate disciplinado:**
  - todos têm limite de frequência;
  - o atualizador de ícones do minimapa sai na primeira linha quando o jogador não se mexeu, não girou e não mudou o zoom;
  - os grupos do agrupamento de ícones do mapa-múndi são reaproveitados entre layouts.
- **Erros com limite de frequência e deduplicados** no capturador (`Errors/Grabber.lua`). Uma rajada de erros de outro addon não derruba o FPS.

## Recomendações priorizadas

1. **[A-01]** Separar disponibilidade de entrega no ForeverMap e guardar as posições no mundo. É o maior ganho na atividade mais comum, o questing.
2. **[A-02]** Filtrar `GET_ITEM_INFO_RECEIVED` pelos itens que estão nas bolsas e atualizar só os espaços deles.
3. **[M-02]** Descarte rápido e memória da última mensagem no filtro de links do chat. É uma mudança pequena com efeito constante em canais cheios.
4. **[M-01]** Agrupar `BAG_UPDATE_COOLDOWN` com `ns:Defer`.
5. **[M-03]** Atualizar as barras de ação por espaço e guardar o custo de mana por magia.
6. **[M-04]** Adiar e condicionar o carregamento dos dados de missão; corrigir a nota do README.
7. **[M-05], [B-01] a [B-05]** Ajustes finos de alocação. Fazer junto quando tocar nesses arquivos.
8. **Medir antes e depois:**
   - comparar a memória do ForeverMap e do ForeverHub na dica da linha de desempenho, logo após o login e depois de 10 minutos fazendo missões;
   - comparar o FPS mínimo ao abrir o banco com a bolsa aberta.

   Isso confirma as estimativas deste relatório, que vieram só da leitura do código.

## Status das correções (2026-11-05)

Todos os achados foram aplicados; falta medir no jogo.

| Achado | O que foi feito |
|--------|-----------------|
| A-01 | `Quests.lua`: o registro é lido por diferença (`ReadLog`); `QUEST_LOG_UPDATE` só redesenha se algo ficou pronto ou mudou, e só recalcula a disponibilidade se mudou o conjunto de missões. A disponibilidade fica guardada por NPC até um evento que a muda. `Minimap.lua`: posição no mundo guardada por ponto. |
| A-02 | `Bags/Data.lua` guarda os itens de cada bolsa (`Data.ids`); `Container:UpdateItems` redesenha só os espaços dos itens que chegaram. |
| M-01 | `BAG_UPDATE_COOLDOWN` agrupado com `ns:Defer`; a recarga só é lida em itens com efeito de uso. |
| M-02 | Descarte por busca literal, função fora da chamada e memória da última mensagem. |
| M-03 | Custo de mana guardado por magia (exceto custos que dependem de aura), atualização por espaço em `ACTIONBAR_SLOT_CHANGED`, texto só reescrito quando muda. |
| M-04 | Dados de missão carregam só com os ícones de missão ligados, 5 s depois do login e fora de combate (ou na hora com o mapa-múndi aberto). README corrigido. |
| M-05 | Lista de candidatos reaproveitada; trocar de subzona não reconstrói. |
| B-01 | Escala e dessaturação dos ícones só aplicadas quando mudam. |
| B-02 | `ns:Defer` do ForeverMap com um frame e prazos, sem timer por chamada. |
| B-03 | Nomes das perícias lidos uma vez. |
| B-04 | Visitante das linhas definido uma vez, sem closure por evento. |
| B-05 | Linhas de contagem guardadas por item até as contagens mudarem (`Data.countsVersion`); receitas de cada material ordenadas uma vez no índice. |
