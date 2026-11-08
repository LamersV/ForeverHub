--[[
	Chat tabs: a tab of the game's own, beside "General" and "Combat Log", that shows only one
	place to talk (party, guild, whispers, a channel...), with its full name.

	The tab is a normal chat window of the game (FCF_OpenNewWindow), set to receive only that
	place; the game keeps it like any other tab (close, rename, move it from its menu).
	It opens already holding what was recently said there: every line written to a chat
	window passes through ChatFrames' AddMessage wrapper, which hands it here with the event
	the game passed along, and the last lines of each place are kept per window.

	The tab button at the top right of each window opens a menu of places (checked: the tab
	exists); a right-click on a letter of the chat bar (ChatBar.lua) opens that tab.
--]]

local _, ns = ...
local L = ns.L

local ChatTabs = ns:NewModule("ChatTabs")

local issecretvalue = issecretvalue or function() return false end
local KEEP = 300 -- lines kept per window, of places that have tabs

-- Event -> place. Officer goes with guild, leaders and warnings with their group.
local EVENT_PLACE = {
	CHAT_MSG_SAY = "SAY", CHAT_MSG_YELL = "YELL",
	CHAT_MSG_PARTY = "PARTY", CHAT_MSG_PARTY_LEADER = "PARTY",
	CHAT_MSG_RAID = "RAID", CHAT_MSG_RAID_LEADER = "RAID", CHAT_MSG_RAID_WARNING = "RAID",
	CHAT_MSG_INSTANCE_CHAT = "INSTANCE_CHAT", CHAT_MSG_INSTANCE_CHAT_LEADER = "INSTANCE_CHAT",
	CHAT_MSG_GUILD = "GUILD", CHAT_MSG_OFFICER = "GUILD",
	CHAT_MSG_WHISPER = "WHISPER", CHAT_MSG_WHISPER_INFORM = "WHISPER",
	CHAT_MSG_BN_WHISPER = "WHISPER", CHAT_MSG_BN_WHISPER_INFORM = "WHISPER",
}
-- Channel link of a line ("|Hchannel:PARTY|h") -> place, for lines without an event.
local LINK_PLACE = {PARTY = "PARTY", RAID = "RAID", INSTANCE_CHAT = "INSTANCE_CHAT", GUILD = "GUILD", OFFICER = "GUILD"}

-- Fixed places: place, tab name, the game's message groups it receives.
local FIXED = {
	{"SAY", "TAB_SAY", {"SAY"}},
	{"YELL", "TAB_YELL", {"YELL"}},
	{"PARTY", "TAB_PARTY", {"PARTY", "PARTY_LEADER"}},
	{"INSTANCE_CHAT", "TAB_INSTANCE", {"INSTANCE_CHAT", "INSTANCE_CHAT_LEADER"}},
	{"RAID", "TAB_RAID", {"RAID", "RAID_LEADER", "RAID_WARNING"}},
	{"GUILD", "TAB_GUILD", {"GUILD", "OFFICER"}},
	{"WHISPER", "TAB_WHISPER", {"WHISPER", "BN_WHISPER"}},
}

local buffers = {} -- chat frame -> {lines = {}, first, count}


--[[ Which place a line belongs to ]]--

-- The event among the extra values of AddMessage (r, g, b, chat type id, access id,
-- type id, event...); searched instead of read at a fixed place.
function ChatTabs.EventOf(...)
	for i = 1, math.min(select("#", ...), 10) do
		local value = select(i, ...)
		if type(value) == "string" and not issecretvalue(value) and value:sub(1, 9) == "CHAT_MSG_" then
			return value
		end
	end
end

-- "PARTY", "GUILD", "CHANNEL:2"... or nil.
function ChatTabs.PlaceOf(text, event)
	local readable = type(text) == "string" and not issecretvalue(text)
	if readable and (event == "CHAT_MSG_CHANNEL" or not event) then
		local number = text:match("|Hchannel:[^:|]+:(%d+)|h")
		if number then return "CHANNEL:" .. number end
	end
	if event then return EVENT_PLACE[event] end
	local group = readable and text:match("|Hchannel:([%u_]+)|h")
	return group and LINK_PLACE[group]
end


--[[ Lines kept ]]--

local function Push(frame, line)
	local buffer = buffers[frame]
	if not buffer then
		buffer = {lines = {}, first = 1, count = 0}
		buffers[frame] = buffer
	end
	if buffer.count < KEEP then
		buffer.count = buffer.count + 1
		buffer.lines[(buffer.first + buffer.count - 2) % KEEP + 1] = line
	else -- full: the oldest gives its place
		buffer.lines[buffer.first] = line
		buffer.first = buffer.first % KEEP + 1
	end
end

-- Oldest first.
local function Lines(frame)
	local buffer = buffers[frame]
	local index = 0
	return function()
		if not buffer or index >= buffer.count then return end
		index = index + 1
		return buffer.lines[(buffer.first + index - 2) % KEEP + 1]
	end
end

local seen = {lines = 0, events = 0, kept = 0} -- for /fh chattabs

-- Called by ChatFrames for every line written to a chat window.
function ChatTabs:Capture(frame, text, r, g, b, ...)
	if text == nil then return end
	local event = ChatTabs.EventOf(r, g, b, ...)
	seen.lines = seen.lines + 1
	if event then
		seen.events, seen.last = seen.events + 1, event
	end
	local place = ChatTabs.PlaceOf(text, event)
	if place then
		seen.kept = seen.kept + 1
		Push(frame, {text, r, g, b, place})
	end
end


--[[ Places ]]--

local function Color(chatType)
	local info = ChatTypeInfo and ChatTypeInfo[chatType]
	if info then return info.r or 1, info.g or 1, info.b or 1 end
	return 1, 1, 1
end

-- {place, name, groups, channel, r, g, b}: the fixed places, then the channels joined.
function ChatTabs:Places()
	local list = {}
	for _, entry in ipairs(FIXED) do
		local r, g, b = Color(entry[1])
		list[#list + 1] = {place = entry[1], name = L[entry[2]], groups = entry[3], r = r, g = g, b = b}
	end
	local data = {GetChannelList()}
	for i = 1, #data, 3 do
		local id, name, disabled = data[i], data[i + 1], data[i + 2]
		if type(id) == "number" and type(name) == "string" and not disabled then
			local r, g, b = Color("CHANNEL" .. id)
			list[#list + 1] = {place = "CHANNEL:" .. id, name = name, channel = name, r = r, g = g, b = b}
		end
	end
	return list
end

function ChatTabs:Find(place)
	for _, entry in ipairs(self:Places()) do
		if entry.place == place then return entry end
	end
end


--[[ Tabs ]]--

-- Functions that moved into ChatFrameUtil in newer clients.
local function Run(old, new, ...)
	local func = _G[old] or (ChatFrameUtil and ChatFrameUtil[new])
	if func then
		local ok, result = pcall(func, ...)
		if ok then return result end
	end
end

-- The tabs this addon opened, per character: place -> {window ID, name}. A tab counts only
-- while that window is open with that name (closed, or reused by the game for another).
local function Opened()
	local key = (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
	ns.db.chatTabs = ns.db.chatTabs or {}
	ns.db.chatTabs[key] = ns.db.chatTabs[key] or {}
	return ns.db.chatTabs[key]
end

local function IsOpenWindow(id, name)
	local tabName, _, _, _, _, _, shown, _, docked = GetChatWindowInfo(id)
	return (shown or docked) and (name == nil or tabName == name)
end

local function TabOf(place)
	local saved = Opened()[place]
	if not saved then return end
	local id, name = saved[1], saved[2]
	local frame = _G["ChatFrame" .. id]
	if frame and id > 2 and IsOpenWindow(id, name) then
		return frame
	end
	Opened()[place] = nil
end

-- The channel "General" would share its name with the game's first tab.
local function FreeName(name)
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		if IsOpenWindow(i, name) then
			return L.CHAT_TAB_CHANNEL:format(name)
		end
	end
	return name
end

-- Only this place reaches the window.
local function Configure(frame, entry)
	Run("ChatFrame_RemoveAllMessageGroups", "RemoveAllMessageGroups", frame)
	Run("ChatFrame_RemoveAllChannels", "RemoveAllChannels", frame)
	for _, group in ipairs(entry.groups or {}) do
		Run("ChatFrame_AddMessageGroup", "AddMessageGroup", frame, group)
	end
	if entry.channel then
		Run("ChatFrame_AddChannel", "AddChannel", frame, entry.channel)
	end
end

-- What was recently said there, from the window that kept the most of it.
local function Fill(frame, place)
	local best, most = nil, 0
	for source in pairs(buffers) do
		if source ~= frame then
			local count = 0
			for line in Lines(source) do
				if line[5] == place then count = count + 1 end
			end
			if count > most then best, most = source, count end
		end
	end
	if not best then return end
	for line in Lines(best) do
		if line[5] == place then
			ns.ChatFrames:AddOld(frame, line[1], line[2], line[3], line[4])
		end
	end
	ns.ChatFrames:AddOld(frame, L.CHAT_HISTORY_END, 0.5, 0.5, 0.5)
end

local function Select(frame)
	if FCFDock_SelectWindow and GENERAL_CHAT_DOCK and frame.isDocked then
		pcall(FCFDock_SelectWindow, GENERAL_CHAT_DOCK, frame)
	else
		frame:Show()
	end
end

-- Opens the tab of a place (or selects it when it already exists).
function ChatTabs:Open(place)
	local entry = self:Find(place)
	if not entry then return end
	local frame = TabOf(place)
	if frame then
		Select(frame)
		return
	end
	if not FCF_OpenNewWindow then return end
	local name = entry.channel and FreeName(entry.name) or entry.name
	frame = Run("FCF_OpenNewWindow", "OpenNewWindow", name, true)
	if not (frame and frame.GetID) then
		-- some clients return nothing: the last open window with that name
		frame = nil
		for i = NUM_CHAT_WINDOWS or 10, 3, -1 do
			if IsOpenWindow(i, name) then
				frame = _G["ChatFrame" .. i]
				break
			end
		end
	end
	if not frame then
		ns:Print(L.CHAT_TABS_FULL)
		return
	end
	Opened()[place] = {frame:GetID(), name}
	Configure(frame, entry)
	ns.ChatFrames:SetupAll()
	if ns.Chat.AddButtons then ns.Chat:AddButtons() end
	self:AddButtons()
	Fill(frame, place)
	Select(frame)
end

function ChatTabs:Close(place)
	local frame = TabOf(place)
	if frame then
		Run("FCF_Close", "Close", frame)
		Opened()[place] = nil
	end
end

function ChatTabs:IsOpen(place)
	return TabOf(place) ~= nil
end


--[[ Tab button and menu ]]--

local function Colored(entry)
	return ("|cff%02x%02x%02x%s|r"):format(entry.r * 255, entry.g * 255, entry.b * 255, entry.name)
end

local function OpenMenu(button)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
	MenuUtil.CreateContextMenu(button, function(_, root)
		root:CreateTitle(L.CHAT_TABS_MENU)
		for _, entry in ipairs(ChatTabs:Places()) do
			root:CreateCheckbox(Colored(entry), function() return ChatTabs:IsOpen(entry.place) end,
				function()
					if ChatTabs:IsOpen(entry.place) then
						ChatTabs:Close(entry.place)
					else
						ChatTabs:Open(entry.place)
					end
				end)
		end
	end)
end

local tabButtons = {}

-- Beside the copy button, dim until the mouse is over it.
local function CreateButton(frame)
	local button = CreateFrame("Button", nil, frame)
	button:SetSize(16, 16)
	button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -23, -3)
	button:SetFrameLevel(frame:GetFrameLevel() + 5)
	button:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
	button:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
	button:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
	button:SetAlpha(0.35)
	button:SetScript("OnClick", OpenMenu)
	button:SetScript("OnEnter", function(self)
		self:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L.CHAT_TABS_BUTTON)
		GameTooltip:AddLine(L.CHAT_TABS_BUTTON_TIP, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		self:SetAlpha(0.35)
		GameTooltip:Hide()
	end)
	tabButtons[frame] = button
end

function ChatTabs:AddButtons()
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. i]
		if frame and i ~= 2 and not tabButtons[frame] then
			CreateButton(frame)
		end
	end
	self:Refresh()
end

function ChatTabs:Refresh()
	for _, button in pairs(tabButtons) do
		button:SetShown(ns.db.chat.filterButton)
	end
end

function ChatTabs:Debug()
	local frame = SELECTED_CHAT_FRAME or ChatFrame1
	ns:Print(L.CHAT_TABS_DEBUG:format(seen.lines, seen.events, tostring(seen.last), seen.kept))
	local counts = {}
	for line in Lines(frame) do
		counts[line[5]] = (counts[line[5]] or 0) + 1
	end
	for place, count in pairs(counts) do
		print(("  %s: %d"):format(place, count))
	end
end


--[[ Module ]]--

function ChatTabs:OnLogin()
	self:AddButtons()
	ns:RegisterCommand("chattabs", function() ChatTabs:Debug() end, "Chat tabs: what was kept from each place")
end
