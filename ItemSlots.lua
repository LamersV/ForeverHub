--[[
	Item level on each slot of the character window and of the inspect window, in
	the item's quality color, and the durability when it gets low (character only).
--]]

local _, ns = ...

local ItemSlots = ns:NewModule("ItemSlots")

local GetDetailedItemLevelInfo = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo

-- shirt, tabard and ammo have no level worth showing
local SKIP = {[0] = true, [4] = true, [19] = true}

local settings
local labels = {} -- slot button -> {Level, Durability}

local function Labels(button)
	local label = labels[button]
	if not label then
		label = {}
		label.Level = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		label.Level:SetPoint("BOTTOMRIGHT", -1, 2)
		label.Durability = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		label.Durability:SetPoint("TOPLEFT", 2, -2)
		labels[button] = label
	end
	return label
end

local function Fill(button, unit)
	local slot = button:GetID()
	if not slot or SKIP[slot] then return end
	local label = Labels(button)
	local link = settings.slotLevels and GetInventoryItemLink(unit, slot)
	local level = link and GetDetailedItemLevelInfo(link)
	if type(level) == "number" and level > 1 then
		local quality = select(3, GetItemInfo(link))
		local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
		label.Level:SetText(level)
		if color then
			label.Level:SetTextColor(color.r, color.g, color.b)
		else
			label.Level:SetTextColor(1, 1, 1)
		end
	else
		label.Level:SetText("")
	end

	local text = ""
	if settings.slotLevels and unit == "player" then
		local current, maximum = GetInventoryItemDurability(slot)
		if current and maximum and maximum > 0 then
			local percent = current / maximum * 100
			if percent < 60 then
				local r, g = 1, percent < 30 and 0.2 or 0.65
				text = ("|cff%02x%02x33%d%%|r"):format(r * 255, g * 255, math.floor(percent))
			end
		end
	end
	label.Durability:SetText(text)
end

local function UpdateCharacter()
	for _, name in ipairs({"Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs",
		"Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged"}) do
		local button = _G["Character" .. name .. "Slot"]
		if button then Fill(button, "player") end
	end
end

function ItemSlots:Refresh()
	UpdateCharacter()
end

function ItemSlots:OnInitialize()
	settings = ns.db.qol
end

function ItemSlots:OnLogin()
	if PaperDollItemSlotButton_Update then
		hooksecurefunc("PaperDollItemSlotButton_Update", function(button) Fill(button, "player") end)
	end
	ns:RegisterEvent("UPDATE_INVENTORY_DURABILITY", function()
		if CharacterFrame and CharacterFrame:IsShown() then UpdateCharacter() end
	end)

	local function HookInspect()
		if not InspectPaperDollItemSlotButton_Update then return false end
		hooksecurefunc("InspectPaperDollItemSlotButton_Update", function(button)
			local unit = InspectFrame and InspectFrame.unit
			if unit then Fill(button, unit) end
		end)
		return true
	end
	if not HookInspect() then
		local function OnLoaded(_, name)
			if name == "Blizzard_InspectUI" and HookInspect() then
				ns:UnregisterEvent("ADDON_LOADED", OnLoaded)
			end
		end
		ns:RegisterEvent("ADDON_LOADED", OnLoaded)
	end
end
