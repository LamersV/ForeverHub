--[[
	Chat terms: WoW abbreviations in what players write (LFM, LoS, RFC, WTS...) become links.
	Mouse over shows what they mean; a click keeps it open (in the game's link window).

	The words are marked by Chat.lua's message filter, only outside links, icons and color
	codes. Dungeon, raid and battleground names come from the game itself
	(GetRealZoneText), so they are in the game's language.
--]]

local _, ns = ...
local L = ns.L

local ChatTerms = ns:NewModule("ChatTerms")

local PT = GetLocale() == "ptBR"
local COLOR = "ffa8d8ff" -- light blue: a link, but softer than item and web links

-- {words, English, Portuguese, exact}. Words separated by spaces share the meaning; exact:
-- only in capitals (OS, MS, SR... are common words in Portuguese).
local TERMS = {
	-- groups
	{"LFG", "Looking for group: a player who wants to join a group.", "Procurando grupo: jogador que quer entrar num grupo."},
	{"LFM LMF", "Looking for more: a group that needs more players.", "Procurando mais: grupo que precisa de mais jogadores."},
	{"LF", "Looking for (\"LF tank\": looking for a tank).", "Procurando (\"LF tank\": procurando um tanque)."},
	{"LFW", "Looking for work: a crafter offering their profession.", "Procurando trabalho: artesão oferecendo a profissão."},
	{"PT", "Party: the group.", "Party: o grupo."},
	{"DG DUNG", "Dungeon.", "Masmorra (dungeon)."},
	{"INV", "Invite (to the group).", "Convidar para o grupo."},
	{"RL", "Raid leader.", "Líder da raide."},
	{"MT", "Main tank: the tank who holds the boss.", "Tanque principal: quem segura o chefe."},
	{"OT", "Off tank: the second tank.", "Tanque secundário."},
	{"DPS", "Damage per second; also the players who deal the damage.", "Dano por segundo; também os jogadores que causam o dano no grupo."},
	{"HEALER HEALS", "The player who heals the group.", "Quem cura o grupo."},
	{"SUMM SUMMON", "Summon: a warlock brings players with the Ritual of Summoning.", "Invocar: o bruxo traz jogadores com o Ritual de Invocação."},
	{"PORT", "A mage portal to a city.", "Portal de mago para uma cidade."},
	-- trade
	{"WTS", "Want to sell.", "Quer vender."},
	{"WTB", "Want to buy.", "Quer comprar."},
	{"WTT", "Want to trade (item for item).", "Quer trocar (item por item)."},
	{"PST", "Please send tell: whisper me.", "Me mande um sussurro."},
	{"PM", "Private message: a whisper.", "Mensagem privada: um sussurro."},
	{"AH", "Auction House.", "Casa de Leilões.", true},
	{"COD", "Cash on delivery: mail paid on receipt.", "Correio pago na entrega (o destinatário paga para pegar)."},
	{"TIP", "A tip for a service (enchant, portal, craft).", "Gorjeta por um serviço (encantamento, portal, item feito)."},
	-- loot
	{"BIS", "Best in slot: the best item for that slot.", "Melhor item possível para aquele espaço (best in slot)."},
	{"BOP", "Bind on pickup: bound to whoever loots it.", "Vinculado ao recolher: fica preso a quem saquear."},
	{"BOE", "Bind on equip: can be traded until worn.", "Vinculado ao equipar: dá para vender ou trocar até alguém usar."},
	{"MS", "Main spec: roll for the role you play (priority).", "Especialização principal: rola pelo papel que você joga (tem prioridade).", true},
	{"OS", "Off spec: roll for another role (after main spec).", "Especialização secundária: rola por outro papel (depois da principal).", true},
	{"SR", "Soft reserve: an item reserved before the run; only those who reserved it roll.", "Reserva leve: item reservado antes da masmorra; só rola quem reservou.", true},
	{"HR", "Hard reserve: an item that already has an owner.", "Reserva fixa: item que já tem dono.", true},
	{"ML", "Master looter: the leader hands out the loot.", "Mestre do saque: o líder distribui os itens."},
	{"FFA", "Free for all: whoever takes it first keeps it.", "Livre: quem pegar primeiro leva."},
	{"NINJA", "Takes loot they should not (rolls Need without needing it).", "Pega item que não devia (rola Necessidade sem precisar)."},
	-- combat
	{"LOS LOSS", "Line of sight: going behind a wall or pillar so casters must come to you.", "Linha de visão: ir para trás de uma parede ou pilar para os conjuradores virem até você."},
	{"AGGRO AGRO", "Threat: who the monster is attacking.", "Ameaça: em quem o monstro está batendo."},
	{"PULL", "Bring monsters into the fight.", "Puxar monstros para a luta."},
	{"CC", "Crowd control: taking a monster out of the fight (sheep, sap, trap...).", "Controle de grupo: tirar um monstro da luta (polimorfia, aturdir, armadilha...)."},
	{"AOE", "Area of effect: hits many targets.", "Área de efeito: atinge vários alvos."},
	{"DOT", "Damage over time.", "Dano ao longo do tempo."},
	{"HOT", "Heal over time.", "Cura ao longo do tempo."},
	{"CD CDS", "Cooldown: the wait before a skill can be used again.", "Tempo de recarga de uma habilidade."},
	{"OOM", "Out of mana.", "Sem mana."},
	{"MOB MOBS", "A monster (an enemy run by the game).", "Monstro (inimigo controlado pelo jogo)."},
	{"NPC", "Non-player character: someone run by the game.", "Personagem controlado pelo jogo."},
	{"WIPE", "The whole group died.", "O grupo inteiro morreu."},
	{"RES REZ", "Resurrect.", "Ressuscitar."},
	{"KOS", "Kill on sight.", "Matar assim que ver."},
	{"GY", "Graveyard.", "Cemitério."},
	{"HS", "Hearthstone.", "Pedra de Regresso."},
	-- talk
	{"AFK", "Away from keyboard.", "Ausente do teclado."},
	{"BRB", "Be right back.", "Já volto."},
	{"OMW", "On my way.", "Estou a caminho."},
	{"GZ GRATS", "Congratulations.", "Parabéns."},
	{"GG", "Good game.", "Bom jogo."},
	{"GL", "Good luck.", "Boa sorte."},
	{"TY THX", "Thank you.", "Obrigado."},
	{"NP", "No problem.", "De nada / sem problema."},
	{"IRL", "In real life.", "Na vida real."},
	-- cities and zones
	{"SW", "Stormwind.", "Ventobravo."},
	{"IF", "Ironforge.", "Altaforja.", true},
	{"ORG OG", "Orgrimmar.", "Orgrimmar."},
	{"UC", "Undercity.", "Cidade Baixa."},
	{"TB", "Thunder Bluff.", "Penhasco do Trovão.", true}, -- "tb" is "também"
	{"DARN", "Darnassus.", "Darnassus."},
	{"STV", "Stranglethorn Vale.", "Selva do Espinhaço."},
	{"BB", "Booty Bay.", "Angra do Butim.", true},
	{"XR", "The Crossroads, in the Barrens.", "A Encruzilhada, nos Sertões."},
	{"EPL", "Eastern Plaguelands.", "Terras Pestilentas Orientais."},
	{"WPL", "Western Plaguelands.", "Terras Pestilentas Ocidentais."},
}

-- Dungeons, raids and battlegrounds: {words, instance map ID, English name, kind, part}.
local PLACES = {
	{"RFC RF", 389, "Ragefire Chasm", "DUNGEON"},
	{"WC", 43, "Wailing Caverns", "DUNGEON"},
	{"VC DEADMINES", 36, "The Deadmines", "DUNGEON"},
	{"SFK", 33, "Shadowfang Keep", "DUNGEON"},
	{"BFD", 48, "Blackfathom Deeps", "DUNGEON"},
	{"STOCKS STOCKADE", 34, "The Stockade", "DUNGEON"},
	{"GNOMER", 90, "Gnomeregan", "DUNGEON"},
	{"RFK", 47, "Razorfen Kraul", "DUNGEON"},
	{"SM", 189, "Scarlet Monastery", "DUNGEON"},
	{"RFD", 129, "Razorfen Downs", "DUNGEON"},
	{"ULDA ULD", 70, "Uldaman", "DUNGEON"},
	{"ZF", 209, "Zul'Farrak", "DUNGEON"},
	{"MARA", 349, "Maraudon", "DUNGEON"},
	{"ST", 109, "Sunken Temple", "DUNGEON"},
	{"BRD", 230, "Blackrock Depths", "DUNGEON"},
	{"LBRS", 229, "Blackrock Spire", "DUNGEON", "LOWER"},
	{"UBRS", 229, "Blackrock Spire", "DUNGEON", "UPPER"},
	{"DME", 429, "Dire Maul", "DUNGEON", "EAST"},
	{"DMW", 429, "Dire Maul", "DUNGEON", "WEST"},
	{"DMN", 429, "Dire Maul", "DUNGEON", "NORTH"},
	{"STRAT STRATH", 329, "Stratholme", "DUNGEON"},
	{"SCHOLO", 289, "Scholomance", "DUNGEON"},
	{"MC", 409, "Molten Core", "RAID"},
	{"ONY", 249, "Onyxia's Lair", "RAID"},
	{"BWL", 469, "Blackwing Lair", "RAID"},
	{"ZG", 309, "Zul'Gurub", "RAID"},
	{"AQ20", 509, "Ruins of Ahn'Qiraj", "RAID"},
	{"AQ40", 531, "Temple of Ahn'Qiraj", "RAID"},
	{"NAXX", 533, "Naxxramas", "RAID"},
	{"WSG", 489, "Warsong Gulch", "BG"},
	{"AB", 529, "Arathi Basin", "BG", nil, true},
	{"AV", 30, "Alterac Valley", "BG", nil, true},
}

local lookup = {} -- word in capitals -> entry {text, exact} or place {map, name, kind, part, exact}

for _, term in ipairs(TERMS) do
	local entry = {text = PT and term[3] or term[2], exact = term[4]}
	for word in term[1]:gmatch("%S+") do
		lookup[word] = entry
	end
end
for _, place in ipairs(PLACES) do
	local entry = {map = place[2], english = place[3], kind = place[4], part = place[5], exact = place[6]}
	for word in place[1]:gmatch("%S+") do
		lookup[word] = entry
	end
end
-- "DM": the Deadmines or Dire Maul
lookup.DM = {both = {lookup.VC, {map = 429, english = "Dire Maul", kind = "DUNGEON"}}}

-- The name in the game's language, English when the game does not know the map.
local function PlaceName(entry)
	if not entry.name then
		local ok, name = pcall(GetRealZoneText, entry.map)
		entry.name = ok and type(name) == "string" and name ~= "" and name or entry.english
	end
	return entry.name
end


--[[ Marking words ]]--

local function Link(upper, word)
	return ("|c%s|Haddon:ForeverHub:term:%s|h%s|h|r"):format(COLOR, upper, word)
end

local function Word(word)
	local upper = word:upper()
	local entry = lookup[upper]
	if not entry then
		if upper:match("^LF%dM$") then return Link(upper, word) end
		return
	end
	if entry.exact and word ~= upper then return end
	return Link(upper, word)
end

-- Plain text (no links or color codes): its terms become links. Words include accented
-- letters, so parts of Portuguese words never match ("está" is one word, not "est").
function ChatTerms.Mark(text)
	return (text:gsub("[%w\128-\255]+", Word))
end


--[[ Meaning ]]--

-- Title and lines of a term, for a tooltip.
function ChatTerms:Describe(upper)
	local count = upper:match("^LF(%d)M$")
	if count then
		return upper, {L.TERM_LF_N:format(count)}
	end
	local entry = lookup[upper]
	if not entry then return end
	if entry.text then
		return upper, {entry.text}
	end
	local function Place(place)
		local name = PlaceName(place)
		if place.part then
			name = name .. " " .. L["TERM_PART_" .. place.part]
		end
		return L["TERM_KIND_" .. place.kind]:format(name)
	end
	if entry.both then
		local lines = {L.TERM_EITHER}
		for _, place in ipairs(entry.both) do
			lines[#lines + 1] = Place(place)
		end
		return upper, lines
	end
	return upper, {Place(entry)}
end

function ChatTerms:Fill(tooltip, upper)
	local title, lines = self:Describe(upper)
	if not title then return end
	tooltip:SetText(title, 1, 0.82, 0)
	for _, line in ipairs(lines) do
		tooltip:AddLine(line, 1, 1, 1, true)
	end
end

-- A click: the meaning in the game's link window, which stays until closed; a second click
-- on the same term closes it.
local shownTerm

local function ShowClicked(upper)
	local tooltip = ItemRefTooltip
	if not tooltip then return end
	if tooltip:IsShown() and shownTerm == upper then
		tooltip:Hide()
		return
	end
	if not tooltip:IsShown() then
		tooltip:SetOwner(UIParent, "ANCHOR_PRESERVE")
	end
	tooltip:ClearLines()
	ChatTerms:Fill(tooltip, upper)
	tooltip:Show()
	shownTerm = upper
end


--[[ Module ]]--

function ChatTerms:OnLogin()
	EventRegistry:RegisterCallback("SetItemRef", function(_, link)
		if type(link) ~= "string" then return end
		local upper = link:match("^addon:ForeverHub:term:(.+)$")
		if upper then
			ShowClicked(upper)
		end
	end, ChatTerms)
	-- the window closed or showing something else: the next click on a term opens it again
	if ItemRefTooltip then
		local function Forget() shownTerm = nil end
		ItemRefTooltip:HookScript("OnHide", Forget)
		for _, method in ipairs({"SetHyperlink", "ItemRefSetHyperlink"}) do
			if ItemRefTooltip[method] then hooksecurefunc(ItemRefTooltip, method, Forget) end
		end
	end
end
