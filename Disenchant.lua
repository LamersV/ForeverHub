--[[
	Disenchanting on tooltips (DisenchantBuddy-style)

	Armor and weapons: what disenchanting gives, with chance and amount.
	Enchanting materials: the item level ranges that give them.
	Bags: IsWorth() tells which items are worth disenchanting (see there).

	Only classic content: materials and item levels of the original game (up to the
	level 92 raid epics). Tables by quality: {highest item level, results...}, each
	result {material, chance %, min, max}. Called from Tooltips.lua so the lines sit
	between the upgrade line and the IDs.
--]]

local _, ns = ...
local L = ns.L

local Disenchant = ns:NewModule("Disenchant")

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local issecretvalue = issecretvalue or function() return false end

local WEAPON, ARMOR = Enum.ItemClass.Weapon, Enum.ItemClass.Armor
local UNCOMMON, RARE, EPIC, LEGENDARY = 2, 3, 4, 5

local M = {
	STRANGE_DUST = 10940, SOUL_DUST = 11083, VISION_DUST = 11137, DREAM_DUST = 11176, ILLUSION_DUST = 16204,
	LESSER_MAGIC = 10938, GREATER_MAGIC = 10939,
	LESSER_ASTRAL = 10998, GREATER_ASTRAL = 11082,
	LESSER_MYSTIC = 11134, GREATER_MYSTIC = 11135,
	LESSER_NETHER = 11174, GREATER_NETHER = 11175,
	LESSER_ETERNAL = 16202, GREATER_ETERNAL = 16203,
	SMALL_GLIMMERING = 10978, LARGE_GLIMMERING = 11084,
	SMALL_GLOWING = 11138, LARGE_GLOWING = 11139,
	SMALL_RADIANT = 11177, LARGE_RADIANT = 11178,
	SMALL_BRILLIANT = 14343, LARGE_BRILLIANT = 14344,
	NEXUS = 20725,
}

local ARMOR_UNCOMMON = {
	{15, {M.STRANGE_DUST, 80, 1, 2}, {M.LESSER_MAGIC, 20, 1, 2}},
	{20, {M.STRANGE_DUST, 75, 2, 3}, {M.GREATER_MAGIC, 20, 1, 2}, {M.SMALL_GLIMMERING, 5, 1, 1}},
	{25, {M.STRANGE_DUST, 75, 4, 6}, {M.LESSER_ASTRAL, 15, 1, 2}, {M.SMALL_GLIMMERING, 10, 1, 1}},
	{30, {M.SOUL_DUST, 75, 1, 2}, {M.GREATER_ASTRAL, 20, 1, 2}, {M.LARGE_GLIMMERING, 5, 1, 1}},
	{35, {M.SOUL_DUST, 75, 2, 5}, {M.LESSER_MYSTIC, 20, 1, 2}, {M.SMALL_GLOWING, 5, 1, 1}},
	{40, {M.VISION_DUST, 75, 1, 2}, {M.GREATER_MYSTIC, 20, 1, 2}, {M.LARGE_GLOWING, 5, 1, 1}},
	{45, {M.VISION_DUST, 75, 2, 5}, {M.LESSER_NETHER, 20, 1, 2}, {M.SMALL_RADIANT, 5, 1, 1}},
	{50, {M.DREAM_DUST, 75, 1, 2}, {M.GREATER_NETHER, 20, 1, 2}, {M.LARGE_RADIANT, 5, 1, 1}},
	{55, {M.DREAM_DUST, 75, 2, 6}, {M.LESSER_ETERNAL, 20, 1, 2}, {M.SMALL_BRILLIANT, 5, 1, 1}},
	{60, {M.ILLUSION_DUST, 75, 1, 2}, {M.GREATER_ETERNAL, 20, 1, 2}, {M.LARGE_BRILLIANT, 5, 1, 1}},
	{65, {M.ILLUSION_DUST, 75, 2, 5}, {M.GREATER_ETERNAL, 20, 2, 3}, {M.LARGE_BRILLIANT, 5, 1, 1}},
}

local WEAPON_UNCOMMON = {
	{15, {M.LESSER_MAGIC, 80, 1, 2}, {M.STRANGE_DUST, 20, 1, 2}},
	{20, {M.GREATER_MAGIC, 75, 1, 2}, {M.STRANGE_DUST, 20, 2, 3}, {M.SMALL_GLIMMERING, 5, 1, 1}},
	{25, {M.GREATER_MAGIC, 75, 1, 2}, {M.STRANGE_DUST, 15, 4, 6}, {M.SMALL_GLIMMERING, 10, 1, 1}},
	{30, {M.GREATER_MAGIC, 75, 1, 2}, {M.SOUL_DUST, 20, 1, 2}, {M.LARGE_GLIMMERING, 5, 1, 1}},
	{35, {M.LESSER_MYSTIC, 75, 1, 2}, {M.SOUL_DUST, 20, 2, 5}, {M.SMALL_GLOWING, 5, 1, 1}},
	{40, {M.GREATER_MYSTIC, 75, 1, 2}, {M.VISION_DUST, 20, 1, 2}, {M.LARGE_GLOWING, 5, 1, 1}},
	{45, {M.LESSER_NETHER, 75, 1, 2}, {M.VISION_DUST, 20, 2, 5}, {M.SMALL_RADIANT, 5, 1, 1}},
	{50, {M.GREATER_NETHER, 75, 1, 2}, {M.DREAM_DUST, 20, 1, 2}, {M.LARGE_RADIANT, 5, 1, 1}},
	{55, {M.LESSER_ETERNAL, 75, 1, 2}, {M.DREAM_DUST, 20, 2, 5}, {M.SMALL_BRILLIANT, 5, 1, 1}},
	{60, {M.GREATER_ETERNAL, 75, 1, 2}, {M.ILLUSION_DUST, 20, 1, 2}, {M.LARGE_BRILLIANT, 5, 1, 1}},
	{65, {M.GREATER_ETERNAL, 75, 2, 3}, {M.ILLUSION_DUST, 20, 2, 5}, {M.LARGE_BRILLIANT, 5, 1, 1}},
}

local RARE_ANY = {
	{25, {M.SMALL_GLIMMERING, 100, 1, 1}},
	{30, {M.LARGE_GLIMMERING, 100, 1, 1}},
	{35, {M.SMALL_GLOWING, 100, 1, 1}},
	{40, {M.LARGE_GLOWING, 100, 1, 1}},
	{45, {M.SMALL_RADIANT, 100, 1, 1}},
	{50, {M.LARGE_RADIANT, 100, 1, 1}},
	{55, {M.SMALL_BRILLIANT, 100, 1, 1}},
	{86, {M.LARGE_BRILLIANT, 99.5, 1, 1}, {M.NEXUS, 0.5, 1, 1}},
}

local EPIC_ANY = {
	{45, {M.SMALL_RADIANT, 100, 2, 4}},
	{50, {M.LARGE_RADIANT, 100, 2, 4}},
	{55, {M.SMALL_BRILLIANT, 100, 2, 4}},
	{60, {M.NEXUS, 100, 1, 1}},
	{92, {M.NEXUS, 100, 1, 2}}, -- 1 crystal a third of the time, 2 otherwise
}

-- Crafted wands and a few quest rewards cannot be disenchanted.
local BLOCKED = {
	[11287] = true, [11288] = true, [11289] = true, [11290] = true, -- magic and mystic wands
	[20406] = true, [20407] = true, [20408] = true, -- Twilight Cultist set
}

local function Table(quality, classID)
	if quality == UNCOMMON then
		return classID == WEAPON and WEAPON_UNCOMMON or ARMOR_UNCOMMON
	elseif quality == RARE then
		return RARE_ANY
	elseif quality == EPIC then
		return EPIC_ANY
	end
end

local function Row(rows, itemLevel)
	for i = 1, #rows do
		if itemLevel <= rows[i][1] then
			return rows[i]
		end
	end
end

-- Enchanting skill needed, by item level (classic values, the same for every quality).
local SKILL = {{20, 1}, {25, 25}, {30, 50}, {35, 75}, {40, 100}, {45, 125}, {50, 150}, {55, 175}, {60, 200}}

local function RequiredSkill(itemLevel)
	for _, entry in ipairs(SKILL) do
		if itemLevel <= entry[1] then
			return entry[2]
		end
	end
	return 225
end

-- The results row for an item, or nil when it cannot be disenchanted.
-- Second value: true when the item is known not to be disenchantable.
local function Lookup(link, id)
	local _, _, quality, itemLevel, _, _, _, _, _, _, _, classID = GetItemInfo(link)
	if classID ~= WEAPON and classID ~= ARMOR or not quality or quality < UNCOMMON then return end
	if quality >= LEGENDARY or BLOCKED[id] then
		return nil, true
	end
	local rows = Table(quality, classID)
	local row = rows and itemLevel and Row(rows, itemLevel)
	return row, nil, itemLevel
end


--[[ Enchanting skill ]]--

local DISENCHANT_SPELL, ENCHANTING_LINE = 13262, 333
local skillCache -- false: not an enchanter; number: skill; true: enchanter, skill unknown

local function EnchantingSkill()
	if skillCache ~= nil then return skillCache end
	skillCache = false
	if not (IsPlayerSpell and IsPlayerSpell(DISENCHANT_SPELL)) then return skillCache end
	skillCache = true
	if GetProfessions and GetProfessionInfo then
		for i = 1, 5 do
			local index = select(i, GetProfessions())
			if index then
				local _, _, rank, _, _, _, skillLine = GetProfessionInfo(index)
				if skillLine == ENCHANTING_LINE then
					skillCache = rank
					break
				end
			end
		end
	end
	return skillCache
end

-- Whether this character can disenchant the item: nil when it is not an enchanter.
local function CanDisenchant(itemLevel)
	local skill = EnchantingSkill()
	if not skill then return nil end
	return skill == true or skill >= RequiredSkill(itemLevel)
end

-- material -> {[quality] = {min item level, max item level}}, built once from the tables
local sources = {}

local function AddSources(rows, quality)
	local low = 1
	for _, row in ipairs(rows) do
		for i = 2, #row do
			local id = row[i][1]
			sources[id] = sources[id] or {}
			local range = sources[id][quality]
			if range then
				range[1], range[2] = math.min(range[1], low), math.max(range[2], row[1])
			else
				sources[id][quality] = {low, row[1]}
			end
		end
		low = row[1] + 1
	end
end
AddSources(ARMOR_UNCOMMON, UNCOMMON)
AddSources(WEAPON_UNCOMMON, UNCOMMON)
AddSources(RARE_ANY, RARE)
AddSources(EPIC_ANY, EPIC)


--[[ Tooltip lines ]]--

local function QualityHex(quality)
	local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
	return color and color.hex or "|cffffffff"
end

local function MaterialText(id)
	local name, _, quality = GetItemInfo(id)
	local icon = select(5, GetItemInfoInstant(id))
	if not name then
		C_Item.RequestLoadItemDataByID(id)
		name = "…"
	end
	return ("  |T%s:0|t %s%s|r"):format(icon or 134400, QualityHex(quality), name)
end

local function Amount(result)
	local chance, low, high = result[2], result[3], result[4]
	local amount = low == high and low or (low .. "-" .. high)
	return ("%s%% (%sx)"):format(chance, amount)
end

local function AddResults(tooltip, row, itemLevel)
	tooltip:AddLine(L.DE_RESULTS, 1, 0.82, 0)
	for i = 2, #row do
		tooltip:AddDoubleLine(MaterialText(row[i][1]), Amount(row[i]), 1, 1, 1, 1, 1, 1)
	end
	-- green: this character can do it; red: skill too low; gray: not an enchanter
	local can = CanDisenchant(itemLevel)
	local r, g, b = 0.6, 0.6, 0.6
	if can == true then
		r, g, b = 0.2, 1, 0.2
	elseif can == false then
		r, g, b = 1, 0.3, 0.3
	end
	tooltip:AddLine(L.DE_SKILL:format(RequiredSkill(itemLevel)), r, g, b)
end

local function AddSourceLines(tooltip, ranges)
	tooltip:AddLine(L.DE_FROM, 1, 0.82, 0)
	for quality = UNCOMMON, EPIC do
		local range = ranges[quality]
		if range then
			tooltip:AddDoubleLine(("  %s%s|r"):format(QualityHex(quality), L.DE_ITEM_LEVEL),
				range[1] .. "-" .. range[2], 1, 1, 1, 1, 1, 1)
		end
	end
end

local function ModifierDown(modifier)
	if modifier == "SHIFT" then
		return IsShiftKeyDown()
	elseif modifier == "CTRL" then
		return IsControlKeyDown()
	elseif modifier == "ALT" then
		return IsAltKeyDown()
	end
	return true
end

function Disenchant:AddTooltip(tooltip, link)
	if self.disabled or not ns.db.tooltip.disenchant then return end
	if not link or issecretvalue(link) or not ModifierDown(ns.db.tooltip.disenchantModifier) then return end

	local id = tonumber(link:match("item:(%d+)"))
	if not id then return end

	if sources[id] then
		return AddSourceLines(tooltip, sources[id])
	end

	local row, blocked, itemLevel = Lookup(link, id)
	if blocked then
		tooltip:AddLine(ITEM_DISENCHANT_NOT_DISENCHANTABLE or L.DE_NOT_POSSIBLE, 0.6, 0.6, 0.6)
	elseif row then
		AddResults(tooltip, row, itemLevel)
	end
end

--[[
	Worth disenchanting, for the bag marker: the item can be disenchanted, this
	character has the skill (or the "even without Enchanting" option is on, for
	alts that send gear to an enchanter), and it is not an upgrade over what is
	equipped. Items the character cannot use are never upgrades.
--]]
function Disenchant:IsWorth(link, unusable)
	local settings = ns.db.bags
	if not settings.disenchantMark or not link or issecretvalue(link) then return false end
	local id = tonumber(link:match("item:(%d+)"))
	local row, _, itemLevel = Lookup(link, id)
	if not row then return false end

	local can = CanDisenchant(itemLevel)
	if can == false or (can == nil and not settings.disenchantMarkAlways) then return false end

	if not unusable and ns.Upgrade then
		local result = ns.Upgrade:Compare(link)
		if result == "new" or (type(result) == "number" and result > 0.5) then return false end
	end
	return true
end


--[[ Module ]]--

function Disenchant:OnLogin()
	-- a new rank or learning Enchanting changes what can be disenchanted
	for _, event in ipairs({"SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED"}) do
		pcall(ns.RegisterEvent, ns, event, function() skillCache = nil end)
	end
	-- the original addon would add the same tooltip lines a second time (the bag marker stays)
	if C_AddOns.IsAddOnLoaded("DisenchantBuddy") then
		self.disabled = true
		return
	end
	-- cache the material names so the first tooltip already shows them
	for _, id in pairs(M) do
		C_Item.RequestLoadItemDataByID(id)
	end
end
