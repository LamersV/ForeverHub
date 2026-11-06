--[[
	Mail:
	  - "Take all" in the inbox (money and items, mail by mail, skipping cash on
	    delivery), when the game has no such button of its own;
	  - a button beside the recipient box with this realm's characters of the same
	    faction and the latest recipients; the last one is filled in when the send
	    tab opens (selected, so typing replaces it).
--]]

local _, ns = ...
local L = ns.L

local Mail = ns:NewModule("Mail")

local settings, store
local STEP = 0.4 -- seconds between two takes: the server answers each one


--[[ Take all ]]--

local taking, takeButton

local function FreeSlots()
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local slots, family = C_Container.GetContainerNumFreeSlots(bag)
		if family == 0 then free = free + (slots or 0) end
	end
	return free
end

local function Stop(message)
	taking = false
	if takeButton then takeButton:Enable() end
	if message then ns:Print(message) end
end

local function TakeNext()
	if not taking then return end
	if not (InboxFrame and InboxFrame:IsVisible()) then return Stop() end
	for index = GetInboxNumItems(), 1, -1 do
		local _, _, _, _, money, cod, _, itemCount = GetInboxHeaderInfo(index)
		if not (cod and cod > 0) then
			if money and money > 0 then
				TakeInboxMoney(index)
				return C_Timer.After(STEP, TakeNext)
			end
			if itemCount and itemCount > 0 then
				if FreeSlots() == 0 then
					return Stop(L.MAIL_BAGS_FULL)
				end
				for attachment = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
					if GetInboxItem(index, attachment) then
						TakeInboxItem(index, attachment)
						return C_Timer.After(STEP, TakeNext)
					end
				end
			end
		end
	end
	Stop()
end

local function CreateTakeAll()
	if _G.OpenAllMail or not InboxFrame then return end -- the game's own button
	takeButton = CreateFrame("Button", nil, InboxFrame, "UIPanelButtonTemplate")
	takeButton:SetSize(110, 22)
	takeButton:SetText(L.MAIL_TAKE_ALL)
	takeButton:SetPoint("BOTTOM", InboxFrame, "BOTTOM", -10, 98)
	takeButton:SetScript("OnClick", function(self)
		self:Disable()
		taking = true
		TakeNext()
	end)
	takeButton:SetShown(settings.mailTakeAll)
end


--[[ Recipients ]]--

local function Recent()
	store.recent = store.recent or {}
	return store.recent
end

local function Remember(name)
	if type(name) ~= "string" or name == "" then return end
	local recent = Recent()
	for i = #recent, 1, -1 do
		if recent[i]:lower() == name:lower() then table.remove(recent, i) end
	end
	table.insert(recent, 1, name)
	for i = #recent, 11, -1 do recent[i] = nil end
	store.last = name
end

-- Other characters on this realm with the same faction, from the bags' saved data.
local function Alts()
	local list, faction = {}, UnitFactionGroup("player")
	local chars = ns.db.realms and ns.db.realms[GetRealmName()] or {}
	for name, char in pairs(chars) do
		if name ~= UnitName("player") and (not char.faction or char.faction == faction) then
			list[#list + 1] = name
		end
	end
	table.sort(list)
	return list
end

local function Pick(name)
	SendMailNameEditBox:SetText(name)
	if SendMailSubjectEditBox then SendMailSubjectEditBox:SetFocus() end
end

local function CreateRecipients()
	local box = SendMailNameEditBox
	if not box then return end
	local button = CreateFrame("Button", nil, box)
	button:SetSize(22, 22)
	button:SetPoint("LEFT", box, "RIGHT", 2, 0)
	button:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
	button:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Down")
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	button:SetScript("OnClick", function(self)
		MenuUtil.CreateContextMenu(self, function(_, root)
			root:SetTag("MENU_FOREVERHUB_MAIL")
			local alts, recent = Alts(), Recent()
			if #alts > 0 then
				root:CreateTitle(L.MAIL_ALTS)
				for _, name in ipairs(alts) do
					root:CreateButton(name, function() Pick(name) end)
				end
			end
			if #recent > 0 then
				root:CreateTitle(L.MAIL_RECENT)
				for _, name in ipairs(recent) do
					root:CreateButton(name, function() Pick(name) end)
				end
			end
			if #alts == 0 and #recent == 0 then
				root:CreateTitle(L.MAIL_NONE)
			end
		end)
	end)
	ns.Widgets.AttachTooltip(button, L.MAIL_PICK_TIP, L.MAIL_PICK)
	Mail.recipientButton = button
	button:SetShown(settings.mailRecipients)

	-- the last recipient, selected so that typing replaces it
	if SendMailFrame then
		SendMailFrame:HookScript("OnShow", function()
			if settings.mailRecipients and store.last and box:GetText() == "" then
				box:SetText(store.last)
				box:HighlightText()
			end
		end)
	end
end


--[[ Module ]]--

function Mail:Refresh()
	if takeButton then takeButton:SetShown(settings.mailTakeAll) end
	if self.recipientButton then self.recipientButton:SetShown(settings.mailRecipients) end
end

function Mail:OnInitialize()
	settings = ns.db.qol
	local realm = GetRealmName()
	ns.db.mail = ns.db.mail or {}
	ns.db.mail[realm] = ns.db.mail[realm] or {}
	store = ns.db.mail[realm]
end

function Mail:OnLogin()
	local pending
	for _, func in ipairs({"SendMail"}) do
		if _G[func] then
			hooksecurefunc(func, function(name) pending = name end)
		end
	end
	if C_Mail and C_Mail.SendMail then
		hooksecurefunc(C_Mail, "SendMail", function(name) pending = name end)
	end
	ns:RegisterEvent("MAIL_SEND_SUCCESS", function()
		Remember(pending)
		pending = nil
	end)
	ns:RegisterEventOnce("MAIL_SHOW", function()
		CreateTakeAll()
		CreateRecipients()
	end)
	ns:RegisterEvent("MAIL_CLOSED", function() Stop() end)
end
