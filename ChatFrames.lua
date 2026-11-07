--[[
	Chat windows
	  * tooltips when the mouse is over a link (items, spells, quests, achievements...)
	  * short channel names: [2. Trade - City] -> [T], [Party] -> [P]
	  * the last lines of each window come back after /reload and login, and so does
	    what was typed
	  * the arrow keys go through what was typed, without Alt
	  * Alt+click on a name invites that player
	  * the look of the minimap: dark background and the border of the game's dialogs,
	    the side buttons hidden, tabs only with the mouse over them
	Secret lines (in dungeons and raids) are shown as they come and never saved.
--]]

local _, ns = ...
local L = ns.L

local ChatFrames = ns:NewModule("ChatFrames")

local issecretvalue = issecretvalue or function() return false end
local settings
local HISTORY_LINES = 80 -- per window
local TYPED_LINES = 40

local hiddenParent = CreateFrame("Frame")
hiddenParent:Hide()

-- Functions that moved into ChatFrameUtil in newer clients.
local function ChatFunction(old, new)
	return _G[old] or (ChatFrameUtil and ChatFrameUtil[new])
end

-- The combat log window (always ChatFrame2) is left as the game draws it.
local function IsCombatLogFrame(frame)
	return frame == _G.COMBATLOG or (frame.GetName and frame:GetName() == "ChatFrame2")
end


--[[ Link tooltips ]]--

local TIP_KINDS = {
	item = true, spell = true, enchant = true, quest = true, achievement = true, talent = true,
	currency = true, instancelock = true, mount = true, transmogappearance = true,
}

local function LinkEnter(frame, link)
	if not settings.tooltips or issecretvalue(link) or type(link) ~= "string" then return end
	local kind = link:match("^(%a+):")
	if not kind or not TIP_KINDS[kind] then return end
	GameTooltip:SetOwner(frame, "ANCHOR_CURSOR_RIGHT", 12, 4)
	if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
		GameTooltip:Show()
	else
		GameTooltip:Hide()
	end
end

local function LinkLeave(frame)
	if GameTooltip:IsOwned(frame) then
		GameTooltip:Hide()
	end
end


--[[ Short channel names ]]--

local shortByName -- full channel name ("Party", "Party Leader"...) -> short
local letters = {} -- short -> channel it was given to
local shortByBase = {}

-- First letter of a channel's name (two when another channel took it).
function ChatFrames:ShortChannel(base)
	local short = shortByBase[base]
	if short then return short end
	local first = base:match("^[%z\1-\127\194-\244][\128-\191]*") or base
	short = first:upper()
	if letters[short] and letters[short] ~= base then
		local second = base:match("^[%z\1-\127\194-\244][\128-\191]*([%z\1-\127\194-\244][\128-\191]*)") or ""
		short = first:upper() .. second:lower()
	end
	letters[short] = letters[short] or base
	shortByBase[base] = short
	return short
end

local function BuildShortNames()
	shortByName = {}
	local fixed = {
		{CHAT_MSG_SAY, L.CHAT_ABBR_SAY}, {CHAT_MSG_YELL, L.CHAT_ABBR_YELL},
		{CHAT_MSG_PARTY, L.CHAT_ABBR_PARTY}, {CHAT_MSG_PARTY_LEADER, L.CHAT_ABBR_PARTY_LEADER},
		{CHAT_MSG_RAID, L.CHAT_ABBR_RAID}, {CHAT_MSG_RAID_LEADER, L.CHAT_ABBR_RAID_LEADER},
		{CHAT_MSG_RAID_WARNING, L.CHAT_ABBR_RAID_WARNING}, {CHAT_MSG_GUILD, L.CHAT_ABBR_GUILD},
		{CHAT_MSG_OFFICER, L.CHAT_ABBR_OFFICER}, {CHAT_MSG_INSTANCE_CHAT, L.CHAT_ABBR_INSTANCE},
		{CHAT_MSG_INSTANCE_CHAT_LEADER, L.CHAT_ABBR_INSTANCE_LEADER},
	}
	for _, pair in ipairs(fixed) do
		if type(pair[1]) == "string" then
			shortByName[pair[1]] = pair[2]
			letters[pair[2]] = pair[1]
		end
	end
end

-- "2. Trade - City" -> "T"; "Party" -> "P".
local function Short(name)
	local fixed = shortByName[name]
	if fixed then return fixed end
	local rest = name:match("^%d+%.%s*(.+)$")
	if not rest then return name end
	local base = rest:match("^(.-)%s+%-%s+.+$") or rest
	return ChatFrames:ShortChannel(base)
end

local function ShortLink(prefix, name)
	return prefix .. "[" .. Short(name) .. "]|h"
end

local function Shorten(text)
	if not text:find("|Hchannel:", 1, true) then return text end
	return (text:gsub("(|Hchannel:[^|]*|h)%[([^%]]*)%]|h", ShortLink))
end

-- The chat frame writes every line through AddMessage: the channel names are made
-- short there (secret lines pass untouched).
local restoring = false -- history and typed text being put back

local function WrapAddMessage(frame)
	local original = frame.AddMessage
	frame.AddMessage = function(self, text, ...)
		if not issecretvalue(text) and type(text) == "string" then
			if settings.shortChannels then
				text = Shorten(text)
			end
			-- restored history already has them
			if not restoring and ns.ChatNames then
				text = ns.ChatNames.Decorate(text)
			end
		end
		return original(self, text, ...)
	end
end


--[[ History ]]--

local function CharacterKey()
	return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end

local function SaveHistory()
	if not settings.history then return end
	local store = {}
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. i]
		if frame and not IsCombatLogFrame(frame) and frame.GetNumMessages then
			local lines = {}
			local count = frame:GetNumMessages()
			for index = math.max(1, count - HISTORY_LINES + 1), count do
				local text, r, g, b = frame:GetMessageInfo(index)
				if type(text) == "string" and not issecretvalue(text) and text ~= "" then
					lines[#lines + 1] = {text, r or 1, g or 1, b or 1}
				end
			end
			if #lines > 0 then
				store[i] = lines
			end
		end
	end
	ns.db.chatHistory = ns.db.chatHistory or {}
	ns.db.chatHistory[CharacterKey()] = store
end

local function RestoreHistory()
	local all = ns.db.chatHistory
	local store = settings.history and all and all[CharacterKey()]
	if type(store) ~= "table" then return end
	restoring = true
	for i, lines in pairs(store) do
		local frame = _G["ChatFrame" .. i]
		if frame and type(lines) == "table" and #lines > 0 then
			for _, line in ipairs(lines) do
				if type(line) == "table" and type(line[1]) == "string" then
					frame:AddMessage(line[1], line[2], line[3], line[4])
				end
			end
			frame:AddMessage(L.CHAT_HISTORY_END, 0.5, 0.5, 0.5)
		end
	end
	restoring = false
end

-- What was typed: kept across sessions, put back in every edit box.
local function SaveTyped(_, text)
	if restoring or not settings.history or type(text) ~= "string" or issecretvalue(text) or text == "" then return end
	local typed = ns.db.chatTyped or {}
	ns.db.chatTyped = typed
	if typed[#typed] ~= text then
		typed[#typed + 1] = text
		while #typed > TYPED_LINES do
			table.remove(typed, 1)
		end
	end
end

local function RestoreTyped(editBox)
	local typed = settings.history and ns.db.chatTyped
	if type(typed) ~= "table" or not editBox.AddHistoryLine then return end
	restoring = true
	for _, text in ipairs(typed) do
		pcall(editBox.AddHistoryLine, editBox, text)
	end
	restoring = false
end


--[[ Arrow keys ]]--

local function ApplyArrows(editBox)
	if settings.arrows and editBox.SetAltArrowKeyMode then
		editBox:SetAltArrowKeyMode(false)
	end
end


--[[ Alt+click on a name: invite ]]--

local closeTellAt

local function OnItemRef(_, link, _, button)
	if not settings.altInvite or button ~= "LeftButton" or not IsAltKeyDown()
		or IsShiftKeyDown() or IsControlKeyDown() then return end
	if issecretvalue(link) or type(link) ~= "string" then return end
	local name = link:match("^player:([^:]+)")
	if not name or name == "" then return end
	local invite = C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
	if invite then
		invite(name)
		closeTellAt = GetTime() -- the same click opens a whisper to them: closed right after
	end
end

local function AfterSendTell()
	if closeTellAt ~= GetTime() then return end
	closeTellAt = nil
	local getActive = ChatFunction("ChatEdit_GetActiveWindow", "GetActiveWindow")
	local editBox = getActive and getActive()
	if not editBox then return end
	editBox:SetText("")
	local deactivate = ChatFunction("ChatEdit_DeactivateChat", "DeactivateChat")
	if deactivate then
		pcall(deactivate, editBox)
	else
		editBox:ClearFocus()
	end
end


--[[ Look ]]--

local SIDE_BUTTONS = {"ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
	"ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton"}

local function HideSideButtons(frame)
	local buttonFrame = frame.buttonFrame or _G[frame:GetName() .. "ButtonFrame"]
	if buttonFrame then
		buttonFrame:SetParent(hiddenParent)
	end
end


--[[ Windows ]]--

local done = {}

local function SetupFrame(frame)
	if done[frame] then return end
	done[frame] = true
	frame:HookScript("OnHyperlinkEnter", LinkEnter)
	frame:HookScript("OnHyperlinkLeave", LinkLeave)
	if not IsCombatLogFrame(frame) then
		WrapAddMessage(frame)
	end
	if settings.hideButtons then
		HideSideButtons(frame)
	end
	local editBox = frame.editBox or _G[frame:GetName() .. "EditBox"]
	if editBox and not done[editBox] then
		done[editBox] = true
		ApplyArrows(editBox)
		editBox:HookScript("OnEditFocusGained", ApplyArrows)
		if editBox.AddHistoryLine then
			RestoreTyped(editBox)
			hooksecurefunc(editBox, "AddHistoryLine", SaveTyped)
		end
	end
end

local function SetupAll()
	for _, name in ipairs(CHAT_FRAMES or {}) do
		local frame = _G[name]
		if frame then SetupFrame(frame) end
	end
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. i]
		if frame then SetupFrame(frame) end
	end
end

function ChatFrames:Refresh()
	for frame in pairs(done) do
		if frame.SetAltArrowKeyMode then
			frame:SetAltArrowKeyMode(not settings.arrows)
		end
	end
end


--[[ Module ]]--

function ChatFrames:OnInitialize()
	settings = ns.db.chat
end

function ChatFrames:OnLogin()
	BuildShortNames()
	SetupAll()
	RestoreHistory()

	-- whisper windows opened later
	if FCF_OpenTemporaryWindow then
		hooksecurefunc("FCF_OpenTemporaryWindow", function() ns:Defer("chat-frames", SetupAll) end)
	end

	if settings.hideButtons then
		for _, name in ipairs(SIDE_BUTTONS) do
			local button = _G[name]
			if button then
				button:SetParent(hiddenParent)
			end
		end
	end
	if settings.fadeTabs then
		CHAT_FRAME_TAB_NORMAL_NOMOUSE_ALPHA = 0
		CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0
	end

	EventRegistry:RegisterCallback("SetItemRef", OnItemRef, ChatFrames)
	if ChatFrame_SendTell then
		hooksecurefunc("ChatFrame_SendTell", AfterSendTell)
	elseif ChatFrameUtil and ChatFrameUtil.SendTell then
		hooksecurefunc(ChatFrameUtil, "SendTell", AfterSendTell)
	end

	ns:RegisterEvent("PLAYER_LOGOUT", SaveHistory)
end
