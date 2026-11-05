--[[
	Automation (Leatrix Plus-style)

	Faster loot: with auto loot on, every slot is taken at once on LOOT_READY
	instead of one per frame by the default UI.

	Loot limit: the server never splits a loot stack. With 29 of an item that is
	"Unique (30)", a stack of 2 cannot be taken at all (and destroying one from the
	bags is no way out: for quest items it can drop the whole quest stack). The chat
	then explains why the item stays, and faster loot skips that slot.

	Resurrection: accepted on its own, unless the caster is in combat (a battle
	res, usually better declined in a fight) or in Zul'Gurub, where the Chained
	Spirit offers a resurrection that also moves you.

	Errors: the red "Not enough rage" / "Out of range" spam is hidden; the ones that
	matter (bags full, unique limit, quest log full, not enough money) still show.

	Each one stays off while Leatrix Plus has the same option on.
--]]

local _, ns = ...
local L = ns.L

local Automation = ns:NewModule("Automation")

local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local issecretvalue = issecretvalue or function() return false end
local ITEM_SLOT = Enum.LootSlotType and Enum.LootSlotType.Item or 1
local ZULGURUB = 309

local settings


--[[ Loot limit ]]--

-- "Unique (%d)" as a Lua pattern
local UNIQUE_MULTIPLE = ITEM_UNIQUE_MULTIPLE and "^" .. ITEM_UNIQUE_MULTIPLE
	:gsub("[%(%)%.%-%+%*%?%[%]%^%$]", "%%%0"):gsub("%%d", "(%%d+)") .. "$"

-- The most of this item a character can carry, from the loot tooltip; nil when unlimited.
local function UniqueLimit(slot)
	local data = C_TooltipInfo and C_TooltipInfo.GetLootItem and C_TooltipInfo.GetLootItem(slot)
	if not data or not data.lines then return end
	for _, line in ipairs(data.lines) do
		local text = line.leftText
		if text and not issecretvalue(text) then
			if text == ITEM_UNIQUE then
				return 1
			end
			local limit = UNIQUE_MULTIPLE and text:match(UNIQUE_MULTIPLE)
			if limit then
				return tonumber(limit)
			end
		end
	end
end

-- How many of the stack in this slot would go over the limit (0 when it fits).
local function Excess(slot)
	if GetLootSlotType(slot) ~= ITEM_SLOT then return 0 end
	local link = GetLootSlotLink(slot)
	local quantity = select(3, GetLootSlotInfo(slot)) or 1
	local limit = link and UniqueLimit(slot)
	if not limit then return 0 end
	local have = GetItemCount(link, true) -- the limit counts the bank too
	local excess = have + quantity - limit
	-- already at the limit: nothing to do but leave it, the game says so itself
	if excess > 0 and have < limit then
		return excess, link, have, limit, quantity
	end
	return 0
end

local warned = {} -- slot -> true for the loot window that is open

local function CheckLimits()
	local blocked = {}
	for slot = 1, GetNumLootItems() do
		local ok, excess, link, have, limit, quantity = pcall(Excess, slot)
		if ok and excess > 0 then
			blocked[slot] = true
			if settings.lootLimit and not warned[slot] then
				warned[slot] = true
				ns:Print(L.LOOT_LIMIT:format(link, have, limit, quantity, excess))
			end
		end
	end
	return blocked
end


--[[ Faster loot ]]--

local lastLoot = 0

local function OnLootReady()
	local blocked = CheckLimits()
	if not settings.fasterLoot or ns:LeatrixHas("FasterLooting") then return end
	-- same rule as the default UI: auto loot unless the toggle key inverts it
	if GetCVarBool("autoLootDefault") == IsModifiedClick("AUTOLOOTTOGGLE") then return end
	-- LOOT_READY can fire twice for one corpse
	local now = GetTime()
	if now - lastLoot < 0.3 then return end
	lastLoot = now
	for slot = GetNumLootItems(), 1, -1 do
		local locked = select(6, GetLootSlotInfo(slot))
		if not blocked[slot] and not locked then
			LootSlot(slot)
		end
	end
end


--[[ Resurrection ]]--

local function OnResurrectRequest(_, caster)
	if not settings.autoRes or ns:LeatrixHas("AutoAcceptRes") then return end
	if select(8, GetInstanceInfo()) == ZULGURUB then return end
	if caster and not issecretvalue(caster) then
		local ok, inCombat = pcall(UnitAffectingCombat, caster)
		if ok and inCombat then return end
	end
	AcceptResurrect()
	StaticPopup_Hide("RESURRECT")
	StaticPopup_Hide("RESURRECT_NO_SICKNESS")
	StaticPopup_Hide("RESURRECT_NO_TIMER")
end


--[[ Errors ]]--

local keep = {}
for _, key in ipairs({"ERR_INV_FULL", "ERR_BAG_FULL", "ERR_ITEM_MAX_COUNT", "ERR_QUEST_LOG_FULL",
	"ERR_NOT_ENOUGH_MONEY", "ERR_ITEM_UNIQUE_EQUIPPABLE", "ERR_LOOT_GONE"}) do
	if _G[key] then
		keep[_G[key]] = true
	end
end

local function OnErrorMessage(_, _, message)
	if message and (issecretvalue(message) or keep[message]) then
		UIErrorsFrame:AddMessage(message, 1, 0.1, 0.1, 1)
	end
end

local hiding = false

function Automation:RefreshErrors()
	local hide = settings.hideErrors and not ns:LeatrixHas("HideErrorMessages")
	if hide == hiding or not UIErrorsFrame then return end
	hiding = hide
	if hide then
		UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
		ns:RegisterEvent("UI_ERROR_MESSAGE", OnErrorMessage)
	else
		ns:UnregisterEvent("UI_ERROR_MESSAGE", OnErrorMessage)
		UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
	end
end


--[[ Module ]]--

function Automation:OnInitialize()
	settings = ns.db.automation
end

function Automation:OnLogin()
	ns:RegisterEvent("LOOT_READY", OnLootReady)
	ns:RegisterEvent("LOOT_CLOSED", function() wipe(warned) end)
	ns:RegisterEvent("RESURRECT_REQUEST", OnResurrectRequest)
	self:RefreshErrors()
end
