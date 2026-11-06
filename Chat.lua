--[[
	Chat extras
	  * copy button on every chat window: opens its messages as plain text to copy
	  * web addresses in messages become links; clicking one opens it ready to copy
	Messages that are "secret" values in this client are left untouched.
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

-- Filters run once per chat window showing the channel: the last answer is kept, and messages
-- without anything that looks like an address (nearly all) skip the word by word pass.
local lastIn, lastOut
local function Linkify(text)
	if text == lastIn then
		return lastOut
	end
	local out = text
	if text:find("://", 1, true) or text:find("www.", 1, true) or text:find("discord.gg/", 1, true) then
		out = text:gsub("(%S+)", LinkWord)
	end
	lastIn, lastOut = text, out
	return out
end

local function Filter(_, _, message, ...)
	if not settings.urls or issecretvalue(message) or type(message) ~= "string" then
		return false
	end
	local linked = Linkify(message)
	if linked ~= message then
		return false, linked, ...
	end
	return false
end

local EVENTS = {
	"CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
}


--[[ Module ]]--

function Chat:OnInitialize()
	settings = ns.db.chat
end

function Chat:OnLogin()
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
