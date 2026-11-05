--[[
	Bags - item buttons
	Two pools:
	  live   - Blizzard's ContainerFrameItemButtonTemplate, parented to a frame whose ID
	           is the bag, so clicks/drags/use run through Blizzard's own code.
	  cached - plain item buttons for offline characters; they can never act on real items.
	Buttons are recycled, never destroyed.
--]]

local _, ns = ...
local Item = {}
ns.Item = Item

-- Empty slots show the modern slot background; the classic texture is only a fallback.
local SLOT_ATLAS = "bags-item-slot64"
local CLASSIC_EMPTY = "Interface\\PaperDoll\\UI-Backpack-EmptySlot"
local hasSlotAtlas = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(SLOT_ATLAS) ~= nil
local EMPTY = not hasSlotAtlas and CLASSIC_EMPTY or nil
local BANK_CONTAINER = BANK_CONTAINER
local KEYRING_CONTAINER = KEYRING_CONTAINER or -2
local GetItemIcon = C_Item.GetItemIconByID or GetItemIcon
local GetContainerItemCooldown = C_Container.GetContainerItemCooldown
local GetContainerItemQuestInfo = C_Container.GetContainerItemQuestInfo
local SetItemButtonTexture, SetItemButtonCount, SetItemButtonDesaturated = SetItemButtonTexture, SetItemButtonCount, SetItemButtonDesaturated

local livePool, cachedPool = {}, {}
local liveCount = 0
local poolParent = CreateFrame("Frame")
poolParent:Hide()

local cooldownOf, questOf = {}, {} -- live button -> child regions (template names vary by client)
local templateOnEnter, templateUpdateTooltip = {}, {}
local linkOf = {} -- cached button -> hyperlink
local backgroundOf, tintOf = {}, {} -- button -> slot background / bag type tint

Item.size = 37


--[[ Slot background ]]--

local function AddBackground(button)
	local background = button:CreateTexture(nil, "BACKGROUND", nil, -2)
	background:SetAllPoints()
	if hasSlotAtlas then
		background:SetAtlas(SLOT_ATLAS)
	else
		background:SetTexture(CLASSIC_EMPTY)
	end
	backgroundOf[button] = background

	-- The empty-slot art is drawn on the icon itself (BORDER layer), so the tint sits
	-- above it and is shown only while the slot is empty.
	local tint = button:CreateTexture(nil, "ARTWORK", nil, -1)
	tint:SetPoint("TOPLEFT", 1, -1)
	tint:SetPoint("BOTTOMRIGHT", -1, 1)
	tint:Hide()
	tintOf[button] = tint
end

local colorOf = {} -- button -> bag type whose color tints the slot

-- Colors the slot of a profession/special bag; nil restores a normal slot.
function Item:SetSlotColor(button, bagType)
	local tint = tintOf[button]
	if not tint then return end
	colorOf[button] = bagType
	if bagType then
		tint:SetColorTexture(bagType.r, bagType.g, bagType.b, 0.12)
	else
		tint:Hide()
	end
end

local function UpdateTint(button, empty)
	local tint = tintOf[button]
	if tint then
		tint:SetShown(empty and colorOf[button] ~= nil)
	end
end


--[[ Tooltips for slots the bag API cannot describe (bank main slots, keyring) ]]--

local function InventorySlotFor(bag, slot)
	if bag == BANK_CONTAINER and BankButtonIDToInvSlotID then
		return BankButtonIDToInvSlotID(slot)
	elseif bag == KEYRING_CONTAINER and KeyRingButtonIDToInvSlotID then
		return KeyRingButtonIDToInvSlotID(slot)
	end
end

local function InventorySlotOnEnter(self)
	local invSlot = InventorySlotFor(self:GetParent():GetID(), self:GetID())
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if invSlot then
		GameTooltip:SetInventoryItem("player", invSlot)
	end
	GameTooltip:Show()
	CursorUpdate(self)
end


--[[ Live buttons ]]--

local function CreateLive()
	liveCount = liveCount + 1
	local name = "ForeverHubItem" .. liveCount
	local button = CreateFrame("ItemButton", name, poolParent, "ContainerFrameItemButtonTemplate")

	-- the template registers per-button events we do not need: the window drives updates
	button:SetScript("OnEvent", nil)
	button:SetScript("OnShow", nil)

	cooldownOf[button] = button.Cooldown or _G[name .. "Cooldown"]
	questOf[button] = button.IconQuestTexture or _G[name .. "IconQuestTexture"]
	templateOnEnter[button] = button:GetScript("OnEnter")
	templateUpdateTooltip[button] = button.UpdateTooltip

	for _, key in ipairs({"BattlepayItemTexture", "NewItemTexture", "UpgradeIcon", "ItemContextOverlay", "ItemSlotBackground"}) do
		if button[key] then
			button[key]:Hide()
		end
	end
	AddBackground(button)
	return button
end

-- Creates buttons ahead of time (out of combat) so opening windows never hitches.
function Item:Prewarm(count)
	while liveCount < count do
		livePool[#livePool + 1] = CreateLive()
	end
end

function Item:AcquireLive(holder, slot)
	local button = tremove(livePool) or CreateLive()
	button:SetParent(holder)
	button:SetID(slot)

	local bag = holder:GetID()
	if InventorySlotFor(bag, slot) then
		button:SetScript("OnEnter", InventorySlotOnEnter)
		button.UpdateTooltip = InventorySlotOnEnter
	elseif button:GetScript("OnEnter") ~= templateOnEnter[button] then
		button:SetScript("OnEnter", templateOnEnter[button])
		button.UpdateTooltip = templateUpdateTooltip[button]
	end

	button:Show()
	return button
end

function Item:ReleaseLive(button)
	button:Hide()
	button:ClearAllPoints()
	button:SetParent(poolParent)
	Item:SetSlotColor(button, nil)
	livePool[#livePool + 1] = button
end

function Item:UpdateLive(button, bag, slot, info, settings)
	SetItemButtonTexture(button, info and info.iconFileID or EMPTY)
	SetItemButtonCount(button, info and info.stackCount or 0)
	UpdateTint(button, not info)
	Item:UpdateBorder(button, info and info.quality, info and info.hyperlink, info and info.isBound, settings)

	if button.JunkIcon then
		button.JunkIcon:SetShown(settings.junkIcon and info and info.quality == 0 and not info.hasNoValue or false)
	end

	local quest = questOf[button]
	if quest then
		local questInfo = settings.questIcon and info and GetContainerItemQuestInfo(bag, slot)
		if questInfo and questInfo.questID and not questInfo.isActive then
			quest:SetTexture(TEXTURE_ITEM_QUEST_BANG)
			quest:Show()
		elseif questInfo and (questInfo.questID or questInfo.isQuestItem) then
			quest:SetTexture(TEXTURE_ITEM_QUEST_BORDER)
			quest:Show()
		else
			quest:Hide()
		end
	end

	Item:UpdateCooldown(button, bag, slot, info)
end

function Item:UpdateCooldown(button, bag, slot, info)
	local cooldown = cooldownOf[button]
	if not cooldown then return end
	if info then
		local start, duration, enable = GetContainerItemCooldown(bag, slot)
		CooldownFrame_Set(cooldown, start, duration, enable)
	else
		cooldown:Hide()
	end
end


--[[ Cached buttons ]]--

local function CachedOnEnter(self)
	local link = linkOf[self]
	if not link then return end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetHyperlink(link)
	GameTooltip:Show()
end

local function CachedOnClick(self)
	local link = linkOf[self]
	if link then
		HandleModifiedItemClick(link)
	end
end

local function HideTooltip()
	GameTooltip:Hide()
end

function Item:AcquireCached(parent)
	local button = tremove(cachedPool)
	if not button then
		button = CreateFrame("ItemButton", nil, parent)
		button:SetSize(Item.size, Item.size)
		button:SetScript("OnEnter", CachedOnEnter)
		button:SetScript("OnLeave", HideTooltip)
		button:SetScript("OnClick", CachedOnClick)
		AddBackground(button)
	else
		button:SetParent(parent)
	end
	button:Show()
	return button
end

function Item:ReleaseCached(button)
	button:Hide()
	button:ClearAllPoints()
	button:SetParent(poolParent)
	Item:SetSlotColor(button, nil)
	linkOf[button] = nil
	cachedPool[#cachedPool + 1] = button
end

function Item:UpdateCached(button, quality, count, link, settings)
	linkOf[button] = link
	SetItemButtonTexture(button, link and GetItemIcon(link) or EMPTY)
	SetItemButtonCount(button, count or 0)
	UpdateTint(button, not link)
	Item:UpdateBorder(button, quality, link, false, settings)
end


--[[ Shared ]]--

function Item:UpdateBorder(button, quality, link, isBound, settings)
	if settings.qualityBorder and quality and quality >= 2 then
		SetItemButtonQuality(button, quality, link, false, isBound)
	else
		SetItemButtonQuality(button, nil)
	end
end

-- Dims items that do not match the search (and locked items, like Blizzard does).
function Item:SetMatch(button, matches, locked)
	button:SetAlpha(matches and 1 or 0.3)
	SetItemButtonDesaturated(button, locked or not matches)
end
