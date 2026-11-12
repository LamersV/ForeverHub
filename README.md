# ForeverHub

Addon tudo-em-um para o WoW Forever: bolsas, mover janelas, capturador de erros e várias comodidades, num addon leve e escrito do zero. Substitui o Bagnon, o BlizzMove, o BugSack, o DisenchantBuddy, o ForeverLootSparkles e o Lueur.

## Como usar

- `/fh` lista os comandos; as opções ficam em Opções > AddOns > ForeverHub, no botão do minimapa e no menu de addons.
- `/fh disableold` desativa os addons que o ForeverHub substitui (só neste personagem) e recarrega. Enquanto um deles estiver ativo, o módulo correspondente do ForeverHub fica desligado.
- Outros comandos: `/fh glow` (brilho dos objetos), `/fh bags`, `/fh bank` (banco offline), `/fh errors`, `/fh junk`, `/fh restock`, `/fh gold`, `/fh perf`, `/fh copychat`, `/fh reset`.

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
- Visual do chat: abas numa faixa escura com borda dourada fina, separadas por linhas finas (a selecionada em dourado), a janela e a caixa de digitar na mesma caixa; a borda da caixa de digitar fica da cor do canal.
- Barra de canais: uma faixa escura com borda dourada fina e os canais separados por linhas finas, todos do mesmo tamanho, na linha das abas, que abrem a caixa de texto no canal (a letra de sussurro responde o último). O botão "+" no canto do chat (ou clique direito numa letra) abre uma aba do jogo, ao lado de Geral, só com um canal (Grupo, Guilda, Sussurros, Comércio...), já com o que foi dito recentemente.
- Termos do WoW no chat viram links: passar o mouse ou clicar em LFM, LoS, RFC, WTS, BoE, SR... mostra o significado (nomes de masmorras no idioma do jogo).

**Missões, correio e lembretes**
- Nível das missões no rastreador e no registro; XP das missões prontas na linha de experiência; melhor recompensa marcada.
- Correio: "Pegar tudo", seus personagens e destinatários recentes, o último já preenchido.
- Nível do item nos espaços do personagem e de inspecionar (a durabilidade fica embaixo de cada espaço).
- Lembretes clicáveis, fora de combate, de buffs da classe faltando ou acabando e do ajudante (chamar, reviver, alimentar, invocar).

**Brilho dos objetos** (`/fh glow`)
- Luz no objeto que você está prestes a usar: minério, ervas, objetos de missão (com o progresso, 3/8), baús, a boia de pesca (mesmo longe), corpos com saque e, se quiser, os outros objetos. Fraca fora de alcance, viva ao alcance, cinza quando o jogo recusa (perícia baixa).
- Janela própria com prévia em 3D do objeto (girar, mover, zoom): 15 efeitos (Aura, Sutil, Selo, Mira, Vórtice, Fenda, Chama, Tempestade, Feixe, Gêiser, Farol, Órbita, Espírito, Ondas, Faíscas), cor, tamanho, intensidade e altura; nome e ícone da ação acima da luz, com tamanho e fonte. Tudo vale para todos os objetos ou só para um tipo.
- A luz passa atrás do personagem, some junto com a placa de nome se quiser, e só o que brilha é marcado pelo jogo (PNJs continuam funcionando com a tecla de interagir). Alcance, direção, tecla de interagir, objetos ignorados e quando esconder (combate, instâncias, sem a profissão).
- Animado pelo motor do jogo: nenhum código roda por quadro, só nas mudanças de estado. Texturas próprias, geradas para o ForeverHub.
- Brilho nos itens de missão (mesmo depois dos presets gráficos).
- Farol de missão: aura pulsante no corpo, marca de missão com o progresso (3/8) e feixe de luz em todas as criaturas que uma missão ainda precisa. Cor, tamanho e intensidade da luz ajustáveis.

**Informações**
- Linha de experiência (XP/h, tempo até o próximo nível, descansado), durabilidade, FPS e latência, ouro ganho e gasto, custo de mana nas barras de ação.
- Dicas: IDs, preço unitário, alvo do alvo e o que dá ao desencantar.
- Profissões: lista de compras, guia para subir a perícia, receitas que usam cada material e perícia de esfolar nos inimigos.
- Gráficos e câmera: densidade e distância da grama, detalhe do terreno, distância e tamanho mínimo dos objetos, reflexos na água, densidade do clima, nitidez, zoom máximo, distância das placas de nome e outras configurações do jogo.

## Documentos

- [docs/MELHORIAS.md](docs/MELHORIAS.md): o que foi feito e as ideias pendentes.
- [docs/REGRAS-BLIZZARD.md](docs/REGRAS-BLIZZARD.md): análise de cada recurso frente às regras de addons da Blizzard.

## Notas técnicas

- Módulos independentes, iniciados na ordem do TOC; cada um pode ser desligado nas opções.
- Só ganchos (`hooksecurefunc`, `HookScript`) no código da Blizzard, para não "contaminar" a interface; ações protegidas esperam o fim do combate.
- Em masmorras e raides, dados que o jogo marca como secretos são só exibidos, nunca comparados nem salvos.
