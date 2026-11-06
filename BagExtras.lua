--[[
	In the bag window's footer:
	  - a button that opens the next container in the bags (clams, boxes, sacks...),
	    one per click, with how many are left;
	  - ammo (the equipped kind) and soul shards, with a warning when they run low.
--]]

local _, ns = ...
local L = ns.L

local BagExtras = ns:NewModule("BagExtras")

local SOUL_SHARD = 6265
local GetItemCount = C_Item and C_Item.GetItemCount or GetItemCount
local GetItemIcon = C_Item and C_Item.GetItemIconByID or GetItemIcon

local settings
local frame, openButton, counter
local openable = {} -- {bag, slot} of each container that can be opened
local warned = {}


--[[ Containers ]]--

local function IsLocked(bag, slot)
	if not (C_TooltipInfo and C_TooltipInfo.GetBagItem) then return false end
	local data = C_TooltipInfo.GetBagItem(bag, slot)
	for _, line in ipairs(data and data.lines or {}) do
		if line.leftText == LOCKED then return true end
	end
	return false
end

local function Scan()
	wipe(openable)
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.hasLoot and not IsLocked(bag, slot) then
				openable[#openable + 1] = {bag, slot, info.iconFileID}
			end
		end
	end
end

local function UpdateOpen()
	if not openButton then return end
	local first = openable[1]
	if settings.openBoxes and first then
		openButton:SetNormalTexture(first[3])
		openButton:SetPushedTexture(first[3])
		openButton:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
		openButton.Count:SetText(#openable > 1 and #openable or "")
		openButton:Show()
	else
		openButton:Hide()
	end
end

local function OpenNext()
	if InCombatLockdown() then return end
	local first = openable[1]
	if first then
		C_Container.UseContainerItem(first[1], first[2])
	end
end


--[[ Ammo and shards ]]--

local function Ammo()
	local ok, itemID = pcall(GetInventoryItemID, "player", 0)
	if not ok or not itemID then return end
	return itemID, GetInventoryItemCount("player", 0) or 0
end

local function Warn(key, low, text)
	if low and not warned[key] then
		warned[key] = true
		UIErrorsFrame:AddMessage(text, 1, 0.5, 0.2)
		ns:Print(text)
	elseif not low then
		warned[key] = nil
	end
end

local function UpdateCounter()
	if not settings.ammo then
		if counter then counter:Hide() end
		return
	end
	local parts = {}
	local ammoID, ammo = Ammo()
	if ammoID then
		parts[#parts + 1] = ("|T%s:14|t %d"):format(GetItemIcon(ammoID) or "", ammo)
		Warn("ammo", ammo < settings.ammoLow, L.AMMO_LOW:format(ammo))
	end
	if select(2, UnitClass("player")) == "WARLOCK" then
		local shards = GetItemCount(SOUL_SHARD) or 0
		parts[#parts + 1] = ("|T%s:14|t %d"):format(GetItemIcon(SOUL_SHARD) or "", shards)
		Warn("shards", shards < 3, L.SHARDS_LOW:format(shards))
	end
	if counter then
		counter:SetText(table.concat(parts, "   "))
		counter:SetShown(#parts > 0)
	end
end


--[[ Bag window ]]--

local function Attach()
	if frame then return end
	frame = ns.Bags and ns.Bags.frames and ns.Bags.frames.inventory
	if not frame then return end

	openButton = ns.Widgets.CreateIconButton(frame, "Interface\\Icons\\INV_Misc_Bag_10", 20)
	openButton:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -150, 7)
	openButton.Count = openButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	openButton.Count:SetPoint("BOTTOMRIGHT", -1, 1)
	openButton:SetScript("OnClick", OpenNext)
	ns.Widgets.AttachTooltip(openButton, L.OPEN_BOXES_TIP, L.OPEN_BOXES)

	counter = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	counter:SetPoint("RIGHT", openButton, "LEFT", -10, 0)

	UpdateOpen()
	UpdateCounter()
end

local function Update()
	Scan()
	Attach()
	UpdateOpen()
	UpdateCounter()
end

function BagExtras:Refresh()
	Update()
end

function BagExtras:OnInitialize()
	settings = ns.db.qol
end

function BagExtras:OnLogin()
	local function Later() ns:Defer("bag-extras", Update) end
	ns:RegisterEvent("BAG_UPDATE_DELAYED", Later)
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", Later)
	ns:RegisterEvent("UNIT_INVENTORY_CHANGED", function(_, unit)
		if unit == "player" then Later() end
	end)
	if ns.Bags then
		for _, method in ipairs({"Show", "Toggle"}) do
			if ns.Bags[method] then hooksecurefunc(ns.Bags, method, Later) end
		end
	end
end
