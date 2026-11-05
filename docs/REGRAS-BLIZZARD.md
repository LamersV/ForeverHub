# Regras da Blizzard – análise do !ForeverHub

Análise feita em 31/10/2026, lendo o código. Nada foi alterado por causa dela.

**Conclusão: nenhuma funcionalidade vai contra as regras.** Há alguns pontos de atenção, listados no fim, que são permitidos mas valem a pena conhecer.

Base: a política da Blizzard para addons de interface (UI Add-On Development Policy) e os Termos de Uso.

## O que as regras pedem

| Regra | Situação no ForeverHub |
|---|---|
| Ser gratuito | ✅ Não há nada pago |
| Código aberto e legível, sem ofuscação | ✅ Lua puro e comentado |
| Não pesar no servidor (spam de comandos ou mensagens) | ✅ Não envia nada ao servidor por conta própria |
| Sem anúncios nem pedido de doação no jogo | ✅ Não tem |
| Sem conteúdo ofensivo | ✅ |
| Não automatizar o jogo (bots, ações sem clique) | ✅ Toda ação parte de um clique ou comando do jogador |

O código foi verificado em busca de funções sensíveis: uso automático de item, envio de mensagens no chat, comunicação entre addons, macros, lançar feitiços, escolher alvo. **Nenhuma aparece.** O addon também não faz conexão de rede, e nada sai do computador.

## Funcionalidade por funcionalidade

**Bolsas e banco** ✅
- Organizar chama `C_Container.SortBags` / `SortBankBags`, as mesmas funções do botão de organizar da Blizzard. Só roda com clique.
- Arrastar bolsas na barra usa `PutItemInBag` / `PickupBagFromSlot`, sempre a partir de um clique, como arrastar na barra padrão.
- Os botões de item usam o modelo de botão da própria Blizzard. Usar, vender e mover itens continua sendo o código da Blizzard; o addon não usa itens sozinho.
- Itens de outros personagens são salvos em `SavedVariables`, num arquivo local. O Bagnon e o BagBrother fazem o mesmo há anos.

**Quantidades na dica do item e ouro de todos** ✅ Só lê os dados locais salvos.

**Mover janelas** ✅
- Mover e mudar a escala de janelas é permitido; o BlizzMove existe há mais de 15 anos.
- Em combate, janelas protegidas esperam a luta terminar, como a regra técnica do jogo exige. Por isso o addon não gera bloqueios.

**Capturador de erros** ✅ Só lê erros de Lua da interface e guarda localmente. Mesma técnica do BugGrabber.

**Ocultar avisos "AddOn bloqueado"** ✅ Os avisos continuam registrados na janela de erros, só não aparecem como pop-up. O BugGrabber faz igual.

**`/fh disableold`** ✅ Usa a função oficial `C_AddOns.DisableAddOn` e recarrega a interface. Só roda quando o jogador digita o comando ou clica no botão.

**Link `[Erros]` no chat** ✅ Tipo de link próprio para addons. Só o jogador vê; nada é enviado a outros.

## Pontos de atenção (permitidos, mas bom saber)

1. **O capturador de erros "tranca" o controle de erros.** Em [Errors/Grabber.lua:146](../Errors/Grabber.lua#L146), depois de instalar o próprio capturador, o addon troca `seterrorhandler` por uma função que não faz nada. Outro addon de erros não consegue capturar. É intencional e igual ao BugGrabber, mas pode confundir se outro addon de erros for instalado: ele vai parecer "não funcionar".

2. **Janelas da Blizzard são escondidas trocando o "pai" delas** ([Bags/Blizzard.lua](../Bags/Blizzard.lua)). As bolsas padrão vão para um frame oculto; a janela do banco fica invisível e minúscula, mas continua "aberta" para o jogo. É permitido e é a forma comum de substituir as bolsas. O risco é técnico, não de regra: no pior caso, um aviso de "AddOn bloqueado" ou uma janela que não abre. O botão "Banco" volta à janela original.

3. **`/fh disableold` desativa os outros addons só para o personagem atual** ([Core.lua:215](../Core.lua#L215)). Em outro personagem, Bagnon, BlizzMove e BugSack continuam ativos e os módulos do ForeverHub ficam desligados até rodar o comando ali também. Questão de comportamento, não de regra.

4. **Os erros salvos podem incluir nomes de personagens ou textos do chat**, quando aparecem nas variáveis locais de um erro. Ficam só em `WTF\...\SavedVariables\!ForeverHub.lua`. Se esse arquivo for enviado a alguém, essas informações vão junto.

5. **Se o addon for publicado** (CurseForge, Wago etc.): a política exige que seja gratuito e com código aberto, o que já é atendido. Fora das regras da Blizzard: o Bagnon e o BugSack são "Todos os direitos reservados". Como o ForeverHub foi escrito do zero, sem copiar código deles, não há problema. Evitar dizer na descrição que ele "contém" esses addons; "substitui" ou "alternativa a" é o adequado.

6. **Regras do próprio Forever:** o WoW Forever pode ter regras próprias sobre addons, além das gerais da Blizzard. Não foram verificadas. Conferir nos avisos ou no fórum oficial do Forever.
