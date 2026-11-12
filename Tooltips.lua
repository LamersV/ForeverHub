--[[
	Tooltip extras: item level of gear, upgrade %, disenchant results (Disenchant.lua),
	item and spell IDs, and the target of the unit under the mouse.
	Unit data can be a "secret" value in this client (combat, instances); those
	are never compared or colored, and the whole unit addition is protected.
--]]

local _, ns = ...
local L = ns.L

local Tooltips = ns:NewModule("Tooltips")

local issecretvalue = issecretvalue or function() return false end
local settings

local function IsMainTooltip(tooltip)
	return tooltip == GameTooltip or tooltip == ItemRefTooltip
end

local function AddID(tooltip, label, id)
	if not settings.ids or not IsMainTooltip(tooltip) or id == nil or issecretvalue(id) then return end
	tooltip:AddDoubleLine(label, tostring(id), 0.55, 0.55, 0.55, 0.8, 0.8, 0.8)
end

-- Item level of gear (classic tooltips do not show it). Every item has one, but on bags,
-- shirts, tabards and ammo it means nothing, and level 1 is starting or joke gear.
local GetDetailedItemLevelInfo = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local NO_LEVEL = {
	INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_TABARD = true, INVTYPE_BODY = true,
	INVTYPE_AMMO = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true,
}
local LEVEL_PREFIX = type(ITEM_LEVEL) == "string" and ITEM_LEVEL:match("^(.-)%%d") or nil

local function AddItemLevel(tooltip, data)
	if not settings.itemLevel or not IsMainTooltip(tooltip) then return end
	local _, link = tooltip:GetItem()
	if not link or issecretvalue(link) then return end
	local equipLoc = select(4, GetItemInfoInstant(link))
	if not equipLoc or equipLoc == "" or NO_LEVEL[equipLoc] then return end
	local level = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)
	if not level or level <= 1 then return end
	-- the game may already write it
	if LEVEL_PREFIX and LEVEL_PREFIX ~= "" and data and type(data.lines) == "table" then
		for _, line in ipairs(data.lines) do
			local text = line.leftText
			if type(text) == "string" and not issecretvalue(text) and text:find(LEVEL_PREFIX, 1, true) == 1 then return end
		end
	end
	tooltip:AddDoubleLine(L.TIP_ITEM_LEVEL, tostring(level), 1, 0.82, 0, 1, 1, 1)
end

-- How the item compares with what is equipped in the same slot, and the talent tree the
-- estimate follows.
local function AddUpgrade(tooltip)
	if not ns.db.bags.upgrade or not IsMainTooltip(tooltip) or not ns.Upgrade then return end
	local _, link = tooltip:GetItem()
	if not link or issecretvalue(link) then return end
	local text, r, g, b = ns.Upgrade:Format(ns.Upgrade:Compare(link))
	if text then
		if text == "+" then
			text = L.UPGRADE_EMPTY_SLOT
		end
		local spec = ns.Upgrade:SpecName()
		tooltip:AddDoubleLine(spec and L.UPGRADE_TIP_SPEC:format(spec) or L.UPGRADE_TIP, text, 1, 0.82, 0, r, g, b)
	end
end

local function AddDisenchant(tooltip)
	if not IsMainTooltip(tooltip) or not ns.Disenchant then return end
	local _, link = tooltip:GetItem()
	ns.Disenchant:AddTooltip(tooltip, link)
end

local function OnItem(tooltip, data)
	AddItemLevel(tooltip, data)
	AddUpgrade(tooltip)
	AddDisenchant(tooltip)
	AddID(tooltip, L.TIP_ITEM_ID, data and data.id)
end

local function OnSpell(tooltip, data)
	AddID(tooltip, L.TIP_SPELL_ID, data and data.id)
end

local function AddTargetLine(tooltip)
	local _, unit = tooltip:GetUnit()
	if not unit or issecretvalue(unit) then return end
	local target = unit .. "target"
	if not UnitExists(target) then return end

	local text
	if UnitIsUnit(target, "player") then
		text = "|cffff4040" .. L.TIP_YOU .. "|r"
	else
		local name = UnitName(target)
		if not name or issecretvalue(name) then return end
		local _, class = UnitClass(target)
		local color = UnitIsPlayer(target) and class and not issecretvalue(class) and RAID_CLASS_COLORS[class]
		text = color and color:WrapTextInColorCode(name) or name
	end
	tooltip:AddLine(L.TIP_TARGET:format(text), 1, 0.82, 0)
end

local function OnUnit(tooltip)
	if settings.targetOfTarget and IsMainTooltip(tooltip) then
		pcall(AddTargetLine, tooltip) -- secret values raise errors when tested; then the line is skipped
	end
end

function Tooltips:OnInitialize()
	settings = ns.db.tooltip
end

function Tooltips:OnLogin()
	if not (TooltipDataProcessor and Enum.TooltipDataType) then return end
	local types = Enum.TooltipDataType
	TooltipDataProcessor.AddTooltipPostCall(types.Item, OnItem)
	TooltipDataProcessor.AddTooltipPostCall(types.Spell, OnSpell)
	if types.UnitAura then
		TooltipDataProcessor.AddTooltipPostCall(types.UnitAura, OnSpell)
	end
	TooltipDataProcessor.AddTooltipPostCall(types.Unit, OnUnit)
end
