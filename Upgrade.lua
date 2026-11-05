--[[
	Upgrade estimate: how much better (or worse) a piece of gear is than what is
	equipped in the same slot, as a percentage.

	Two modes:
	  stats - item stats weighted for the player's class (an estimate: weights are
	          general rules of thumb, not a simulation)
	  level - item level only
	Rings, trinkets and dual-wielded one-handers are compared with the weaker of the
	two equipped. Results are cached per link and reset when the equipment changes.
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
local DEFAULT_WEIGHTS = {STR = 0.7, AGI = 0.7, INT = 0.7, STA = 0.5, SPI = 0.3, AP = 0.4, SP = 0.6, HEAL = 0.5, CRIT = 0.6, HIT = 0.6, ARMOR = 0.01, DPS = 3}
local OTHER_STAT = 0.4 -- any other bonus (ratings the table does not know)

local weights
local scores, results = {}, {} -- link -> score / link -> comparison
local settings


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
			score = score + value * (weights[stat] or 0)
		elseif token:find("^ITEM_MOD_") then
			score = score + value * OTHER_STAT
		end
	end
	return score
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

function Upgrade:OnLogin()
	weights = WEIGHTS[select(2, UnitClass("player"))] or DEFAULT_WEIGHTS
	ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
		Upgrade:Reset()
		if ns.Bags and ns.Bags.active then
			ns:Defer("bags-upgrade", function() ns.Bags:UpdateItems() end)
		end
	end)
end
