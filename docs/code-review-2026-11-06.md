# Revisão: desempenho e opções do ForeverHub

**Data:** 2026-11-06

**Escopo revisado:**
- **Desempenho:** o ForeverHub inteiro (cerca de 12 mil linhas). Foi lido a fundo o que entrou depois da revisão de 05/11: chat, brilhos, missões, correio, extras das bolsas, níveis nos espaços e lembretes. Nos módulos antigos, conferi que as correções de 05/11 continuam no lugar e procurei regressões.
- **Opções:** a página de opções (`Options.lua`), do ponto de vista de quem usa (UX).
- **Fora do escopo:** o ForeverMap e o ForeverGroups.
- **Nada foi medido no jogo.** O custo de cada caso foi estimado pela leitura do código.

## Resumo executivo

Os módulos antigos continuam bem: um frame de eventos para todos os módulos, eventos em rajada agrupados com `ns:Defer`, nada redesenhado com a janela fechada e cache nas dicas. Não há regressão.

Os problemas estão no código das últimas sessões, e todos no mesmo estilo: **trabalho periódico ou por evento que não olha se é necessário.** Em ordem de impacto:
1. **Lembretes** escutam `UNIT_AURA` e `UNIT_HEALTH` de todas as unidades. Isso dá centenas de chamadas por segundo em grupo e raide, só para descartar quase todas. Os lembretes também refazem tudo a cada segundo, mesmo sem nada para mostrar.
2. **Botão de abrir caixas** varre todas as bolsas (uma tabela nova por espaço, e uma dica lida por item que dá para abrir) a cada mudança nas bolsas, mesmo com a bolsa fechada. Num caçador, isso acontece a cada tiro.
3. **Brilhos** reclassificam o objeto mirado, lendo o cursor do jogo, 6 vezes por segundo, embora o objeto só mude quando o jogo avisa.

Nenhum deles trava o jogo. Mas os três são custo fixo e constante, justamente no combate em grupo, onde mais pesa. As correções são pequenas e locais.

**As opções** cresceram para 17 seções numa página só, de cerca de 3.000 pixels de rolagem. Opções que o jogador pensa como uma coisa só estão em lugares diferentes. Esse foi o motivo exato da dúvida sobre desencantar: o ícone fica em Bolsas e a dica fica em Dicas. A recomendação é dividir por contexto, em subpáginas, e juntar cada módulo com o seu liga/desliga.

## Panorama por severidade

| Severidade | Quantidade |
|------------|-----------|
| 🔴 Crítico | 0 |
| 🟠 Alto    | 2 |
| 🟡 Médio   | 3 |
| 🟢 Baixo   | 3 |

## Achados de desempenho

### 🟠 [A-01] Lembretes: eventos de unidade de todo mundo e uma reconstrução por segundo

- **Local:** [Reminders.lua:334-356](../Reminders.lua#L334-L356)
- **Categoria:** Performance
- **Problema:**
  - `UNIT_AURA` e `UNIT_HEALTH` estão registrados no frame geral do addon. Eles disparam para cada unidade: grupo, raide, alvo, foco e cada placa de nome. O código só quer `player` e `pet`.
  - O timer de 1 s chama `Update()` sempre que a opção está ligada, ou seja, o tempo todo. Cada passada faz quatro coisas:
    - lê todos os buffs, e cada `C_UnitAuras.GetAuraDataByIndex` cria uma tabela;
    - chama `GetSpellName` várias vezes por grupo de magias;
    - recria a lista de ícones;
    - em `Show()`, refaz `SetAttribute`, `SetTexture` e a posição de cada botão.
- **Impacto:**
  - Em raide, de dezenas a centenas de chamadas Lua por segundo, quase todas descartadas na primeira linha.
  - Fora de combate, uma passada completa por segundo que gera lixo para o coletor, mesmo sem nenhum lembrete visível.
- **Correção sugerida:**
  - Um frame próprio com `RegisterUnitEvent("UNIT_AURA", "player")`, `("UNIT_HEALTH", "pet")` e `("UNIT_INVENTORY_CHANGED", "player")`.
  - Nomes das magias lidos uma vez.
  - O timer só roda enquanto algum lembrete mostra contagem, ou algum buff acompanhado está a menos de 70 s do fim. Os eventos cuidam do resto.
  - `Show()` só mexe nos botões quando a lista mudou.

### 🟠 [A-02] Abrir caixas: varredura completa das bolsas a cada mudança, com a bolsa fechada

- **Local:** [BagExtras.lua:34-45](../BagExtras.lua#L34-L45) e [BagExtras.lua:146-153](../BagExtras.lua#L146-L153)
- **Categoria:** Performance
- **Problema:**
  - Cada `BAG_UPDATE_DELAYED` roda `Scan()` nos até 80 espaços. `C_Container.GetContainerItemInfo` cria uma tabela por espaço, e cada item que dá para abrir ainda tem a dica lida com `C_TooltipInfo.GetBagItem`, para ver se está trancado.
  - Isso acontece mesmo com a janela das bolsas fechada, quando o botão nem aparece.
  - Para o caçador, a munição muda a cada tiro.
- **Impacto:** lixo e trabalho constantes em combate (caçador), ao saquear e ao vender, sem efeito visível.
- **Correção sugerida:**
  - Varrer só com a janela das bolsas aberta e, no `OnShow` dela, com a bolsa fechada só marcar como "a refazer".
  - O aviso de munição baixa continua sempre, porque só usa `GetInventoryItemCount`, que é barato.

### 🟡 [M-01] Brilhos: a classificação do objeto é refeita a cada 0,15 s

- **Local:** [Sparkles.lua:136-176](../Sparkles.lua#L136-L176) e [Sparkles.lua:292-320](../Sparkles.lua#L292-L320)
- **Categoria:** Performance
- **Problema:** com um objeto mirado, cada passada do poll faz três coisas:
  - chama `SetUnitCursorTexture`, que pede ao jogo o cursor do objeto;
  - lê a textura e procura palavras no nome dela;
  - em corpos, chama `CanLootUnit`.

  Mas o objeto só muda quando chega `PLAYER_SOFT_INTERACT_CHANGED`. Entre um aviso e outro, só o alcance precisa ser conferido.
- **Correção sugerida:**
  - Guardar a classificação pelo GUID do alvo e refazê-la só quando o alvo mudar.
  - No poll, conferir só o alcance e o "trancado".
  - O poll pode ir para 0,2 s.

### 🟡 [M-02] Destaque no chat cria uma função por palavra procurada, em cada mensagem

- **Local:** [Chat.lua:232-239](../Chat.lua#L232-L239)
- **Categoria:** Performance
- **Problema:** `segment:gsub(pattern, function(found) ... end)` cria uma função nova para cada palavra, em cada trecho de cada mensagem que tenha alguma palavra.
- **Correção sugerida:** usar `segment:gsub(pattern, "|cffff9a1f%0|r")`, que faz a mesma coisa sem criar função.

### 🟡 [M-03] Lembretes: o laço de 1 s continua mesmo com a opção desligada

- **Local:** [Reminders.lua:352-354](../Reminders.lua#L352-L354)
- **Categoria:** Performance
- **Problema:** o timer é criado sempre, e a condição `holder:IsShown() or settings.buffReminders` não considera os lembretes do ajudante. Com tudo desligado, ele continua acordando a cada segundo.
- **Correção sugerida:** criar e cancelar o timer em `Reminders:Refresh()`, junto com a correção de A-01.

### 🟢 [B-01] Extras das bolsas: `UNIT_INVENTORY_CHANGED` sem filtro de unidade

- **Local:** [BagExtras.lua:150](../BagExtras.lua#L150)
- **Correção sugerida:** `RegisterUnitEvent(..., "player")` num frame próprio, ou deixar a munição só com `BAG_UPDATE_DELAYED`.

### 🟢 [B-02] Melhor recompensa: nova tentativa sem cancelar a anterior

- **Local:** [Quests.lua:208-212](../Quests.lua#L208-L212)
- **Problema:** se `QUEST_COMPLETE` chega duas vezes seguidas, há duas sequências de novas tentativas, e a mensagem pode sair duas vezes no chat.
- **Correção sugerida:** um contador de geração. Cada tentativa confere se ainda é a mais recente.

### 🟢 [B-03] Linha de experiência: soma das missões prontas refeita a cada redesenho

- **Local:** [Experience.lua](../Experience.lua) e [Quests.lua:123-141](../Quests.lua#L123-L141)
- **Problema:** nenhum. O cálculo só roda com a linha visível e quando o registro de missões mudou. Fica registrado como conferido.

## Opções: problemas de usabilidade

1. **Uma página só, longa demais.**
   - São 17 seções e cerca de 3.000 pixels de rolagem.
   - Achar uma opção depende de lembrar em que altura ela está.
   - A busca das Opções do jogo não enxerga páginas próprias, então não há atalho.
2. **Coisas da mesma tarefa estão espalhadas:**

   | Tarefa | Onde está hoje |
   |---|---|
   | Desencantar | o ícone em Bolsas, a dica em Dicas |
   | Equipamento | durabilidade em Equipamento, nível nos espaços em Missões e lembretes, % de melhoria em Bolsas |
   | Experiência | a linha em Progresso, a XP das missões prontas em Missões e lembretes |
   | Bolsas | marcas em Bolsas, abrir caixas e munição em Missões e lembretes |
   | Profissões | esfolar e materiais na dica em Profissões, mas as outras dicas em Dicas |
3. **O liga/desliga dos módulos fica longe das opções de cada módulo.** "Bolsas", "Mover janelas" e "Capturador de erros" são ligados no topo, mas configurados três telas abaixo.
4. **Dependências não aparecem.** "Só melhorias" sem "% de melhoria", "Usar fundos da guilda" sem "Consertar", e as palavras e o som sem "Destacar" continuam clicáveis e parecem fazer algo.
5. **Rótulos longos cortados nas duas colunas:** foi o caso do BoE. As explicações deveriam ir para a dica da caixa de seleção, não para o rótulo.
6. **"Depois de /reload" aparece em notas soltas.** Não há um aviso único com o botão de recarregar quando uma dessas opções muda. Hoje o botão Recarregar só aparece para os módulos.

## Recomendações priorizadas

1. **A-01 e M-03 (lembretes):** eventos com filtro de unidade, timer só quando há contagem, redesenho só quando a lista muda.
2. **A-02 e B-01 (extras das bolsas):** varrer só com a bolsa aberta.
3. **M-01 (brilhos):** classificação guardada por alvo.
4. **Opções em subpáginas por contexto,** com o liga/desliga de cada módulo no topo da sua página, dependências desabilitando as opções filhas, rótulos curtos com explicação na dica, e um aviso único de "recarregar" com o botão.
5. **M-02 e B-02:** ajustes pequenos.

## Status (aplicado em 06/11/2026)

| Achado | Status |
|---|---|
| A-01 e M-03, lembretes | ✅ Eventos de unidade só do jogador e do ajudante (frame próprio com `RegisterUnitEvent`, também para `UNIT_SPELLCAST_SUCCEEDED`). A próxima verificação é agendada a cada 1 s só com buff a menos de 70 s do fim; senão, a cada 30 s. Nomes das magias lidos uma vez. Os botões só mudam no que mudou. |
| A-02 e B-01, extras das bolsas | ✅ Bolsas lidas só com a janela aberta (e ao abrir). O aviso de munição continua sempre. `UNIT_INVENTORY_CHANGED` só do jogador. |
| M-01, brilhos | ✅ Classificação guardada pelo GUID do alvo, refeita em `PLAYER_SOFT_INTERACT_CHANGED`. Poll em 0,2 s. |
| M-02, destaque no chat | ✅ `gsub` com texto de substituição (`%0`), sem função. |
| B-02, melhor recompensa | ✅ Rodadas numeradas: tentativas antigas param quando chega outro `QUEST_COMPLETE`. |
| Opções | ✅ Página inicial com o estado dos addons substituídos, mais 9 subpáginas: Bolsas e banco, Vendedor/saque/correio, Personagem e missões, Chat, Dicas, Interface, Janelas e erros, Profissões, Gráficos e câmera. Liga/desliga de cada módulo no topo da sua página; desencantar todo numa seção só; opções filhas apagadas quando a mãe está desligada; explicações nas dicas; barra "Recarregar" quando uma opção que precisa de /reload muda. O botão de engrenagem das bolsas abre direto a página das bolsas. |
