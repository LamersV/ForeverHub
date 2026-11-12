--[[
	Upgrade estimate: how much better (or worse) a piece of gear is than what is
	equipped in the same slot, as a percentage.

	Two modes:
	  stats - item stats weighted for the player's class and specialization (the
	          talent tree with the most points; an estimate: weights are rules of
	          thumb, not a simulation). The permanent enchant of an item counts too:
	          swapping out an enchanted piece loses it.
	  level - item level only
	Rings, trinkets and dual-wielded one-handers are compared with the weaker of the
	two equipped. Results are cached per link and reset when the equipment or the
	talents change.
--]]

local _, ns = ...

local Upgrade = ns:NewModule("Upgrade")

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local GetItemStats = C_Item and C_Item.GetItemStats or GetItemStats
local GetDetailedItemLevelInfo = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo

-- equip location -> inventory slots it can go to
local SLOTS = {
	INVTYPE_HEAD = {1}, INVTYPE_NECK = {2}, INVTYPE_SHOULDER = {3}, INVTYPE_CHEST = {5}, INVTYPE_ROBE = {5},
	INVTYPE_WAIST = {6}, INVTYPE_LEGS = {7}, INVTYPE_FEET = {8}, INVTYPE_WRIST = {9}, INVTYPE_HAND = {10},
	INVTYPE_FINGER = {11, 12}, INVTYPE_TRINKET = {13, 14}, INVTYPE_CLOAK = {15},
	INVTYPE_WEAPON = {16, 17}, INVTYPE_2HWEAPON = {16}, INVTYPE_WEAPONMAINHAND = {16},
	INVTYPE_WEAPONOFFHAND = {17}, INVTYPE_SHIELD = {17}, INVTYPE_HOLDABLE = {17},
	INVTYPE_RANGED = {18}, INVTYPE_RANGEDRIGHT = {18}, INVTYPE_THROWN = {18}, INVTYPE_RELIC = {18},
}
local OFF_HAND = {INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true}
local RANGED = {INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true}
local OFF_HAND_WEAPONS = {INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true}

local STAT = {
	ITEM_MOD_STRENGTH_SHORT = "STR", ITEM_MOD_AGILITY_SHORT = "AGI", ITEM_MOD_STAMINA_SHORT = "STA",
	ITEM_MOD_INTELLECT_SHORT = "INT", ITEM_MOD_SPIRIT_SHORT = "SPI",
	ITEM_MOD_ATTACK_POWER_SHORT = "AP", ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "AP",
	ITEM_MOD_SPELL_POWER_SHORT = "SP", ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "SP", ITEM_MOD_SPELL_HEALING_DONE_SHORT = "HEAL",
	ITEM_MOD_CRIT_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_MELEE_RATING_SHORT = "CRIT", ITEM_MOD_CRIT_SPELL_RATING_SHORT = "CRIT",
	ITEM_MOD_HIT_RATING_SHORT = "HIT", ITEM_MOD_HIT_MELEE_RATING_SHORT = "HIT", ITEM_MOD_HIT_SPELL_RATING_SHORT = "HIT",
	RESISTANCE0_NAME = "ARMOR", ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "DPS",
	ITEM_MOD_MANA_REGENERATION_SHORT = "MP5", ITEM_MOD_POWER_REGEN0_SHORT = "MP5",
	ITEM_MOD_DEFENSE_SKILL_RATING_SHORT = "TANK", ITEM_MOD_DODGE_RATING_SHORT = "TANK",
	ITEM_MOD_PARRY_RATING_SHORT = "TANK", ITEM_MOD_BLOCK_RATING_SHORT = "TANK", ITEM_MOD_BLOCK_VALUE_SHORT = "TANK",
}

-- Rule-of-thumb weights per class. DPS is weapon damage per second (huge for
-- melee: it drives every white hit), RDPS the same for ranged weapons.
local WEIGHTS = {
	WARRIOR = {STR = 1, AGI = 0.6, STA = 0.5, AP = 0.5, CRIT = 0.8, HIT = 0.9, ARMOR = 0.02, DPS = 7, RDPS = 1},
	PALADIN = {STR = 1, INT = 0.6, STA = 0.5, SPI = 0.2, AGI = 0.3, AP = 0.4, SP = 0.6, HEAL = 0.5, CRIT = 0.6, HIT = 0.6, ARMOR = 0.02, DPS = 5},
	HUNTER = {AGI = 1, STA = 0.5, INT = 0.3, SPI = 0.1, AP = 0.4, CRIT = 0.8, HIT = 0.9, ARMOR = 0.01, DPS = 1.5, RDPS = 7},
	ROGUE = {AGI = 1, STR = 0.5, STA = 0.4, AP = 0.5, CRIT = 0.8, HIT = 0.9, ARMOR = 0.01, DPS = 7},
	PRIEST = {INT = 1, SPI = 0.8, STA = 0.5, SP = 0.9, HEAL = 0.8, CRIT = 0.5, HIT = 0.4, ARMOR = 0.005, DPS = 0.1},
	MAGE = {INT = 1, SPI = 0.4, STA = 0.5, SP = 0.9, CRIT = 0.6, HIT = 0.7, ARMOR = 0.005, DPS = 0.1},
	WARLOCK = {INT = 0.9, SPI = 0.4, STA = 0.7, SP = 1, CRIT = 0.5, HIT = 0.7, ARMOR = 0.005, DPS = 0.1},
	SHAMAN = {INT = 0.8, STR = 0.6, AGI = 0.5, STA = 0.5, SPI = 0.4, AP = 0.3, SP = 0.7, HEAL = 0.6, CRIT = 0.6, HIT = 0.6, ARMOR = 0.01, DPS = 4},
	DRUID = {INT = 0.8, AGI = 0.6, STR = 0.6, STA = 0.5, SPI = 0.5, AP = 0.3, SP = 0.7, HEAL = 0.6, CRIT = 0.6, HIT = 0.6, ARMOR = 0.01, DPS = 1},
}
-- Specializations that want other stats than the class as a whole, by talent tree
-- (classic order). Trees left out use the class weights.
local SPEC_WEIGHTS = {
	SHAMAN = {
		[1] = {INT = 1, SP = 1, CRIT = 0.6, HIT = 0.6, STA = 0.5, SPI = 0.4, MP5 = 1, AGI = 0.05, STR = 0.05, ARMOR = 0.005, DPS = 0.1}, -- Elemental
		[2] = {STR = 1, AGI = 0.8, AP = 0.5, CRIT = 0.8, HIT = 0.9, STA = 0.5, INT = 0.3, SPI = 0.1, MP5 = 0.3, ARMOR = 0.01, DPS = 6}, -- Enhancement
		[3] = {INT = 1, HEAL = 0.9, SP = 0.6, MP5 = 1.5, SPI = 0.5, STA = 0.5, CRIT = 0.5, AGI = 0.05, STR = 0.05, ARMOR = 0.005, DPS = 0.1}, -- Restoration
	},
	DRUID = {
		[1] = {INT = 1, SP = 1, CRIT = 0.6, HIT = 0.6, SPI = 0.5, STA = 0.5, MP5 = 1, AGI = 0.05, STR = 0.05, ARMOR = 0.005, DPS = 0.1}, -- Balance
		[2] = {AGI = 1, STR = 0.9, STA = 0.7, AP = 0.5, CRIT = 0.8, HIT = 0.8, ARMOR = 0.03, TANK = 0.6, DPS = 0}, -- Feral (forms ignore the weapon)
		[3] = {INT = 1, HEAL = 0.9, SPI = 0.7, MP5 = 1.5, SP = 0.5, STA = 0.5, CRIT = 0.4, AGI = 0.05, STR = 0.05, ARMOR = 0.005, DPS = 0.1}, -- Restoration
	},
	PALADIN = {
		[1] = {INT = 1, HEAL = 0.9, SP = 0.5, CRIT = 0.6, MP5 = 1.5, SPI = 0.3, STA = 0.5, STR = 0.1, ARMOR = 0.005, DPS = 0.5}, -- Holy
		[2] = {STA = 1, ARMOR = 0.04, TANK = 0.9, STR = 0.6, AGI = 0.5, INT = 0.4, SP = 0.4, HIT = 0.5, DPS = 2}, -- Protection
		[3] = {STR = 1, AGI = 0.5, CRIT = 0.8, HIT = 0.9, AP = 0.5, STA = 0.5, INT = 0.3, ARMOR = 0.01, DPS = 7}, -- Retribution
	},
	WARRIOR = {
		[3] = {STA = 1, ARMOR = 0.04, TANK = 0.9, AGI = 0.6, STR = 0.6, HIT = 0.6, AP = 0.3, DPS = 3}, -- Protection
	},
}
-- mana regeneration, for the class weights
local MP5 = {PRIEST = 1.2, MAGE = 0.8, WARLOCK = 0.6, PALADIN = 0.8, SHAMAN = 0.8, DRUID = 0.8, HUNTER = 0.3}
for class, value in pairs(MP5) do
	WEIGHTS[class].MP5 = value
end
local DEFAULT_WEIGHTS = {STR = 0.7, AGI = 0.7, INT = 0.7, STA = 0.5, SPI = 0.3, AP = 0.4, SP = 0.6, HEAL = 0.5, CRIT = 0.6, HIT = 0.6, ARMOR = 0.01, DPS = 3}
local OTHER_STAT = 0.4 -- any other bonus (ratings the table does not know)
local TANK_STAT = 0.1 -- defense, dodge, parry, block: little worth outside a tank's table

local weights
local specName -- name of the talent tree whose weights apply, nil for the class weights
local scores, results = {}, {} -- link -> score / link -> comparison
local settings


--[[ Specialization ]]--

-- Points spent in a talent tree. GetTalentTabInfo answers (name, icon, points...) on the
-- classic client and (id, name, description, icon, points...) on later ones.
local function TreeInfo(tab)
	local ok, a, b, c, _, e = pcall(GetTalentTabInfo, tab)
	if not ok then return nil end
	if type(a) == "number" then return b, tonumber(e) or 0 end
	return a, tonumber(c) or 0
end

-- The tree with the most points (at least one), and its name.
local function PrimaryTree()
	if not (GetNumTalentTabs and GetTalentTabInfo) then return nil end
	local best, bestPoints, bestName = nil, 0, nil
	for tab = 1, GetNumTalentTabs() or 0 do
		local name, points = TreeInfo(tab)
		if points and points > bestPoints then
			best, bestPoints, bestName = tab, points, name
		end
	end
	return best, bestName
end

local function ChooseWeights()
	local class = select(2, UnitClass("player"))
	weights, specName = WEIGHTS[class] or DEFAULT_WEIGHTS, nil
	local tree, name = PrimaryTree()
	local spec = tree and SPEC_WEIGHTS[class] and SPEC_WEIGHTS[class][tree]
	if spec then weights = spec end
	if tree and type(name) == "string" then specName = name end
end

-- Name of the talent tree the estimate follows, or nil (no talents yet, or level mode).
function Upgrade:SpecName()
	if settings.upgradeMode == "level" then return nil end
	return specName
end


--[[ Enchants ]]--

-- Stat names as the game writes them, longest first ("Spell Power" before "Power").
local statNames = {}

local function BuildStatNames()
	local seen = {}
	for token, stat in pairs(STAT) do
		local name = _G[token]
		if type(name) == "string" and name ~= "" and stat ~= "DPS" and not seen[name] then
			seen[name] = true
			statNames[#statNames + 1] = {(name:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")), stat}
		end
	end
	table.sort(statNames, function(a, b) return #a[1] > #b[1] end)
end

local ENCHANT_LINE = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.ItemEnchantmentPermanent
local ENCHANT_PREFIX = type(ENCHANTED_TOOLTIP_LINE) == "string" and ENCHANTED_TOOLTIP_LINE:match("^(.-)%%s") or nil

local function StatWeight(stat)
	if stat == "TANK" then return weights.TANK or TANK_STAT end
	return weights[stat] or 0
end

-- Weighted value of the item's permanent enchant ("Enchanted: Stamina +2 and Armor +16"),
-- read from its tooltip: 0 without one, nil while the tooltip is not known yet.
local function EnchantScore(link)
	local enchant = tonumber(link:match("item:%d+:(%d*)") or "")
	if not enchant or enchant == 0 or not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then return 0 end
	local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then return nil end
	for _, line in ipairs(data.lines) do
		local text = line.leftText
		if type(text) == "string" and not (issecretvalue and issecretvalue(text))
			and ((ENCHANT_LINE and line.type == ENCHANT_LINE) or (ENCHANT_PREFIX and ENCHANT_PREFIX ~= "" and text:find(ENCHANT_PREFIX, 1, true) == 1)) then
			local score = 0
			for _, entry in ipairs(statNames) do
				local name = entry[1]
				local value = text:match(name .. "%s*%+(%d+)") or text:match("%+(%d+)%s*" .. name)
				if value then
					score = score + tonumber(value) * StatWeight(entry[2])
					text = text:gsub(name, " ", 1) -- a shorter name inside this one must not count again
				end
			end
			return score
		end
	end
	return 0
end


--[[ Scores ]]--

local function EquipLocation(link)
	local equipLoc = select(4, GetItemInfoInstant(link))
	return equipLoc ~= "" and equipLoc or nil
end

local function ItemLevel(link)
	local level = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link) or select(4, GetItemInfo(link))
	return level or 0
end

-- Weighted stat total; nil while the client has not loaded the item.
local function StatScore(link, equipLoc)
	if not GetItemInfo(link) then return nil end
	local stats = GetItemStats(link)
	if not stats then return nil end
	local score = 0
	for token, value in pairs(stats) do
		local stat = STAT[token]
		if stat == "DPS" then
			score = score + value * ((RANGED[equipLoc] and weights.RDPS) or weights.DPS or 0)
		elseif stat then
			score = score + value * StatWeight(stat)
		elseif token:find("^ITEM_MOD_") then
			score = score + value * OTHER_STAT
		end
	end
	local enchant = EnchantScore(link)
	if not enchant then return nil end
	return score + enchant
end

local function Score(link)
	local score = scores[link]
	if score == nil then
		local equipLoc = EquipLocation(link)
		if settings.upgradeMode == "level" then
			score = GetItemInfo(link) and ItemLevel(link) or nil
		else
			score = StatScore(link, equipLoc)
			-- items without stats (or not understood): fall back to their level
			if score == 0 then
				score = ItemLevel(link) * 0.1
			end
		end
		scores[link] = score
	end
	return score
end

-- Score of what is equipped in a slot: 0 when empty, nil while not loaded.
local function EquippedScore(slot)
	local link = GetInventoryItemLink("player", slot)
	if not link then return 0, nil end
	return Score(link), link
end


--[[ Comparison ]]--

local function Compute(link)
	local equipLoc = EquipLocation(link)
	local slots = equipLoc and SLOTS[equipLoc]
	if not slots then return nil end

	local new = Score(link)
	if not new then return nil end

	local mainHand = GetInventoryItemLink("player", 16)
	local mainHand2H = mainHand and EquipLocation(mainHand) == "INVTYPE_2HWEAPON"

	local current
	if equipLoc == "INVTYPE_2HWEAPON" then
		-- a two-hander replaces both hands
		local main, mainLink = EquippedScore(16)
		local off = mainHand2H and 0 or EquippedScore(17)
		if not main or not off or mainLink == link then return nil end
		current = main + off
		if settings.upgradeMode == "level" and not mainHand2H and off > 0 then
			current = current / 2
		end
	elseif OFF_HAND[equipLoc] and mainHand2H then
		return nil -- an off-hand cannot be compared with a two-hander on its own
	else
		local candidates = slots
		if equipLoc == "INVTYPE_WEAPON" then
			-- the off hand only counts for characters that dual wield one-handers there
			local offHand = GetInventoryItemLink("player", 17)
			local dualWield = CanDualWield and CanDualWield() and offHand and OFF_HAND_WEAPONS[EquipLocation(offHand) or ""]
			candidates = dualWield and slots or {16}
		end
		for _, slot in ipairs(candidates) do
			local score, equipped = EquippedScore(slot)
			if not score then return nil end
			if equipped == link then return nil end -- the same item is already equipped
			if not current or score < current then
				current = score -- replace the weaker one
			end
		end
	end

	if current <= 0 then
		return new > 0 and "new" or nil
	end
	return (new - current) / current * 100
end

-- Percentage (number), "new" for an empty slot, or nil when it does not apply.
function Upgrade:Compare(link)
	if not link then return nil end
	local result = results[link]
	if result == nil then
		result = Compute(link)
		if result ~= nil then
			results[link] = result
		end
	end
	return result
end

-- Text and color for a comparison, or nil.
function Upgrade:Format(result)
	if result == "new" then
		return "+", 0.2, 1, 0.2
	elseif type(result) == "number" then
		local percent = math.floor(result + 0.5)
		if percent > 0 then
			return ("+%d%%"):format(percent), 0.2, 1, 0.2
		elseif percent < 0 then
			return ("%d%%"):format(percent), 1, 0.35, 0.3
		end
		return "=", 0.8, 0.8, 0.8
	end
end

function Upgrade:Reset(all)
	wipe(results)
	if all then
		wipe(scores)
	end
end


--[[ Module ]]--

function Upgrade:OnInitialize()
	settings = ns.db.bags
end

local function RefreshBags()
	if ns.Bags and ns.Bags.active then
		ns:Defer("bags-upgrade", function() ns.Bags:UpdateItems() end)
	end
end

function Upgrade:OnLogin()
	ChooseWeights()
	BuildStatNames()
	ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
		Upgrade:Reset()
		RefreshBags()
	end)
	-- talents moved: another tree may lead, with other weights
	local function Talents()
		local before = weights
		ChooseWeights()
		if weights ~= before then
			Upgrade:Reset(true)
			RefreshBags()
		end
	end
	for _, event in ipairs({"CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_LEVEL_UP"}) do
		pcall(ns.RegisterEvent, ns, event, Talents)
	end
	C_Timer.After(3, Talents) -- talents may not be known yet right at login
end
