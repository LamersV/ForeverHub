--[[
	Bags - inventory and bank windows

	Update strategy:
	  * nothing happens while a window is hidden except setting a dirty flag
	  * on show, the grid is rebuilt only if the bag "signature" (bags, sizes, owner,
	    columns) changed; otherwise only item contents are refreshed
	  * while shown, only the bags/slots reported as changed are touched
--]]

local _, ns = ...
local L, W = ns.L, ns.Widgets
local Data, Item, Search = ns.BagData, ns.Item, ns.Search

local Bags = ns:NewModule("Bags")
Bags.frames = {}
Bags.searchText = ""

local PADDING = 10
local HEADER = 62
local BAGBAR = 34
local FOOTER = 30
local MIN_WIDTH = 270
local GROUP_GAP = 6 -- space between bag type groups
local GROUP_LABEL = 14 -- height of a group's title

local BANK_CONTAINER = BANK_CONTAINER
local KEYRING_CONTAINER = KEYRING_CONTAINER or -2
local GetItemIcon = C_Item.GetItemIconByID or GetItemIcon
local floor, ceil, max = math.floor, math.ceil, math.max
local settings

local Container = {}


--[[ Ownership and bag lists ]]--

function Container:IsLive()
	if self.owner then return false end
	return self.kind == "inventory" or Data.atBank
end

function Container:GetCharacter()
	return Data:GetCharacter(self.owner)
end

function Container:GetBags()
	if self.kind == "inventory" then
		return Data.inventoryBags
	elseif self:IsLive() then
		return Data:GetBankBags()
	end

	local bags = {}
	local char = self:GetCharacter()
	for bag in pairs(char and char.bags or {}) do
		if Data:IsBankBag(bag) then
			bags[#bags + 1] = bag
		end
	end
	table.sort(bags)
	return bags
end

function Container:GetBagSize(bag)
	if self:IsLive() then
		local live = Data.live[bag]
		return live and live.size or 0
	end
	local char = self:GetCharacter()
	local data = char and char.bags[bag]
	return data and data.size or 0
end

-- Profession/special bag type, or nil for a normal bag.
function Container:GetBagType(bag)
	local char = self:GetCharacter()
	local data = char and char.bags[bag]
	return Data:GetBagType(bag, data and data.family, data and data.link)
end

-- Describes everything that affects the grid; a change means a relayout.
function Container:GetSignature()
	local parts = {tostring(self.owner), tostring(self:IsLive()), self:GetColumns(), tostring(settings.reverseBags), settings.spacing,
		tostring(self:IsBagBarShown()), tostring(settings.splitBags), tostring(settings.colorBags)}
	for _, bag in ipairs(self:GetBags()) do
		local bagType = self:GetBagType(bag)
		parts[#parts + 1] = bag .. ":" .. self:GetBagSize(bag) .. (settings.hiddenBags[bag] and "h" or "") .. (bagType and bagType.key or "")
	end
	return table.concat(parts, ",")
end

function Container:GetColumns()
	return self.kind == "bank" and settings.bankColumns or settings.columns
end

function Container:IsBagBarShown()
	return settings.showBagBar[self.kind]
end


--[[ Layout ]]--

function Container:GetHolder(bag)
	local holder = self.holders[bag]
	if not holder then
		holder = CreateFrame("Frame", nil, self.Content)
		holder:SetID(bag) -- read by Blizzard's item button code as the bag of each slot
		holder:SetSize(1, 1)
		holder:SetPoint("TOPLEFT")
		self.holders[bag] = holder
	end
	return holder
end

function Container:ReleaseAll()
	local release = self.layoutLive and Item.ReleaseLive or Item.ReleaseCached
	for i = 1, #self.buttons do
		release(Item, self.buttons[i])
		self.buttons[i] = nil
	end
	for _, slots in pairs(self.byBag) do
		wipe(slots)
	end
end

-- Visible bags in display order; split into groups by bag type when enabled
-- (normal bags first, then each profession type in the order it first appears).
function Container:GetGroups(bags)
	local first, last, dir = 1, #bags, 1
	if settings.reverseBags then
		first, last, dir = #bags, 1, -1
	end

	local normal = {}
	local groups = {normal}
	local byKey = {}
	for i = first, last, dir do
		local bag = bags[i]
		if not settings.hiddenBags[bag] and self:GetBagSize(bag) > 0 then
			local bagType = settings.splitBags and self:GetBagType(bag)
			local group = normal
			if bagType then
				group = byKey[bagType.key]
				if not group then
					group = {type = bagType}
					byKey[bagType.key] = group
					groups[#groups + 1] = group
				end
			end
			group[#group + 1] = bag
		end
	end
	return groups
end

function Container:GetLabel(index)
	local label = self.labels[index]
	if not label then
		label = self.Content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		label:SetJustifyH("LEFT")
		self.labels[index] = label
	end
	return label
end

function Container:Layout()
	Item:DetachFromButtons()
	self:ReleaseAll()

	local live = self:IsLive()
	local bags = self:GetBags()
	local columns = self:GetColumns()
	local step = Item.size + settings.spacing
	local y, labels = 0, 0
	local failed = false

	for _, group in ipairs(self:GetGroups(bags)) do
		if #group > 0 then
			if y > 0 then
				y = y + GROUP_GAP
			end
			if group.type then
				labels = labels + 1
				local label = self:GetLabel(labels)
				local info = group.type
				label:ClearAllPoints()
				label:SetPoint("TOPLEFT", self.Content, "TOPLEFT", 1, -y)
				label:SetText(L["BAGTYPE_" .. info.key] or info.key)
				label:SetTextColor(info.r, info.g, info.b)
				label:Show()
				y = y + GROUP_LABEL
			end

			local count = 0
			for _, bag in ipairs(group) do
				local holder = self:GetHolder(bag)
				local slots = self.byBag[bag] or {}
				self.byBag[bag] = slots
				local bagType = settings.colorBags and self:GetBagType(bag)

				for slot = 1, self:GetBagSize(bag) do
					local button = live and Item:AcquireLive(holder, slot) or Item:AcquireCached(holder)
					if not pcall(button.SetPoint, button, "TOPLEFT", self.Content, "TOPLEFT", (count % columns) * step, -(y + floor(count / columns) * step)) then
						failed = true
					end
					Item:SetSlotColor(button, bagType)
					slots[slot] = button
					self.buttons[#self.buttons + 1] = button
					count = count + 1
				end
			end
			y = y + ceil(count / columns) * step
		end
	end
	for i = labels + 1, #self.labels do
		self.labels[i]:Hide()
	end

	self.layoutLive = live
	self.signature = self:GetSignature()

	-- a button the client refused to move: try the whole layout once more next frame
	if failed and not self.relayoutPending then
		self.relayoutPending = true
		ns:Defer("bags-relayout-" .. self.kind, function()
			if self:IsShown() then
				self:Layout()
			end
			self.relayoutPending = false
		end)
	end

	local barHeight = self:IsBagBarShown() and BAGBAR or 0
	self:UpdateBagBar(bags)
	self.Content:SetPoint("TOPLEFT", PADDING, -HEADER - barHeight)

	local width = max(MIN_WIDTH, PADDING * 2 + columns * step - settings.spacing)
	self:SetSize(width, HEADER + barHeight + max(step, y) - settings.spacing + FOOTER)

	self:UpdateAll()
end


--[[ Content ]]--

function Container:UpdateSlot(bag, slot)
	local button = self.byBag[bag] and self.byBag[bag][slot]
	if not button then return end

	local link, quality, locked
	if self.layoutLive then
		local live = Data.live[bag]
		local info = live and live[slot]
		Item:UpdateLive(button, bag, slot, info, settings)
		link, quality, locked = info and info.hyperlink, info and info.quality, info and info.isLocked
	else
		local data = self:GetCharacter().bags[bag]
		local value = data and data[slot]
		local count
		if value then
			quality, count, link = Data:DecodeSlot(value)
		end
		Item:UpdateCached(button, quality, count, link, settings)
	end

	local matches = (not self.focusBag or self.focusBag == bag) and Search:Matches(Bags.searchText, link, quality)
	Item:SetMatch(button, matches, locked)
end

function Container:UpdateBag(bag)
	local slots = self.byBag[bag]
	if slots then
		for slot in pairs(slots) do
			self:UpdateSlot(bag, slot)
		end
	end
end

function Container:UpdateAll()
	for bag in pairs(self.byBag) do
		self:UpdateBag(bag)
	end
	self:UpdateFooter()
	self.dirty = false
end

function Container:UpdateCooldowns()
	if not self.layoutLive then return end
	for bag, slots in pairs(self.byBag) do
		local live = Data.live[bag]
		for slot, button in pairs(slots) do
			Item:UpdateCooldown(button, bag, slot, live and live[slot])
		end
	end
end

-- Free slots of normal bags, plus those of profession bags (which only take their
-- own kind of items) shown apart in green. Turns red when normal bags are almost full.
function Container:UpdateFooter()
	local free, total, freeSpecial, totalSpecial = 0, 0, 0, 0
	for bag, slots in pairs(self.byBag) do
		local live = self.layoutLive and Data.live[bag]
		local data = not self.layoutLive and self:GetCharacter().bags[bag]
		local special = bag ~= KEYRING_CONTAINER and self:GetBagType(bag) ~= nil
		for slot in pairs(slots) do
			local empty = not (live and live[slot] or data and data[slot])
			if bag == KEYRING_CONTAINER then
				-- keys only: counted in neither
			elseif special then
				totalSpecial = totalSpecial + 1
				freeSpecial = freeSpecial + (empty and 1 or 0)
			else
				total = total + 1
				free = free + (empty and 1 or 0)
			end
		end
	end

	local text = L.FREE_SLOTS:format(free, total)
	if free == 0 and total > 0 then
		text = "|cffff3030" .. L.BAGS_FULL .. "|r"
	elseif free <= settings.lowSpace then
		text = "|cffff5040" .. text .. "|r"
	end
	if totalSpecial > 0 then
		text = text .. ("  |cff8fd36a+%d|r"):format(freeSpecial)
	end
	self.Free:SetText(text)

	if self.Money then
		local char = self:GetCharacter()
		local money = self.owner and (char and char.money or 0) or GetMoney()
		self.Money:SetText(GetMoneyString(money, true))
	end

	if self.Junk then
		local slots, value
		if settings.sellJunkButton and ns.Merchant.atMerchant and self:IsLive() then
			slots, value = ns.Merchant:GetJunk()
		end
		if slots and #slots > 0 then
			self.Junk.count, self.Junk.value = #slots, value
			self.Junk.Value:SetText(GetMoneyString(value, true))
			self.Junk:Show()
		else
			self.Junk:Hide()
		end
	end
end

local function JunkOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(L.JUNK_SELL)
	GameTooltip:AddDoubleLine(L.JUNK_ITEMS:format(self.count or 0), GetMoneyString(self.value or 0, true), 1, 1, 1, 1, 1, 1)
	GameTooltip:AddLine(L.JUNK_HINT, 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

-- Rebuilds when the structure changed, otherwise refreshes contents only.
function Container:Refresh()
	if self:GetSignature() ~= self.signature then
		self:Layout()
	else
		self:UpdateAll()
	end
	self:UpdateTitle()
end


--[[ Header ]]--

local function ClassColored(name, class)
	local color = class and RAID_CLASS_COLORS[class]
	return color and color:WrapTextInColorCode(name) or name
end

function Container:UpdateTitle()
	local base = self.kind == "bank" and L.BANK or L.INVENTORY
	local char = self:GetCharacter()
	if self.owner then
		W.SetTitle(self, ClassColored(self.owner, char and char.class) .. " - " .. base)
	elseif self.kind == "bank" and not Data.atBank then
		W.SetTitle(self, L.OFFLINE:format(base))
	else
		W.SetTitle(self, base)
	end

	local portrait = self.PortraitContainer and self.PortraitContainer.portrait or self.portrait
	if portrait then
		local coords = self.owner and char and char.class and CLASS_ICON_TCOORDS[char.class]
		if coords then
			portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
			portrait:SetTexCoord(unpack(coords))
		else
			portrait:SetTexCoord(0, 1, 0, 1)
			SetPortraitTexture(portrait, "player")
		end
	end

	if self.Sort then
		self.Sort:SetShown(self:IsLive())
	end
	if self.Deposit then
		self.Deposit:SetShown(self:IsLive())
	end
	if self.BlizzardBank then
		self.BlizzardBank:SetShown(self:IsLive())
	end
end

function Container:SetOwner(name)
	if name == ns.playerName then
		name = nil
	end
	if name and not Data:GetCharacter(name) then
		return ns:Print(L.NOT_CACHED)
	end
	self.owner = name
	self:Refresh()
end

local function SortedCharacters()
	local names = {}
	for name in pairs(Data:GetCharacters()) do
		names[#names + 1] = name
	end
	table.sort(names)
	return names
end

local function OpenCharacterMenu(button)
	local frame = button:GetParent()
	if not MenuUtil then
		-- fallback: cycle through characters
		local names = SortedCharacters()
		local current = frame.owner or ns.playerName
		for i, name in ipairs(names) do
			if name == current then
				return frame:SetOwner(names[i % #names + 1])
			end
		end
		return
	end

	MenuUtil.CreateContextMenu(button, function(_, root)
		root:CreateTitle(L.CHARACTERS)
		local chars = Data:GetCharacters()
		for _, name in ipairs(SortedCharacters()) do
			root:CreateRadio(ClassColored(name, chars[name].class),
				function() return (frame.owner or ns.playerName) == name end,
				function() frame:SetOwner(name) end)
		end

		local others = {}
		for _, name in ipairs(SortedCharacters()) do
			if name ~= ns.playerName then
				others[#others + 1] = name
			end
		end
		if #others > 0 then
			root:CreateDivider()
			for _, name in ipairs(others) do
				root:CreateButton("|cffff7070" .. L.DELETE_CHARACTER:format(name) .. "|r", function()
					Data:DeleteCharacter(name)
					if frame.owner == name then
						frame:SetOwner(nil)
					end
				end)
			end
		end
	end)
end

local function MoneyOnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
	GameTooltip:AddLine(L.CHARACTERS)
	local total = 0
	local chars = Data:GetCharacters()
	local names = SortedCharacters()
	table.sort(names, function(a, b) return (chars[a].money or 0) > (chars[b].money or 0) end)
	for _, name in ipairs(names) do
		local money = chars[name].money or 0
		total = total + money
		GameTooltip:AddDoubleLine(ClassColored(name, chars[name].class), GetMoneyString(money, true), 1, 1, 1, 1, 1, 1)
	end
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L.TOTAL, GetMoneyString(total, true), 1, 0.82, 0, 1, 1, 1)
	if ns.Gold then
		ns.Gold:AddTooltipLines(GameTooltip)
	end
	GameTooltip:Show()
end


--[[ Bag bar ]]--

local BAG_EMPTY = "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"

local function BagIcon(frame, bag)
	if bag == 0 or bag == BANK_CONTAINER then
		return "Interface\\Buttons\\Button-Backpack-Up"
	elseif bag == KEYRING_CONTAINER then
		return "Interface\\ContainerFrame\\KeyRing-Bag-Icon"
	end
	if frame:IsLive() then
		local invSlot = Data:GetBagInventorySlot(bag)
		if invSlot then
			return GetInventoryItemTexture("player", invSlot) or BAG_EMPTY
		end
		local tab = frame.tabInfo and frame.tabInfo[bag]
		return tab and tab.icon or BAG_EMPTY
	end
	local data = frame:GetCharacter().bags[bag]
	return data and data.link and GetItemIcon(data.link) or BAG_EMPTY
end

local function BagOnClick(self)
	local frame = self:GetParent():GetParent()
	if frame:IsLive() and self.invSlot and CursorHasItem() then
		PutItemInBag(self.invSlot)
		return
	end
	settings.hiddenBags[self.bag] = not settings.hiddenBags[self.bag] or nil
	frame:Layout()
end

local function BagOnEnter(self)
	local frame = self:GetParent():GetParent()
	frame.focusBag = self.bag
	frame:UpdateAll()

	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if frame:IsLive() and self.invSlot and GetInventoryItemTexture("player", self.invSlot) then
		GameTooltip:SetInventoryItem("player", self.invSlot)
	else
		local data = not frame:IsLive() and frame:GetCharacter().bags[self.bag]
		if data and data.link then
			GameTooltip:SetHyperlink(data.link)
		else
			GameTooltip:SetText(self.bag == 0 and BACKPACK_TOOLTIP or self.bag == BANK_CONTAINER and L.BANK or BAGSLOT or "")
		end
	end
	local bagType = frame:GetBagType(self.bag)
	if bagType then
		GameTooltip:AddLine(L["BAGTYPE_" .. bagType.key] or bagType.key, bagType.r, bagType.g, bagType.b)
	end
	GameTooltip:AddLine(L.BAGS_TOGGLE, 0.7, 0.7, 0.7)
	GameTooltip:Show()
end

local function BagOnLeave(self)
	local frame = self:GetParent():GetParent()
	frame.focusBag = nil
	frame:UpdateAll()
	GameTooltip:Hide()
end

local function BagOnDragStart(self)
	if self:GetParent():GetParent():IsLive() and self.invSlot then
		PickupBagFromSlot(self.invSlot)
	end
end

local function BagOnReceiveDrag(self)
	if self:GetParent():GetParent():IsLive() and self.invSlot then
		PutItemInBag(self.invSlot)
	end
end

function Container:UpdateBagBar(bags)
	local shown = self:IsBagBarShown()
	self.BagBar:SetShown(shown)
	if not shown then return end

	self.tabInfo = nil
	if self.kind == "bank" and self:IsLive() and C_Bank and C_Bank.FetchPurchasedBankTabData and Enum.BankType then
		local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabData, Enum.BankType.Character)
		if ok and type(tabs) == "table" then
			self.tabInfo = {}
			for _, tab in ipairs(tabs) do
				self.tabInfo[tab.ID] = tab
			end
		end
	end

	local buttons = self.BagBar.buttons
	for i, bag in ipairs(bags) do
		local button = buttons[i]
		if not button then
			button = CreateFrame("Button", nil, self.BagBar)
			button:SetSize(28, 28)
			button:SetPoint("LEFT", (i - 1) * 31, 0)
			button.Icon = button:CreateTexture(nil, "ARTWORK")
			button.Icon:SetAllPoints()
			button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			button:RegisterForDrag("LeftButton")
			button:SetScript("OnClick", BagOnClick)
			button:SetScript("OnEnter", BagOnEnter)
			button:SetScript("OnLeave", BagOnLeave)
			button:SetScript("OnDragStart", BagOnDragStart)
			button:SetScript("OnReceiveDrag", BagOnReceiveDrag)
			buttons[i] = button
		end
		button.bag = bag
		button.invSlot = Data:GetBagInventorySlot(bag)
		button.Icon:SetTexture(BagIcon(self, bag))
		button.Icon:SetDesaturated(settings.hiddenBags[bag] and true or false)
		button.Icon:SetAlpha(settings.hiddenBags[bag] and 0.4 or 1)
		button:Show()
	end
	for i = #bags + 1, #buttons do
		buttons[i]:Hide()
	end
end


--[[ Construction ]]--

local function CreateContainer(kind)
	local name = kind == "bank" and "ForeverHubBank" or "ForeverHubInventory"
	local frame = W.CreateWindow(name, UIParent, settings.positions)
	Mixin(frame, Container)

	frame.kind = kind
	frame.holders, frame.byBag, frame.buttons, frame.labels = {}, {}, {}, {}
	frame:SetScale(settings.itemScale)
	if kind == "bank" then
		frame:RestorePosition("TOPLEFT", 40, -110)
	else
		frame:RestorePosition("BOTTOMRIGHT", -70, 110)
	end

	frame.Content = CreateFrame("Frame", nil, frame)
	frame.Content:SetSize(1, 1)
	frame.Content:SetPoint("TOPLEFT", PADDING, -HEADER)

	-- character selector over the portrait
	local selector = CreateFrame("Button", nil, frame)
	selector:SetSize(56, 56)
	selector:SetPoint("TOPLEFT", -6, 7)
	selector:SetScript("OnClick", OpenCharacterMenu)
	W.AttachTooltip(selector, L.CHARACTERS)

	-- search
	local search = W.CreateWithTemplates("EditBox", name .. "Search", frame, "SearchBoxTemplate", "InputBoxTemplate")
	search:SetHeight(20)
	search:SetAutoFocus(false)
	search:SetPoint("TOPLEFT", 64, -32)
	search:SetPoint("RIGHT", frame, "RIGHT", -64, 0)
	search:HookScript("OnTextChanged", function(self)
		Bags:SetSearch(self:GetText())
	end)
	search:SetScript("OnEscapePressed", function(self)
		self:SetText("")
		self:ClearFocus()
	end)
	W.AttachTooltip(search, L.SEARCH_HELP, L.SEARCH)
	frame.Search = search

	-- title bar buttons
	local bagToggle = W.CreateIconButton(frame, "Interface\\Icons\\INV_Misc_Bag_08", 22, L.BAGS_TOGGLE)
	bagToggle:SetPoint("TOPRIGHT", -12, -31)
	bagToggle:SetScript("OnClick", function()
		settings.showBagBar[kind] = not settings.showBagBar[kind]
		frame:Layout()
	end)

	frame.Sort = W.CreateIconButton(frame, "Interface\\Icons\\INV_Pet_Broom", 22, L.SORT)
	frame.Sort:SetPoint("RIGHT", bagToggle, "LEFT", -5, 0)
	frame.Sort:SetScript("OnClick", function() Bags:Sort(kind) end)

	if kind == "bank" then
		frame.Deposit = W.CreateIconButton(frame, "Interface\\Icons\\INV_Misc_Herb_01", 22)
		frame.Deposit:SetPoint("RIGHT", frame.Sort, "LEFT", -5, 0)
		frame.Deposit:SetScript("OnClick", function() Bags:DepositReagents() end)
		W.AttachTooltip(frame.Deposit, L.DEPOSIT_TIP, L.DEPOSIT_REAGENTS)
	end

	-- options: leftmost title bar button; the search box ends just before it
	local options = W.CreateIconButton(frame, "Interface\\Icons\\INV_Misc_Gear_01", 22, L.OPEN_OPTIONS)
	options:SetPoint("RIGHT", frame.Deposit or frame.Sort, "LEFT", -5, 0)
	options:SetScript("OnClick", function() ns:OpenOptions() end)
	search:SetPoint("RIGHT", options, "LEFT", -6, 0)

	frame.BagBar = CreateFrame("Frame", nil, frame)
	frame.BagBar:SetSize(1, 28)
	frame.BagBar:SetPoint("TOPLEFT", PADDING, -HEADER + 2)
	frame.BagBar.buttons = {}

	-- footer
	frame.Free = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	frame.Free:SetPoint("BOTTOMLEFT", 14, 11)

	if kind == "inventory" then
		-- sell junk: only shown at a merchant when there is something to sell
		local junk = W.CreateIconButton(frame, "Interface\\Icons\\INV_Misc_Coin_02", 18)
		junk:SetPoint("LEFT", frame.Free, "RIGHT", 8, 0)
		junk:SetScript("OnClick", function() ns.Merchant:SellJunk() end)
		junk:SetScript("OnEnter", JunkOnEnter)
		junk:SetScript("OnLeave", GameTooltip_Hide)
		junk.Value = junk:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		junk.Value:SetPoint("LEFT", junk, "RIGHT", 4, 0)
		junk:Hide()
		frame.Junk = junk

		local money = CreateFrame("Button", nil, frame)
		money:SetSize(120, 18)
		money:SetPoint("BOTTOMRIGHT", -12, 7)
		money:SetScript("OnEnter", MoneyOnEnter)
		money:SetScript("OnLeave", GameTooltip_Hide)
		frame.Money = money:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		frame.Money:SetPoint("RIGHT")
		frame.Money:SetJustifyH("RIGHT")
	else
		frame.BlizzardBank = W.CreateButton(frame, BANK or "Blizzard", 100, function()
			Bags:UseBlizzardBank()
		end)
		frame.BlizzardBank:SetPoint("BOTTOMRIGHT", -10, 6)
		W.AttachTooltip(frame.BlizzardBank, L.USE_BLIZZARD_BANK)
	end

	frame:SetScript("OnShow", function(self)
		self:Refresh()
		PlaySound(SOUNDKIT.IG_BACKPACK_OPEN)
	end)
	frame:SetScript("OnHide", function(self)
		PlaySound(SOUNDKIT.IG_BACKPACK_CLOSE)
		self.Search:ClearFocus()
		local hadOwner = self.owner
		self.owner = nil
		if hadOwner then
			self.signature = nil
		end
		if Bags.OnFrameHidden then
			Bags:OnFrameHidden(kind)
		end
	end)

	Bags.frames[kind] = frame
	return frame
end


--[[ Public API ]]--

function Bags:GetFrame(kind, create)
	return self.frames[kind] or (create and CreateContainer(kind))
end

function Bags:Show(kind)
	self:GetFrame(kind, true):Show()
end

function Bags:Hide(kind)
	local frame = self.frames[kind]
	if frame then
		frame:Hide()
	end
end

function Bags:Toggle(kind)
	local frame = self:GetFrame(kind, true)
	frame:SetShown(not frame:IsShown())
end

function Bags:IsShown(kind)
	local frame = self.frames[kind]
	return frame and frame:IsShown()
end

function Bags:SetSearch(text)
	if text == self.searchText then return end
	self.searchText = text
	for _, frame in pairs(self.frames) do
		if frame.Search:GetText() ~= text then
			frame.Search:SetText(text)
		end
	end
	ns:Defer("bags-search", function()
		for _, frame in pairs(Bags.frames) do
			if frame:IsShown() then
				frame:UpdateAll()
			end
		end
	end)
end

function Bags:Sort(kind)
	if kind == "inventory" then
		C_Container.SortBags()
	elseif C_Container.SortBankBags then
		C_Container.SortBankBags()
	elseif C_Container.SortBank then
		C_Container.SortBank(Enum.BankType and Enum.BankType.Character or 0)
	else
		return
	end
	PlaySound(SOUNDKIT.UI_BAG_SORTING_01 or SOUNDKIT.IG_BACKPACK_OPEN)
end

--[[ Reagent deposit ]]--

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local ItemClass = Enum.ItemClass or {}
local REAGENT_CLASSES = {[ItemClass.Tradegoods or 7] = true, [ItemClass.Reagent or 5] = true}
local DEPOSIT_BATCH, DEPOSIT_DELAY = 8, 0.2
local depositing

-- Trade goods, reagents and anything flagged as a crafting reagent; never junk.
local function IsReagent(info)
	if not info or not info.itemID or info.isLocked or info.quality == 0 then return false end
	local classID = select(6, GetItemInfoInstant(info.itemID))
	if REAGENT_CLASSES[classID] then return true end
	return select(17, GetItemInfo(info.itemID)) == true
end

function Bags:DepositReagents()
	if depositing or not Data.atBank then return end
	local slots = {}
	for _, bag in ipairs(Data.inventoryBags) do
		if bag ~= KEYRING_CONTAINER then
			for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
				if IsReagent(C_Container.GetContainerItemInfo(bag, slot)) then
					slots[#slots + 1] = {bag, slot}
				end
			end
		end
	end
	if #slots == 0 then
		return ns:Print(L.DEPOSIT_NONE)
	end

	depositing = true
	local bankType = Enum.BankType and Enum.BankType.Character
	local index = 1
	local function Step()
		-- with the bank closed, "using" an item would use it for real
		if not Data.atBank then
			depositing = false
			return
		end
		for _ = 1, DEPOSIT_BATCH do
			local entry = slots[index]
			if not entry then
				depositing = false
				ns:Print(L.DEPOSITED:format(#slots))
				return
			end
			if IsReagent(C_Container.GetContainerItemInfo(entry[1], entry[2])) then
				C_Container.UseContainerItem(entry[1], entry[2], nil, bankType)
			end
			index = index + 1
		end
		C_Timer.After(DEPOSIT_DELAY, Step)
	end
	Step()
end


-- Refreshes item contents and footers (junk marks, merchant state) without a relayout.
function Bags:UpdateItems()
	for _, frame in pairs(self.frames) do
		if frame:IsShown() then
			frame:UpdateAll()
		else
			frame.dirty = true
		end
	end
end

-- Called by the options panel after a layout setting changed.
function Bags:ApplySettings()
	for _, frame in pairs(self.frames) do
		frame:SetScale(settings.itemScale)
		frame.signature = nil
		if frame:IsShown() then
			frame:Refresh()
		end
	end
end


--[[ Data events ]]--

local function ForShown(method, ...)
	for _, frame in pairs(Bags.frames) do
		if frame:IsShown() then
			frame[method](frame, ...)
		else
			frame.dirty = true
		end
	end
end

local function OnData(event, a, b)
	if event == "BAGS_CHANGED" then
		for _, frame in pairs(Bags.frames) do
			if not frame:IsShown() then
				frame.dirty = true
			elseif frame:GetSignature() ~= frame.signature then
				frame:Layout()
			elseif frame.layoutLive then
				for bag in pairs(a) do
					frame:UpdateBag(bag)
				end
				frame:UpdateFooter()
			end
		end
	elseif event == "SLOT_CHANGED" then
		for _, frame in pairs(Bags.frames) do
			if frame:IsShown() and frame.layoutLive then
				frame:UpdateSlot(a, b)
			end
		end
	elseif event == "COOLDOWNS" then
		ForShown("UpdateCooldowns")
	elseif event == "QUESTS" or event == "ITEM_INFO" then
		ns:Defer("bags-refresh", function() ForShown("UpdateAll") end)
	elseif event == "MONEY" then
		ForShown("UpdateFooter")
	elseif event == "BANK_OPENED" or event == "BANK_CLOSED" then
		local bank = Bags.frames.bank
		if bank and bank:IsShown() then
			bank:Refresh() -- switches between live and offline view
		end
		if event == "BANK_OPENED" and not InCombatLockdown() then
			local slots = 0
			for _, bag in ipairs(Data:GetBankBags()) do
				slots = slots + (Data.live[bag] and Data.live[bag].size or 0)
			end
			Item:Prewarm(slots + #Bags.frames.inventory.buttons + 16)
		end
	end
end

function Bags:OnLogin()
	if not Data.active then return end
	settings = ns.db.bags
	Data:RegisterListener(OnData)

	-- create the inventory and its buttons now, out of combat, so the first open is instant
	local slots = 0
	for _, bag in ipairs(Data.inventoryBags) do
		slots = slots + (Data.live[bag] and Data.live[bag].size or 0)
	end
	Item:Prewarm(slots + 16)
	self:GetFrame("inventory", true)

	-- what the character can use changes with level, skills and spells
	local function UsabilityChanged()
		Item:ResetUsability()
		ns:Defer("bags-usability", function() Bags:UpdateItems() end)
	end
	for _, event in ipairs({"PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "LEARNED_SPELL_IN_TAB"}) do
		pcall(ns.RegisterEvent, ns, event, UsabilityChanged) -- some events may not exist in this client
	end

	ns:RegisterCommand("bags", function() Bags:Toggle("inventory") end, "Toggle the inventory")
	ns:RegisterCommand("bank", function() Bags:Toggle("bank") end, "Show your bank (offline when not at a banker)")
	ns:RegisterCommand("deposit", function() Bags:DepositReagents() end, "Deposit reagents into the bank (at a banker)")
	ns:RegisterCommand("bagtypes", function()
		-- lists what the client reports for each bag, to tune type detection
		local frame = Bags:GetFrame("inventory", true)
		local char = frame:GetCharacter()
		for _, bag in ipairs(Data.inventoryBags) do
			local data = char.bags[bag]
			if data then
				local bagType = frame:GetBagType(bag)
				print(("  %d: %s  family=%s  %s"):format(bag, data.link or (bag == 0 and BACKPACK_TOOLTIP or "-"), tostring(data.family or 0),
					bagType and (L["BAGTYPE_" .. bagType.key] or bagType.key) or L.BAGTYPE_normal))
			end
		end
	end, "List your bags and the type detected for each")
	self.active = true
end
