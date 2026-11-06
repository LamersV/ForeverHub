--[[
	Chat extras
	  * copy button on every chat window: opens its messages as plain text to copy
	  * web addresses in messages become links; clicking one opens it ready to copy
	  * item links get their icon, item level and the upgrade over what is worn
	  * the character's name and chosen words are colored, with a sound
	Messages that are "secret" values in this client are left untouched.
	ChatFrames.lua: link tooltips, short channel names, history, arrows, Alt+click, look.
	ChatBar.lua: buttons to talk in each channel.
--]]

local _, ns = ...
local L, W = ns.L, ns.Widgets

local Chat = ns:NewModule("Chat")

local issecretvalue = issecretvalue or function() return false end
local settings
local copy -- copy window, built on first use
local buttons = {}


--[[ Copy window ]]--

local function CreateCopy()
	copy = W.CreateWindow("ForeverHubCopyFrame", UIParent, ns.db.positions, true)
	copy:SetSize(600, 420)
	copy:RestorePosition("CENTER", 0, 40)

	local scroll = W.CreateWithTemplates("ScrollFrame", nil, copy, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 14, -32)
	scroll:SetPoint("BOTTOMRIGHT", -32, 14)

	-- like the error window: the edit box is the scroll child, with an explicit width
	local edit = CreateFrame("EditBox", nil, scroll)
	scroll:SetScrollChild(edit)
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetMaxLetters(0)
	edit:SetFontObject(ChatFontNormal)
	edit:SetWidth(copy:GetWidth() - 46)
	edit:SetScript("OnEscapePressed", function() copy:Hide() end)
	edit:SetScript("OnTextChanged", function(self, userInput)
		if userInput then -- read-only
			self:SetText(copy.text)
			self:HighlightText()
		end
	end)
	scroll:HookScript("OnSizeChanged", function(_, width)
		if width and width > 0 then
			edit:SetWidth(width)
		end
	end)

	copy.Edit, copy.Scroll = edit, scroll
end

-- Opens text selected for Ctrl+C. height: window height; toBottom: scroll to the end.
function Chat:OpenCopy(title, text, height, toBottom)
	if not copy then
		CreateCopy()
	end
	W.SetTitle(copy, title)
	copy:SetHeight(height or 420)
	copy.text = text
	copy:Show()
	copy:Raise() -- above the error window when opened from it
	copy.Edit:SetText(text)
	copy.Edit:SetFocus()
	copy.Edit:HighlightText()
	C_Timer.After(0, function()
		copy.Scroll:SetVerticalScroll(toBottom and copy.Scroll:GetVerticalScrollRange() or 0)
	end)
end


--[[ Chat text ]]--

-- Removes colors, textures and link markup, keeping the visible text.
local function Plain(text)
	text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
	text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|K.-|k", "?")
	return text
end

local function ChatText(chatFrame)
	local lines = {}
	for i = 1, chatFrame:GetNumMessages() do
		local text = chatFrame:GetMessageInfo(i)
		if text and not issecretvalue(text) and type(text) == "string" then
			lines[#lines + 1] = Plain(text)
		end
	end
	return table.concat(lines, "\n")
end

local function CopyChat(chatFrame)
	local name = GetChatWindowInfo and GetChatWindowInfo(chatFrame:GetID()) or chatFrame:GetName()
	Chat:OpenCopy(L.CHAT_COPY_TITLE:format(name or ""), ChatText(chatFrame), nil, true)
end


--[[ Copy buttons ]]--

local function CreateButton(chatFrame)
	local button = CreateFrame("Button", nil, chatFrame)
	button:SetSize(18, 18)
	button:SetPoint("TOPRIGHT", chatFrame, "TOPRIGHT", -2, -2)
	button:SetFrameLevel(chatFrame:GetFrameLevel() + 5)
	button:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	button:SetAlpha(0.35)
	button:SetScript("OnClick", function() CopyChat(chatFrame) end)
	button:SetScript("OnEnter", function(self)
		self:SetAlpha(1)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L.CHAT_COPY)
		GameTooltip:Show()
	end)
	button:SetScript("OnLeave", function(self)
		self:SetAlpha(0.35)
		GameTooltip:Hide()
	end)
	buttons[#buttons + 1] = button
end

function Chat:Refresh()
	for _, button in ipairs(buttons) do
		button:SetShown(settings.copyButton)
	end
end


--[[ Web links ]]--

local function Link(url)
	return ("|cff4fc3f7|Haddon:ForeverHub:url:%s|h[%s]|h|r"):format(url, url)
end

local function LinkWord(word)
	if word:find("|", 1, true) then return end -- already markup (item links, colors)
	if word:match("^https?://%S+") or word:match("^www%.%S+%.%S+") or word:match("^discord%.gg/%S+") then
		return Link(word)
	end
end

-- Messages without anything that looks like an address (nearly all) skip the word by word pass.
local function Linkify(text)
	if text:find("://", 1, true) or text:find("www.", 1, true) or text:find("discord.gg/", 1, true) then
		return (text:gsub("(%S+)", LinkWord))
	end
	return text
end


--[[ Item links: icon, item level and upgrade ]]--

local GetItemIconByID = C_Item.GetItemIconByID or GetItemIcon
local GetDetailedItemLevelInfo = C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
local IsEquippableItem = C_Item.IsEquippableItem or IsEquippableItem

-- "[Name]" becomes "icon [Name] (level)", with the upgrade over what is worn after it. The
-- link itself is left as it was: Shift+click pastes it into the chat, and the server
-- checks the names of the links it gets.
local function ItemLink(payload, name)
	local itemID = tonumber(payload:match("^(%d+)"))
	if not itemID then return end
	local icon = GetItemIconByID and GetItemIconByID(itemID)
	local prefix = icon and ("|T%s:0|t"):format(icon) or ""
	local level, upgrade = "", ""
	local item = "item:" .. payload
	if IsEquippableItem and IsEquippableItem(itemID) then
		local value = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(item)
		if type(value) == "number" and value > 1 then
			level = (" (%d)"):format(value)
		end
		local Upgrade = ns.Upgrade
		if Upgrade and Upgrade.Compare then
			local ok, result = pcall(Upgrade.Compare, Upgrade, item)
			-- not "ok and Format()": "and" would keep only the text, without the color
			local text, r, g, b
			if ok then
				text, r, g, b = Upgrade:Format(result)
			end
			if text and text ~= "=" and r then
				upgrade = (" |cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
			end
		end
	end
	return ("%s|Hitem:%s|h[%s]|h%s%s"):format(prefix, payload, name, level, upgrade)
end

local function EnrichItems(text)
	if not text:find("|Hitem:", 1, true) then return text end
	return (text:gsub("|Hitem:([^|]+)|h%[(.-)%]|h", ItemLink))
end


--[[ Highlight: the character's name and chosen words ]]--

local HIGHLIGHT_REPLACE = "|cffff9a1f%0|r" -- gsub replacement: the match, colored
local HIGHLIGHT_EVENTS = {
	CHAT_MSG_SAY = true, CHAT_MSG_YELL = true, CHAT_MSG_PARTY = true, CHAT_MSG_PARTY_LEADER = true,
	CHAT_MSG_RAID = true, CHAT_MSG_RAID_LEADER = true, CHAT_MSG_RAID_WARNING = true, CHAT_MSG_GUILD = true,
	CHAT_MSG_OFFICER = true, CHAT_MSG_CHANNEL = true, CHAT_MSG_INSTANCE_CHAT = true,
	CHAT_MSG_INSTANCE_CHAT_LEADER = true,
}
local patterns = {} -- a pattern for each word, letters in either case
local playerName

-- Letters match in either case (accented letters as written); magic characters are escaped.
local function Caseless(word)
	word = word:gsub("%p", "%%%0")
	return (word:gsub("%a", function(c) return "[" .. c:lower() .. c:upper() .. "]" end))
end

function Chat:UpdateKeywords()
	wipe(patterns)
	playerName = UnitName("player")
	if playerName and not issecretvalue(playerName) then
		patterns[#patterns + 1] = Caseless(playerName)
	end
	for word in (settings.keywords or ""):gmatch("[^,;]+") do
		word = strtrim(word)
		if #word >= 2 then
			patterns[#patterns + 1] = Caseless(word)
		end
	end
end

local hit
local function Mark(segment)
	for i = 1, #patterns do
		local count
		segment, count = segment:gsub(patterns[i], HIGHLIGHT_REPLACE)
		if count > 0 then hit = true end
	end
	return segment
end

-- Words are colored only outside links, icons and color codes, which they would break.
local SKIP = {"|H.-|h.-|h", "|T.-|t", "|A.-|a", "|c%x%x%x%x%x%x%x%x", "|cn[^:]*:"}
local parts = {}
local function Highlight(text)
	local any = false
	for i = 1, #patterns do
		if text:find(patterns[i]) then any = true break end
	end
	if not any then return text, false end
	hit = false
	wipe(parts)
	local position = 1
	while true do
		local first, last
		for _, pattern in ipairs(SKIP) do
			local s, e = text:find(pattern, position)
			if s and (not first or s < first) then first, last = s, e end
		end
		if not first then
			parts[#parts + 1] = Mark(text:sub(position))
			break
		end
		parts[#parts + 1] = Mark(text:sub(position, first - 1))
		parts[#parts + 1] = text:sub(first, last)
		position = last + 1
	end
	return table.concat(parts), hit
end

local lastSound = 0
local function Alert()
	if not settings.highlightSound or GetTime() - lastSound < 2 then return end
	lastSound = GetTime()
	PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175, "Master")
end

local function IsMe(author)
	if not author or author == "" then return false end
	return Ambiguate(author, "short") == playerName
end


--[[ Message filter ]]--

-- Filters run once per chat window showing the channel: the answer for the last message is
-- kept (and the sound plays once, for a new message only).
local lastIn, lastEvent, lastAuthor, lastOut

local function Process(event, message, author)
	local out, alert = message, false
	if settings.urls then
		out = Linkify(out)
	end
	if settings.itemInfo then
		out = EnrichItems(out)
	end
	if settings.highlight and #patterns > 0 and HIGHLIGHT_EVENTS[event] and not IsMe(author) then
		out, alert = Highlight(out)
	end
	return out, alert
end

local function Filter(_, event, message, author, ...)
	if issecretvalue(message) or type(message) ~= "string" then
		return false
	end
	local who = not issecretvalue(author) and author or nil
	if message ~= lastIn or event ~= lastEvent or who ~= lastAuthor then
		local alert
		lastOut, alert = Process(event, message, who)
		lastIn, lastEvent, lastAuthor = message, event, who
		if alert then
			Alert()
		end
	end
	if lastOut ~= message then
		return false, lastOut, author, ...
	end
	return false
end

local EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_LOOT",
}


--[[ Module ]]--

function Chat:OnInitialize()
	settings = ns.db.chat
end

function Chat:OnLogin()
	self:UpdateKeywords()
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local chatFrame = _G["ChatFrame" .. i]
		if chatFrame then
			CreateButton(chatFrame)
		end
	end
	self:Refresh()

	local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
	if addFilter then
		for _, event in ipairs(EVENTS) do
			addFilter(event, Filter)
		end
	end

	EventRegistry:RegisterCallback("SetItemRef", function(_, link)
		local url = link:match("^addon:ForeverHub:url:(.+)$")
		if url then
			Chat:OpenCopy(L.CHAT_LINK_TITLE, url, 110)
		end
	end, Chat)

	ns:RegisterCommand("copychat", function() CopyChat(SELECTED_CHAT_FRAME or ChatFrame1) end, "Copy the text of the chat window")
end
