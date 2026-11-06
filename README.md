# ForeverHub

Addon tudo-em-um para o WoW Forever: bolsas, mover janelas, capturador de erros e várias comodidades, num addon leve e escrito do zero. Substitui o Bagnon, o BlizzMove, o BugSack, o DisenchantBuddy e o ForeverLootSparkles.

## Como usar

- `/fh` lista os comandos; as opções ficam em Opções > AddOns > ForeverHub, no botão do minimapa e no menu de addons.
- `/fh disableold` desativa os addons que o ForeverHub substitui (só neste personagem) e recarrega. Enquanto um deles estiver ativo, o módulo correspondente do ForeverHub fica desligado.
- Outros comandos: `/fh bags`, `/fh bank` (banco offline), `/fh errors`, `/fh junk`, `/fh restock`, `/fh gold`, `/fh perf`, `/fh copychat`, `/fh reset`.

## Recursos

**Bolsas e banco**
- Inventário e banco numa janela cada, com busca, organizar, barra de bolsas e bolsas de profissão separadas.
- Banco e bolsas dos outros personagens, também fora do banco; quantos de cada item cada personagem tem, na dica do item.
- Marcas nos itens: qualidade, lixo, missão, nível do item, "vincula ao equipar", inutilizável, novo e % de melhoria sobre o que está equipado.
- Botão para abrir caixas, mariscos e sacos (um por clique); munição e fragmentos de alma no rodapé, com aviso.

**Vendedor e automações**
- Vende o lixo e conserta ao abrir o vendedor (com o dinheiro da guilda primeiro, quando permitido); reabastece itens escolhidos.
- Saque mais rápido, aviso de limite de item único, aceitar ressurreição e esconder as mensagens de erro vermelhas (as importantes, como bolsa cheia, continuam).

**Mover janelas**
- Arraste e mude a escala das janelas da Blizzard; posições salvas na sessão ou sempre.

**Capturador de erros**
- Guarda os erros de Lua em silêncio, com contador no minimapa, link `[Erros]` no chat e uma janela para ler e copiar.

**Chat**
- Links da web clicáveis, botão para copiar o chat, dica ao passar o mouse em links, ícone, nível e melhoria ao lado dos itens.
- Canais abreviados, destaque do seu nome e de palavras escolhidas, histórico depois do `/reload`, setas sem Alt e Alt+clique para convidar.
- Barra de canais: letras coloridas na linha das abas que abrem a caixa de texto no canal.

**Missões, correio e lembretes**
- Nível das missões no rastreador e no registro; XP das missões prontas na linha de experiência; melhor recompensa marcada.
- Correio: "Pegar tudo", seus personagens e destinatários recentes, o último já preenchido.
- Nível do item e durabilidade baixa nos espaços do personagem e de inspecionar.
- Lembretes clicáveis, fora de combate, de buffs da classe faltando ou acabando e do ajudante (chamar, reviver, alimentar, invocar).

**Brilhos e interação**
- Brilho nos itens de missão (mesmo depois dos presets gráficos), ícone da ação acima do objeto próximo e brilhos dourados em minério, ervas e corpos com saque.

**Informações**
- Linha de experiência (XP/h, tempo até o próximo nível, descansado), durabilidade, FPS e latência, ouro ganho e gasto, custo de mana nas barras de ação.
- Dicas: IDs, preço unitário, alvo do alvo e o que dá ao desencantar.
- Profissões: lista de compras, guia para subir a perícia, receitas que usam cada material e perícia de esfolar nos inimigos.
- Gráficos e câmera: densidade e distância da grama, zoom máximo, distância das placas de nome e outras configurações do jogo.

## Documentos

- [docs/MELHORIAS.md](docs/MELHORIAS.md): o que foi feito e as ideias pendentes.
- [docs/REGRAS-BLIZZARD.md](docs/REGRAS-BLIZZARD.md): análise de cada recurso frente às regras de addons da Blizzard.

## Notas técnicas

- Módulos independentes, iniciados na ordem do TOC; cada um pode ser desligado nas opções.
- Só ganchos (`hooksecurefunc`, `HookScript`) no código da Blizzard, para não "contaminar" a interface; ações protegidas esperam o fim do combate.
- Em masmorras e raides, dados que o jogo marca como secretos são só exibidos, nunca comparados nem salvos.
