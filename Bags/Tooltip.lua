--[[
	Bags - tooltips
	Item counts across characters, and a taint-safe sell price line.
--]]

local _, ns = ...
local L, Data = ns.L, ns.BagData

local Tooltip = ns:NewModule("BagTooltip")

local issecretvalue = issecretvalue or function() return false end
local tonumber = tonumber

local function ClassColored(name, class)
	local color = class and RAID_CLASS_COLORS[class]
	return color and color:WrapTextInColorCode(name) or name
end

local function SortByName(a, b)
	return a.name < b.name
end

local function AddCounts(tooltip, data)
	if not ns.db.bags.tooltipCounts then return end
	if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end

	local itemID = data and data.id
	if not itemID or issecretvalue(itemID) then return end

	local counts = Data:GetItemCounts(tonumber(itemID))
	if not counts then return end
	table.sort(counts, SortByName)

	local total = 0
	tooltip:AddLine(" ")
	for _, entry in ipairs(counts) do
		local parts = {}
		if entry.bags > 0 then parts[#parts + 1] = L.TOOLTIP_BAGS .. " " .. entry.bags end
		if entry.bank > 0 then parts[#parts + 1] = L.TOOLTIP_BANK .. " " .. entry.bank end
		if entry.equip > 0 then parts[#parts + 1] = L.TOOLTIP_EQUIPPED .. " " .. entry.equip end

		local sum = entry.bags + entry.bank + entry.equip
		total = total + sum
		tooltip:AddDoubleLine(ClassColored(entry.name, entry.class), ("%d |cffaaaaaa(%s)|r"):format(sum, table.concat(parts, ", ")), 1, 1, 1, 1, 1, 1)
	end
	if #counts > 1 then
		tooltip:AddDoubleLine(L.TOTAL, total, 1, 0.82, 0, 1, 1, 1)
	end
end

-- Blizzard draws sell prices with a money frame; doing that from addon-owned item
-- buttons spreads taint through the UI, so the line is written as plain text instead.
local function SellPriceLine(tooltip, line)
	if not line.price or tooltip.isShopping then return end
	if line.maxPrice and line.maxPrice >= 1 then
		tooltip:AddLine(SELL_PRICE .. ":", 1, 1, 1)
		tooltip:AddLine(("    %s: %s"):format(MINIMUM, GetMoneyString(line.price, true)), 1, 1, 1)
		tooltip:AddLine(("    %s: %s"):format(MAXIMUM, GetMoneyString(line.maxPrice, true)), 1, 1, 1)
	else
		tooltip:AddLine(("%s: %s"):format(SELL_PRICE, GetMoneyString(line.price, true)), 1, 1, 1)
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
