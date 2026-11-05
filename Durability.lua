--[[
	Durability: percentage on the character window's item slots, and a warning
	when any equipped item drops to the threshold (once per drop, again after a repair).
--]]

local _, ns = ...
local L = ns.L

local Durability = ns:NewModule("Durability")

local SLOTS = {"HeadSlot", "ShoulderSlot", "ChestSlot", "WaistSlot", "LegsSlot", "FeetSlot", "WristSlot",
	"HandsSlot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot"}

local slotIDs = {} -- slot name -> inventory slot id (only slots this client has)
local labels = {} -- slot name -> font string on the character window
local settings
local warned = false

local function Percent(slotID)
	local current, maximum = GetInventoryItemDurability(slotID)
	if current and maximum and maximum > 0 then
		return current / maximum * 100
	end
end

local function Color(percent)
	if percent > 50 then
		return 0.2, 1, 0.2
	elseif percent > settings.threshold then
		return 1, 0.82, 0
	end
	return 1, 0.25, 0.2
end

local function UpdateLabels()
	if not (CharacterFrame and CharacterFrame:IsShown()) then return end
	for name, slotID in pairs(slotIDs) do
		local button = _G["Character" .. name]
		local percent = settings.show and Percent(slotID)
		local label = labels[name]
		if percent and percent < 100 and button then
			if not label then
				label = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
				label:SetPoint("BOTTOM", 0, 2)
				labels[name] = label
			end
			label:SetFormattedText("%d%%", math.floor(percent))
			label:SetTextColor(Color(percent))
			label:Show()
		elseif label then
			label:Hide()
		end
	end
end

local function CheckWarning()
	if not settings.warn then return end
	local lowest
	for _, slotID in pairs(slotIDs) do
		local percent = Percent(slotID)
		if percent and (not lowest or percent < lowest) then
			lowest = percent
		end
	end
	if lowest and lowest <= settings.threshold then
		if not warned then
			warned = true
			local text = L.DURABILITY_LOW:format(math.floor(lowest))
			ns:Print("|cffff6040" .. text .. "|r")
			if UIErrorsFrame then
				UIErrorsFrame:AddMessage(text, 1, 0.35, 0.2)
			end
		end
	else
		warned = false
	end
end

function Durability:Refresh()
	UpdateLabels()
	CheckWarning()
end

function Durability:OnInitialize()
	settings = ns.db.durability
end

function Durability:OnLogin()
	for _, name in ipairs(SLOTS) do
		local ok, slotID = pcall(GetInventorySlotInfo, name)
		if ok and slotID then
			slotIDs[name] = slotID
		end
	end

	ns:RegisterEvent("UPDATE_INVENTORY_DURABILITY", function() ns:Defer("durability", function() Durability:Refresh() end) end)
	ns:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function() ns:Defer("durability", function() Durability:Refresh() end) end)
	if CharacterFrame then
		CharacterFrame:HookScript("OnShow", UpdateLabels)
	end
	CheckWarning()
end
