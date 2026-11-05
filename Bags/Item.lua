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
local ours = {} -- every item button created here

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


--[[ Quest and junk markers ]]--

-- Modern atlas when the client has it, a classic texture otherwise.
local function SetArt(texture, atlas, file)
	if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
		texture:SetAtlas(atlas)
	else
		texture:SetTexture(file)
	end
end

local markersOf = {} -- button -> {glow, frame, bang, shade, coin}

local function AddMarkers(button)
	local markers = {}

	-- quest item: gold frame with a soft glow around the slot
	markers.glow = button:CreateTexture(nil, "OVERLAY", nil, 1)
	markers.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	markers.glow:SetBlendMode("ADD")
	markers.glow:SetVertexColor(1, 0.82, 0, 0.7)
	markers.glow:SetPoint("CENTER")
	markers.glow:SetSize(Item.size * 1.75, Item.size * 1.75)

	markers.frame = button:CreateTexture(nil, "OVERLAY", nil, 2)
	markers.frame:SetTexture("Interface\\Common\\WhiteIconFrame")
	markers.frame:SetVertexColor(1, 0.82, 0)
	markers.frame:SetAllPoints()

	-- starts a quest: the quest giver "!" in the corner
	markers.bang = button:CreateTexture(nil, "OVERLAY", nil, 3)
	markers.bang:SetSize(18, 18)
	markers.bang:SetPoint("TOPLEFT", -3, 3)
	SetArt(markers.bang, "QuestNormal", "Interface\\GossipFrame\\AvailableQuestIcon")

	-- junk: darker icon and a gold coin in the corner
	markers.shade = button:CreateTexture(nil, "ARTWORK", nil, 1)
	markers.shade:SetPoint("TOPLEFT", 2, -2)
	markers.shade:SetPoint("BOTTOMRIGHT", -2, 2)
	markers.shade:SetColorTexture(0.08, 0.06, 0.04, 0.5)

	markers.coin = button:CreateTexture(nil, "OVERLAY", nil, 3)
	markers.coin:SetSize(14, 14)
	markers.coin:SetPoint("TOPLEFT", 1, -1)
	SetArt(markers.coin, "coin-gold", "Interface\\MoneyFrame\\UI-GoldIcon")

	-- cannot be used by this character: red tint over the icon
	markers.unusable = button:CreateTexture(nil, "ARTWORK", nil, 2)
	markers.unusable:SetPoint("TOPLEFT", 2, -2)
	markers.unusable:SetPoint("BOTTOMRIGHT", -2, 2)
	markers.unusable:SetColorTexture(0.9, 0.08, 0.08, 0.38)

	-- new item: pulsing glow until the mouse passes over it
	markers.new = button:CreateTexture(nil, "OVERLAY", nil, 0)
	SetArt(markers.new, "bags-glow-white", "Interface\\Buttons\\UI-ActionButton-Border")
	markers.new:SetBlendMode("ADD")
	if markers.new:GetAtlas() then
		markers.new:SetAllPoints()
	else
		markers.new:SetPoint("CENTER")
		markers.new:SetSize(Item.size * 1.75, Item.size * 1.75)
	end
	local pulse = markers.new:CreateAnimationGroup()
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.3)
	fade:SetDuration(0.8)
	pulse:SetLooping("BOUNCE")
	markers.pulse = pulse

	-- item level (top right) and "BoE" (bottom left)
	markers.level = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	markers.level:SetPoint("TOPRIGHT", -2, -2)
	markers.boe = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	markers.boe:SetPoint("BOTTOMLEFT", 2, 2)
	markers.boe:SetText(ns.L.BOE)
	markers.boe:SetTextColor(0.45, 0.85, 1)

	-- upgrade over the equipped item (bottom right: gear never stacks, so no count there)
	markers.upgrade = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	markers.upgrade:SetPoint("BOTTOMRIGHT", -1, 2)

	for key, region in pairs(markers) do
		if key ~= "pulse" then
			region:Hide()
		end
	end
	markersOf[button] = markers
end

local function SetNewGlow(button, shown)
	local markers = markersOf[button]
	if not markers then return end
	markers.new:SetShown(shown)
	if shown and not markers.pulse:IsPlaying() then
		markers.pulse:Play()
	elseif not shown then
		markers.pulse:Stop()
	end
end


--[[ Item details: level, BoE, usability ]]--

local GetItemInfo = C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item.GetItemInfoInstant or GetItemInfoInstant
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
local BIND_ON_EQUIP = Enum.ItemBind and Enum.ItemBind.OnEquip or 2

-- equippable slots where an item level means nothing
local NO_LEVEL = {
	INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_TABARD = true, INVTYPE_BODY = true,
	INVTYPE_AMMO = true, INVTYPE_NON_EQUIP = true, INVTYPE_NON_EQUIP_IGNORE = true,
}

local function EquipLocation(link)
	local equipLoc = select(4, GetItemInfoInstant(link))
	return equipLoc and equipLoc ~= "" and equipLoc or nil
end

-- Item level of gear, nil for everything else.
local function ItemLevel(link)
	local equipLoc = EquipLocation(link)
	if not equipLoc or NO_LEVEL[equipLoc] then return end
	local level = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link) or select(4, GetItemInfo(link))
	return level and level > 1 and level or nil
end

local function IsBindOnEquip(link)
	return EquipLocation(link) ~= nil and select(14, GetItemInfo(link)) == BIND_ON_EQUIP
end

-- An item is unusable when its tooltip shows a red restriction line (class, level,
-- armor or weapon skill, profession...). Cached per link; reset on level/skill changes.
local unusable = {}

local function IsRed(color)
	return color and color.r > 0.9 and color.g < 0.25 and color.b < 0.25
end

local function ScanUnusable(link)
	local data = C_TooltipInfo.GetHyperlink(link)
	if not data or not data.lines then return nil end -- not known by the client yet
	for i = 2, #data.lines do -- line 1 is the name
		local line = data.lines[i]
		if IsRed(line.leftColor) or IsRed(line.rightColor) then
			return true
		end
	end
	return false
end

function Item:IsUnusable(link)
	local result = unusable[link]
	if result == nil and C_TooltipInfo and C_TooltipInfo.GetHyperlink then
		local ok, value = pcall(ScanUnusable, link)
		if ok and value ~= nil then
			unusable[link] = value
			result = value
		end
	end
	return result or false
end

function Item:ResetUsability()
	wipe(unusable)
end

-- Upgrade percentage: only for this character's own items, compared with what it wears.
local function UpdateUpgrade(markers, link, unusableItem, settings)
	local text, r, g, b
	if settings.upgrade and link and not unusableItem then
		local result = ns.Upgrade:Compare(link)
		if not (settings.upgradeOnly and (type(result) ~= "number" or result <= 0.5) and result ~= "new") then
			text, r, g, b = ns.Upgrade:Format(result)
		end
	end
	if text then
		markers.upgrade:SetText(text)
		markers.upgrade:SetTextColor(r, g, b)
	end
	markers.upgrade:SetShown(text ~= nil)
end

-- Level, BoE and usability markers shared by live and cached buttons.
local function UpdateDetails(button, link, quality, isBound, settings, live)
	local markers = markersOf[button]
	if not markers then return end

	local level = settings.itemLevel and link and ItemLevel(link)
	if level then
		local color = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality or 1]
		markers.level:SetText(level)
		markers.level:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
	end
	markers.level:SetShown(level ~= nil)
	markers.boe:SetShown(settings.boe and link and isBound == false and IsBindOnEquip(link) or false)
	local unusableItem = link and Item:IsUnusable(link)
	markers.unusable:SetShown(settings.unusable and unusableItem or false)
	UpdateUpgrade(markers, live and link, unusableItem, settings)
end

-- quest: nil, "item" (used by a quest) or "start" (starts a quest)
local function UpdateMarkers(button, junk, quest)
	local markers = markersOf[button]
	if not markers then return end
	markers.glow:SetShown(quest ~= nil)
	markers.frame:SetShown(quest ~= nil)
	markers.bang:SetShown(quest == "start")
	markers.shade:SetShown(junk)
	markers.coin:SetShown(junk and quest == nil)
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

-- Alt+left-click marks an item as junk (or keeps a gray item); Blizzard does nothing on it.
-- Once seen, a new item stops glowing.
local function LiveOnLeave(self)
	local bag, slot = self:GetParent():GetID(), self:GetID()
	if C_NewItems and C_NewItems.IsNewItem(bag, slot) then
		C_NewItems.RemoveNewItem(bag, slot)
	end
	SetNewGlow(self, false)
end

local function LiveOnClick(self, mouse)
	if mouse == "LeftButton" and IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown() then
		ns.Merchant:ToggleJunk(self:GetParent():GetID(), self:GetID())
	end
end

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
	AddMarkers(button)
	button:HookScript("OnClick", LiveOnClick)
	button:HookScript("OnLeave", LiveOnLeave) -- OnEnter is swapped for bank/keyring slots, OnLeave never is
	ours[button] = true
	return button
end

-- A tooltip (or the stack split frame) anchored to one of our buttons can make the
-- client refuse to re-anchor that button ("anchor family connection"), so they are
-- detached before a relayout.
function Item:DetachFromButtons()
	for _, tooltip in ipairs({GameTooltip, ItemRefTooltip}) do
		local owner = tooltip and tooltip:GetOwner()
		if owner and ours[owner] then
			tooltip:Hide()
			tooltip:ClearAllPoints()
		end
	end
	local split = StackSplitFrame
	if split and split:IsShown() and ours[split.owner] then
		split:Hide()
	end
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

	-- the template's own small markers are replaced by ours
	if button.JunkIcon then
		button.JunkIcon:Hide()
	end
	if questOf[button] then
		questOf[button]:Hide()
	end

	local quest
	if settings.questIcon and info then
		local questInfo = GetContainerItemQuestInfo(bag, slot)
		if questInfo and questInfo.questID and not questInfo.isActive then
			quest = "start"
		elseif questInfo and (questInfo.questID or questInfo.isQuestItem) then
			quest = "item"
		end
	end
	if quest then
		SetItemButtonQuality(button, nil) -- the gold quest frame replaces the quality border
	end
	UpdateMarkers(button, settings.junkIcon and ns.Merchant:IsJunk(info) or false, quest)
	UpdateDetails(button, info and info.hyperlink, info and info.quality, info and info.isBound or false, settings, true)
	SetNewGlow(button, settings.newGlow and info and C_NewItems and C_NewItems.IsNewItem(bag, slot) or false)

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
		AddMarkers(button)
		ours[button] = true
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

	local itemID = link and tonumber(link:match("item:(%d+)"))
	local junk = settings.junkIcon and itemID and ns.Merchant:IsJunk({itemID = itemID, quality = quality}) or false
	UpdateMarkers(button, junk, nil)
	UpdateDetails(button, link, quality, nil, settings) -- binding state is unknown offline: no "BoE"
	SetNewGlow(button, false)
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
