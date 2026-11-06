--[[
	Bags - tooltips
	Item counts across characters, and a taint-safe sell price line.
--]]

local _, ns = ...
local L, Data = ns.L, ns.BagData

local Tooltip = ns:NewModule("BagTooltip")

local issecretvalue = issecretvalue or function() return false end
local tonumber = tonumber
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

local function ClassColored(name, class)
	local color = class and RAID_CLASS_COLORS[class]
	return color and color:WrapTextInColorCode(name) or name
end

local function SortByName(a, b)
	return a.name < b.name
end

-- The game refreshes a hovered item's tooltip every 0.2 s: the lines of the last item are kept
-- until a character's counts change.
local cachedID, cachedVersion
local cachedLines = {} -- left, right, left, right...
local cachedTotal, cachedChars = 0, 0

local function BuildLines(itemID)
	wipe(cachedLines)
	cachedTotal, cachedChars = 0, 0
	local counts = Data:GetItemCounts(itemID)
	if not counts then return end
	table.sort(counts, SortByName)
	local parts = {}
	for _, entry in ipairs(counts) do
		wipe(parts)
		if entry.bags > 0 then parts[#parts + 1] = L.TOOLTIP_BAGS .. " " .. entry.bags end
		if entry.bank > 0 then parts[#parts + 1] = L.TOOLTIP_BANK .. " " .. entry.bank end
		if entry.equip > 0 then parts[#parts + 1] = L.TOOLTIP_EQUIPPED .. " " .. entry.equip end

		local sum = entry.bags + entry.bank + entry.equip
		cachedTotal = cachedTotal + sum
		cachedLines[#cachedLines + 1] = ClassColored(entry.name, entry.class)
		cachedLines[#cachedLines + 1] = ("%d |cffaaaaaa(%s)|r"):format(sum, table.concat(parts, ", "))
	end
	cachedChars = #counts
end

local function AddCounts(tooltip, data)
	if not ns.db.bags.tooltipCounts then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end

	local itemID = data and data.id
	if not itemID or issecretvalue(itemID) then return end
	itemID = tonumber(itemID)
	if not itemID then return end

	if itemID ~= cachedID or Data.countsVersion ~= cachedVersion then
		BuildLines(itemID)
		cachedID, cachedVersion = itemID, Data.countsVersion
	end
	if cachedChars == 0 then return end

	tooltip:AddLine(" ")
	for i = 1, #cachedLines, 2 do
		tooltip:AddDoubleLine(cachedLines[i], cachedLines[i + 1], 1, 1, 1, 1, 1, 1)
	end
	if cachedChars > 1 then
		tooltip:AddDoubleLine(L.TOTAL, cachedTotal, 1, 0.82, 0, 1, 1, 1)
	end
end

-- Blizzard draws sell prices with a money frame; doing that from addon-owned item
-- buttons spreads taint through the UI, so the line is written as plain text instead.
-- Stack size of the hovered bag item (item buttons keep it in .count), 1 otherwise.
local function StackCount(tooltip)
	local owner = tooltip:GetOwner()
	local count = owner and owner.count
	if type(count) == "number" and not issecretvalue(count) and count > 1 then
		return count
	end
	return 1
end

-- Whole stack value from the item's unit price, so the total never depends on how
-- the client filled the line.
local function StackPrice(tooltip)
	if not ns.db.tooltip.unitPrice then return end
	local count = StackCount(tooltip)
	if count <= 1 then return end
	local _, link = tooltip:GetItem()
	local unit = link and not issecretvalue(link) and select(11, GetItemInfo(link))
	if unit and unit > 0 then
		return unit * count, unit, count
	end
end

local function SellPriceLine(tooltip, line)
	if not line.price or tooltip.isShopping then return end
	if line.maxPrice and line.maxPrice >= 1 then
		tooltip:AddLine(SELL_PRICE .. ":", 1, 1, 1)
		tooltip:AddLine(("    %s: %s"):format(MINIMUM, GetMoneyString(line.price, true)), 1, 1, 1)
		tooltip:AddLine(("    %s: %s"):format(MAXIMUM, GetMoneyString(line.maxPrice, true)), 1, 1, 1)
	else
		local total, unit, count = StackPrice(tooltip)
		if total then
			tooltip:AddLine(("%s: %s  |cffaaaaaa(%s x %d)|r"):format(SELL_PRICE, GetMoneyString(total, true), GetMoneyString(unit, true), count), 1, 1, 1)
		else
			tooltip:AddLine(("%s: %s"):format(SELL_PRICE, GetMoneyString(line.price, true)), 1, 1, 1)
		end
	end
	return true
end

function Tooltip:OnLogin()
	if not Data.active or not TooltipDataProcessor then return end

	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, AddCounts)
	if Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice then
		TooltipDataProcessor.AddLinePreCall(Enum.TooltipDataLineType.SellPrice, SellPriceLine)
	end
end
