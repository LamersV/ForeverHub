--[[
	Professions - shopping list

	Recipes and how many times to craft them, per character. A small window that
	is always visible lists the materials: what the character has (bags + bank)
	out of what is needed, which ones a vendor sells and which ones the character
	can craft. Crafting one of the recipes takes one off the list.

	At a merchant that sells missing materials, a button buys them.
--]]

local _, ns = ...
local L = ns.L
local Prof = ns.Professions

local Shopping = ns:NewModule("Shopping")

local POSITION = "ForeverHubShopping"
local ROW_HEIGHT, WIDTH, MAX_ROWS = 16, 250, 24
local GREEN, RED, GRAY, GOLD = "|cff40ff40", "|cffff5040", "|cffaaaaaa", "|cffffd200"

local settings, list
local frame, rows = nil, {}
local buyButton
local needs, order = {}, {} -- itemID -> amount; item IDs sorted by name

local function Enabled()
	return settings.shopping
end


--[[ The list ]]--

function Shopping:Add(recipeID, amount)
	local recipe = Prof:GetRecipe(recipeID)
	if not recipe then
		ns:Print(L.PROF_LIST_UNKNOWN)
		return
	end
	local count = (list[recipeID] or 0) + (amount or 1)
	list[recipeID] = count > 0 and count or nil
	ns:Print(L.PROF_LIST_ADDED:format(recipe.n or recipeID, count))
	self:Update()
end

function Shopping:Remove(recipeID, amount)
	local count = (list[recipeID] or 0) - (amount or math.huge)
	list[recipeID] = count > 0 and count or nil
	self:Update()
end

function Shopping:Clear()
	wipe(list)
	self:Update()
end

function Shopping:IsEmpty()
	return next(list) == nil
end

-- Materials of every recipe on the list.
local function SortByName(a, b)
	local nameA, nameB = Prof:ItemName(a) or "", Prof:ItemName(b) or ""
	if nameA == nameB then return a < b end
	return nameA < nameB
end

local function Compute()
	wipe(needs)
	wipe(order)
	for recipeID, count in pairs(list) do
		local recipe = Prof:GetRecipe(recipeID)
		local reagents = recipe and recipe.r or {}
		for i = 1, #reagents, 2 do
			local id = reagents[i]
			if not needs[id] then
				order[#order + 1] = id
			end
			needs[id] = (needs[id] or 0) + reagents[i + 1] * count
		end
	end
	table.sort(order, SortByName)
end

-- How many of an item the list needs in all, or nil.
function Shopping:GetNeed(itemID)
	return needs[itemID]
end

function Shopping:GetMissing(itemID)
	local need = needs[itemID]
	if not need then return 0 end
	return math.max(0, need - Prof:Count(itemID))
end


--[[ Window ]]--

local function RowEnter(row)
	GameTooltip:SetOwner(row, "ANCHOR_LEFT")
	if row.itemID then
		GameTooltip:SetItemByID(row.itemID)
	elseif row.recipeID then
		GameTooltip:SetText(row.Text:GetText())
		GameTooltip:AddLine(L.PROF_LIST_RECIPE_HINT, 0.7, 0.7, 0.7, true)
	else
		GameTooltip:SetText(L.PROF_LIST_TITLE)
		GameTooltip:AddLine(L.PROF_LIST_HINT, 0.7, 0.7, 0.7, true)
	end
	GameTooltip:Show()
end

local function RowClick(row, button)
	if row.recipeID and button == "RightButton" then
		Shopping:Remove(row.recipeID, IsShiftKeyDown() and math.huge or 1)
	elseif row.itemID and IsModifiedClick("CHATLINK") then
		local _, link = (C_Item and C_Item.GetItemInfo or GetItemInfo)(row.itemID)
		if link then
			ChatEdit_InsertLink(link)
		end
	end
end

local function GetRow(i)
	local row = rows[i]
	if row then return row end
	row = CreateFrame("Button", nil, frame)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("LEFT", 6, 0)
	row:SetPoint("RIGHT", -6, 0)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row.Icon = row:CreateTexture(nil, "ARTWORK")
	row.Icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
	row.Icon:SetPoint("LEFT")
	row.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.Count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Count:SetPoint("RIGHT")
	row.Text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.Text:SetPoint("RIGHT", row.Count, "LEFT", -4, 0)
	row.Text:SetJustifyH("LEFT")
	row.Text:SetWordWrap(false)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", RowClick)
	-- dragging a row moves the window
	row:RegisterForDrag("LeftButton")
	row:SetScript("OnDragStart", function() frame:GetScript("OnDragStart")(frame) end)
	row:SetScript("OnDragStop", function() frame:GetScript("OnDragStop")(frame) end)
	rows[i] = row
	return row
end

local function SetRow(i, text, count, icon, recipeID, itemID)
	local row = GetRow(i)
	row:SetPoint("TOP", frame, "TOP", 0, -6 - (i - 1) * ROW_HEIGHT)
	row.recipeID, row.itemID = recipeID, itemID
	row.Icon:SetShown(icon ~= nil)
	row.Icon:SetTexture(icon)
	row.Text:ClearAllPoints()
	row.Text:SetPoint("LEFT", icon and row.Icon or row, icon and "RIGHT" or "LEFT", icon and 4 or 0, 0)
	row.Text:SetPoint("RIGHT", row.Count, "LEFT", -4, 0)
	row.Text:SetText(text)
	row.Count:SetText(count or "")
	row:Show()
end

local function DefaultPoint()
	frame:ClearAllPoints()
	frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
end

local function Create()
	frame = CreateFrame("Frame", "ForeverHubShopping", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
	frame:SetBackdropColor(0, 0, 0, 0.5)
	frame:SetWidth(WIDTH)
	if not ns:ApplyPosition(ns.db.positions, POSITION, frame) then
		DefaultPoint()
	end
	frame:SetScript("OnDragStart", function(self)
		GameTooltip_Hide()
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		ns:SavePosition(ns.db.positions, POSITION, self)
	end)

	local clear = CreateFrame("Button", nil, frame, "UIPanelCloseButtonNoScripts")
	clear:SetSize(20, 20)
	clear:SetPoint("TOPRIGHT", 0, 0)
	clear:SetFrameLevel(frame:GetFrameLevel() + 5)
	clear:SetScript("OnClick", function()
		if IsShiftKeyDown() then
			Shopping:Clear()
		else
			ns:Print(L.PROF_LIST_CLEAR_HINT)
		end
	end)
	clear:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(L.PROF_LIST_CLEAR)
		GameTooltip:Show()
	end)
	clear:SetScript("OnLeave", GameTooltip_Hide)
	frame.Clear = clear
end

local function Render()
	local n = 1
	local ready = true
	for _, id in ipairs(order) do
		if Prof:Count(id) < needs[id] then
			ready = false
			break
		end
	end
	SetRow(n, GOLD .. L.PROF_LIST_TITLE .. "|r" .. (ready and ("  " .. GREEN .. L.PROF_LIST_READY .. "|r") or ""), nil)
	rows[n].Count:SetText("     ") -- room for the close button

	local recipes = {}
	for recipeID in pairs(list) do
		if Prof:GetRecipe(recipeID) then
			recipes[#recipes + 1] = recipeID
		end
	end
	table.sort(recipes, function(a, b)
		return (Prof:GetRecipe(a).n or "") < (Prof:GetRecipe(b).n or "")
	end)
	for _, recipeID in ipairs(recipes) do
		local recipe = Prof:GetRecipe(recipeID)
		n = n + 1
		SetRow(n, ("%dx %s"):format(list[recipeID], recipe.n or "?"), nil, recipe.i, recipeID)
	end

	for i, id in ipairs(order) do
		if n >= MAX_ROWS then
			n = n + 1
			SetRow(n, GRAY .. L.PROF_LIST_MORE:format(#order - i + 1) .. "|r")
			break
		end
		local need = needs[id]
		local have, inBags = Prof:Count(id)
		local name = Prof:ItemName(id) or ("item " .. id)
		local color = have >= need and GREEN or RED
		local note = ""
		if have < need then
			if Prof:IsVendorItem(id) then
				note = " " .. GRAY .. L.PROF_LIST_VENDOR .. "|r"
			elseif Prof:GetProducer(id) then
				note = " " .. GOLD .. L.PROF_LIST_CRAFT .. "|r"
			end
		elseif inBags < need then
			note = " " .. GRAY .. L.PROF_LIST_IN_BANK .. "|r"
		end
		n = n + 1
		SetRow(n, "  " .. name .. note, ("%s%d|r/%d"):format(color, math.min(have, need), need), Prof:ItemIcon(id), nil, id)
	end

	for i = n + 1, #rows do
		rows[i]:Hide()
	end
	frame:SetHeight(12 + n * ROW_HEIGHT)
end

function Shopping:Update()
	ns:Defer("shopping", function() Shopping:Refresh() end)
end

function Shopping:Refresh()
	Compute()
	local show = Enabled() and not self:IsEmpty()
	if show and not frame then
		Create()
	end
	if frame then
		frame:SetShown(show)
		if show then
			Render()
		end
	end
	self:UpdateBuyButton()
	Prof:Fire("ListChanged")
end

function Shopping:ResetPosition()
	ns.db.positions[POSITION] = nil
	if frame then
		DefaultPoint()
	end
end


--[[ Merchant ]]--

local function Missing(itemID)
	return Shopping:GetMissing(itemID)
end

function Shopping:UpdateBuyButton()
	local merchant = ns.Merchant
	if not (merchant and merchant.atMerchant and MerchantFrame) then
		if buyButton then buyButton:Hide() end
		return
	end
	local plan, total = {}, 0
	if Enabled() and not self:IsEmpty() then
		plan, total = merchant:PlanPurchase(Missing)
	end
	if #plan == 0 then
		if buyButton then buyButton:Hide() end
		return
	end
	if not buyButton then
		buyButton = ns.Widgets.CreateButton(MerchantFrame, "", 200, function()
			local bought = ns.Merchant:Buy(Missing)
			if #bought > 0 then
				ns:Print(L.PROF_LIST_BOUGHT:format(table.concat(bought, ", ")))
			else
				ns:Print(ERR_NOT_ENOUGH_MONEY or L.PROF_LIST_BUY)
			end
		end)
		buyButton:SetPoint("BOTTOMRIGHT", MerchantFrame, "TOPRIGHT", 0, 2)
		buyButton:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(L.PROF_LIST_BUY)
			for _, entry in ipairs(self.plan or {}) do
				GameTooltip:AddDoubleLine(("%dx %s"):format(entry.amount, Prof:ItemName(entry.id) or entry.id),
					GetMoneyString(entry.cost, true), 1, 1, 1, 1, 1, 1)
			end
			GameTooltip:Show()
		end)
		buyButton:SetScript("OnLeave", GameTooltip_Hide)
	end
	buyButton.plan = plan
	buyButton:SetText(L.PROF_LIST_BUY_COST:format(GetMoneyString(total, true)))
	buyButton:SetWidth(math.max(160, buyButton:GetFontString():GetStringWidth() + 24))
	-- short of money it still buys what it can, in the list's order
	buyButton:GetFontString():SetTextColor(1, GetMoney() >= total and 0.82 or 0.3, GetMoney() >= total and 0 or 0.3)
	buyButton:Show()
end

-- Remember the vendor price of every material sold here.
local function ReadMerchant()
	local merchant = ns.Merchant
	if not merchant then return end
	for i = 1, GetMerchantNumItems() do
		local id = merchant:GetItemID(i)
		if id and Prof:GetRecipesUsing(id) then
			local price = merchant:GetUnitPrice(i)
			if price then
				Prof:SetVendorPrice(id, price)
			end
		end
	end
end


--[[ Module ]]--

function Shopping:OnInitialize()
	settings = ns.db.professions
	list = Prof.list
end

function Shopping:OnLogin()
	-- one craft of a recipe on the list takes it down by one
	local casts = CreateFrame("Frame")
	casts:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	casts:SetScript("OnEvent", function(_, _, _, _, spellID)
		if not spellID or (issecretvalue and issecretvalue(spellID)) or not list[spellID] then return end
		local recipe = Prof:GetRecipe(spellID)
		Shopping:Remove(spellID, 1)
		if not list[spellID] and recipe then
			ns:Print(L.PROF_LIST_DONE:format(recipe.n or spellID))
		end
	end)

	local function Changed()
		if frame and frame:IsShown() or buyButton and buyButton:IsShown() or ns.Merchant and ns.Merchant.atMerchant then
			Shopping:Update()
		end
	end
	ns:RegisterEvent("BAG_UPDATE_DELAYED", Changed)
	ns:RegisterEvent("BANKFRAME_OPENED", Changed)
	ns:RegisterEvent("PLAYER_MONEY", Changed)
	ns:RegisterEvent("GET_ITEM_INFO_RECEIVED", function(_, itemID)
		if needs[itemID] then Changed() end
	end)
	ns:RegisterEvent("MERCHANT_SHOW", function()
		ReadMerchant()
		-- after the junk sale and the restock
		C_Timer.After(0.5, function() Shopping:Update() end)
	end)
	ns:RegisterEvent("MERCHANT_CLOSED", function()
		if buyButton then buyButton:Hide() end
	end)
	Prof:On("RecipesChanged", Changed)

	ns:RegisterCommand("lista", function(rest)
		if rest == "limpar" or rest == "clear" then
			Shopping:Clear()
		else
			settings.shopping = not settings.shopping
			Shopping:Refresh()
		end
	end, L.PROF_LIST_COMMAND)

	self:Refresh()
end
