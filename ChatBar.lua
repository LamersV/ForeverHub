--[[
	Chat bar: a button for each place to talk (say, yell, party, instance, raid, guild,
	whispers and each joined channel, like General or Trade), on the line of the chat tabs,
	at its right end: one dark strip with the thin golden border of the game's windows,
	the places split by thin lines, all of the same width, each with the channel's short
	name in its color. A click opens the chat box already set to that channel
	(whispers: answer the last one); a right-click opens a chat tab with only that channel
	(ChatTabs.lua). Buttons only show where they can be used (party when in a group...).
--]]

local _, ns = ...
local L = ns.L

local ChatBar = ns:NewModule("ChatBar")

local HEIGHT, PAD, INSET = 24, 6, 3 -- strip height; space beside each label; border inside
local MIN_WIDTH = 24
local settings
local bar
local buttons = {}

-- Fixed places to talk: chat type, short label, when it can be used.
local FIXED = {
	{"SAY", "CHAT_ABBR_SAY"},
	{"YELL", "CHAT_ABBR_YELL"},
	{"PARTY", "CHAT_ABBR_PARTY", function() return IsInGroup(LE_PARTY_CATEGORY_HOME) end},
	{"INSTANCE_CHAT", "CHAT_ABBR_INSTANCE", function() return IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end},
	{"RAID", "CHAT_ABBR_RAID", function() return IsInRaid() end},
	{"GUILD", "CHAT_ABBR_GUILD", function() return IsInGuild() end},
	{"WHISPER", "CHAT_ABBR_WHISPER"},
}

-- Functions that moved into ChatFrameUtil in newer clients.
local function ChatFunction(old, new)
	return _G[old] or (ChatFrameUtil and ChatFrameUtil[new])
end

-- Opens the chat box set to a chat type (and channel number).
local function Talk(chatType, channel)
	local choose = ChatFunction("ChatEdit_ChooseBoxForSend", "ChooseBoxForSend")
	local activate = ChatFunction("ChatEdit_ActivateChat", "ActivateChat")
	local editBox = choose and choose() or ChatFrame1EditBox
	if not editBox then return end
	if activate then
		activate(editBox)
	else
		editBox:Show()
		editBox:SetFocus()
	end
	editBox:SetAttribute("chatType", chatType)
	if channel then
		editBox:SetAttribute("channelTarget", channel)
	end
	if editBox.UpdateHeader then
		editBox:UpdateHeader()
	else
		local update = ChatFunction("ChatEdit_UpdateHeader", "UpdateHeader")
		if update then update(editBox) end
	end
end

local function Color(chatType)
	local info = ChatTypeInfo and ChatTypeInfo[chatType]
	if info then
		return info.r or 1, info.g or 1, info.b or 1
	end
	return 1, 1, 1
end

local function Paint(button, lighter)
	local r, g, b = button.r, button.g, button.b
	if lighter then
		r, g, b = r + (1 - r) * 0.5, g + (1 - g) * 0.5, b + (1 - b) * 0.5
	end
	button.Text:SetTextColor(r, g, b)
end

local function OnEnter(self)
	Paint(self, true)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText(self.title, 1, 1, 1, 1, true)
	GameTooltip:AddLine(self.chatType == "WHISPER" and L.CHAT_BAR_HINT_WHISPER or L.CHAT_BAR_HINT, nil, nil, nil, true)
	if ns.ChatTabs then
		GameTooltip:AddLine(L.CHAT_BAR_TAB, nil, nil, nil, true)
	end
	GameTooltip:Show()
end

local function OnLeave(self)
	Paint(self, false)
	GameTooltip:Hide()
end

-- Answers the last whisper (nothing happens when there was none).
local function Reply()
	local reply = ChatFunction("ChatFrame_ReplyTell", "ReplyTell")
	if reply then pcall(reply, SELECTED_CHAT_FRAME or ChatFrame1) end
end

local function OnClick(self, mouse)
	if mouse == "RightButton" then
		if ns.ChatTabs then
			ns.ChatTabs:Open(self.place)
		end
	elseif self.chatType == "WHISPER" then
		Reply()
	else
		Talk(self.chatType, self.channel)
	end
end


--[[ Look: one dark strip with a thin golden border, the places split by thin lines ]]--

local function OnMouseDown(self)
	self.Text:SetPoint("CENTER", 1, -1)
end

local function OnMouseUp(self)
	self.Text:SetPoint("CENTER", 0, 0)
end

local function GetButton(index)
	local button = buttons[index]
	if button then return button end
	button = CreateFrame("Button", nil, bar)
	button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	button.Text:SetPoint("CENTER", 0, 0)
	button.Text:SetShadowOffset(1, -1)
	-- soft light on the place under the mouse
	local light = button:CreateTexture(nil, "HIGHLIGHT")
	light:SetPoint("TOPLEFT", 1, 0)
	light:SetPoint("BOTTOMRIGHT", -1, 0)
	light:SetColorTexture(1, 1, 1, 0.12)
	-- the line on its left, between it and the next place
	local line = button:CreateTexture(nil, "ARTWORK")
	line:SetWidth(1)
	line:SetPoint("TOPLEFT", 0, -2)
	line:SetPoint("BOTTOMLEFT", 0, 2)
	line:SetColorTexture(0.8, 0.65, 0.25, 0.45)
	button.Line = line
	button:SetScript("OnMouseDown", OnMouseDown)
	button:SetScript("OnMouseUp", OnMouseUp)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", OnClick)
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", OnLeave)
	buttons[index] = button
	return button
end

local function Place(index, label, title, chatType, channel)
	local button = GetButton(index)
	button.chatType, button.channel, button.title = chatType, channel, title
	button.place = channel and ("CHANNEL:" .. channel) or chatType
	button.r, button.g, button.b = Color(channel and ("CHANNEL" .. channel) or chatType)
	button.Text:SetText(label)
	Paint(button, button:IsMouseOver())
	button:SetHeight(HEIGHT - INSET * 2)
	button:ClearAllPoints()
	if index == 1 then
		button:SetPoint("RIGHT", bar, "RIGHT", -INSET, 0)
	else
		button:SetPoint("RIGHT", buttons[index - 1], "LEFT", 0, 0)
	end
	button:Show()
end

-- All the same width (the widest label); the strip wraps them; no line left of the last one.
local function Widths(count)
	local width = MIN_WIDTH
	for index = 1, count do
		width = math.max(width, math.ceil(buttons[index].Text:GetStringWidth()) + PAD * 2)
	end
	for index = 1, count do
		buttons[index]:SetWidth(width)
		buttons[index].Line:SetShown(index < count)
	end
	bar:SetWidth(width * count + INSET * 2)
end

-- On the line of the tabs (centered on their text), its right end on the right of the chat.
local function PlaceBar()
	local chat = ChatFrame1
	if not bar or not chat then return end
	-- the right edge of the chat's box (ChatSkin.lua) or of the game's background
	local edge = ns.ChatSkin and ns.ChatSkin:WindowBox(chat)
	if not (edge and edge:GetRight()) then edge = ChatFrame1Background end
	if not (edge and edge.GetRight and edge:GetRight()) then edge = chat end
	local y = 12
	local tab = ChatFrame1Tab
	local text = tab and (tab.Text or _G[tab:GetName() .. "Text"])
	local _, centerY = (text or tab or chat):GetCenter()
	if tab and centerY and edge:GetTop() then
		y = centerY - edge:GetTop()
	end
	bar:ClearAllPoints()
	bar:SetPoint("RIGHT", edge, "TOPRIGHT", 0, y)
end

-- Joined channels, as {number, name}.
local function Channels()
	local list = {}
	local data = {GetChannelList()}
	for i = 1, #data, 3 do
		local id, name, disabled = data[i], data[i + 1], data[i + 2]
		if type(id) == "number" and type(name) == "string" and not disabled then
			list[#list + 1] = {id, name}
		end
	end
	return list
end

-- Right to left: the joined channels last, so the fixed ones keep their place.
local function Layout()
	if not bar then return end
	local entries = {}
	for _, info in ipairs(FIXED) do
		if not info[3] or info[3]() then
			local chatType = info[1]
			entries[#entries + 1] = {L[info[2]], _G["CHAT_MSG_" .. chatType] or chatType, chatType}
		end
	end
	local short = ns.ChatFrames and ns.ChatFrames.ShortChannel
	for _, channel in ipairs(Channels()) do
		local id, name = channel[1], channel[2]
		local label = short and short(ns.ChatFrames, name) or tostring(id)
		entries[#entries + 1] = {label, ("%d. %s"):format(id, name), "CHANNEL", id}
	end

	local count = #entries
	for index = 1, count do
		local entry = entries[count - index + 1]
		Place(index, entry[1], entry[2], entry[3], entry[4])
	end
	for index = count + 1, #buttons do
		buttons[index]:Hide()
	end
	Widths(count)
	bar:SetShown(settings.channelBar and count > 0)
	PlaceBar()
end

local function Update()
	ns:Defer("chat-bar", Layout)
end

function ChatBar:Refresh()
	if settings.channelBar and not bar then
		self:Create()
	end
	if bar then
		Layout()
	end
end

function ChatBar:Create()
	local dock = GeneralDockManager or ChatFrame1
	if not dock then return end
	bar = CreateFrame("Frame", "ForeverHubChatBar", dock, "BackdropTemplate")
	bar:SetSize(10, HEIGHT)
	bar:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 12, insets = {left = INSET, right = INSET, top = INSET, bottom = INSET},
	})
	bar:SetBackdropColor(0, 0, 0, 0.6)
	bar:SetBackdropBorderColor(0.8, 0.65, 0.25, 0.9)
	bar:SetFrameStrata(dock:GetFrameStrata())
	Layout()
end


--[[ Module ]]--

function ChatBar:OnInitialize()
	settings = ns.db.chat
end

function ChatBar:OnLogin()
	if settings.channelBar then
		self:Create()
	end
	for _, event in ipairs({"PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_GUILD_UPDATE",
		"CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE", "ZONE_CHANGED_NEW_AREA", "UPDATE_CHAT_COLOR"}) do
		pcall(ns.RegisterEvent, ns, event, Update)
	end
end
