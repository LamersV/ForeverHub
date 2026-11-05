--[[
	Errors - window and notifications
	The window is only built the first time it is opened.
--]]

local _, ns = ...
local L = ns.L
local W = ns.Widgets
local Errors = ns.Errors

local Window = ns:NewModule("ErrorWindow")

local filter = "current"
local list, index = {}, 0
local frame
local linked = setmetatable({}, {__mode = "v"}) -- chat link id -> error


--[[ Formatting ]]--

local function Clean(text)
	text = text:gsub("Interface[/\\]AddOns[/\\]", "")
	return (text:gsub("|", "||"))
end

local function Colorize(text)
	text = text:gsub("([%w_%-%.!/\\]+%.lua)(%]?):(%d+)", "|cffffd200%1|r%2:|cff80ff80%3|r")
	return text
end

local function Format(err, colored)
	local header = Clean(err.message)
	local meta = ("%s  ·  %s"):format(date("%d/%m %H:%M:%S", err.time), L.ERROR_COUNTER:format(err.count))
	local stack = err.stack and Clean(err.stack)
	local locals = ns.db.errors.showLocals and err.locals and Clean(err.locals)

	if colored then
		header = "|cffff7070" .. Colorize(header) .. "|r"
		meta = "|cff999999" .. meta .. "|r"
		stack = stack and "|cffc8c8c8" .. Colorize(stack) .. "|r"
		locals = locals and "|cff7fb2ff" .. L.LOCALS .. ":|r\n|cffb0b0b0" .. locals .. "|r"
	elseif locals then
		locals = L.LOCALS .. ":\n" .. locals
	end

	local text = header .. "\n" .. meta
	if stack then
		text = text .. "\n\n" .. stack
	end
	if locals then
		text = text .. "\n\n" .. locals
	end
	return text
end


--[[ Window ]]--

local function Refresh()
	if not frame or not frame:IsShown() then return end

	local err = list[index]
	frame.colored = err and Format(err, true) or L.ERROR_NONE
	frame.plain = err and Format(err, false) or ""
	frame.Text:SetText(frame.Text:HasFocus() and frame.plain or frame.colored)
	frame.Text:SetCursorPosition(0)
	frame.Scroll:SetVerticalScroll(0)

	frame.Index:SetText(#list > 0 and L.ERROR_INDEX:format(index, #list) or "")
	frame.Prev:SetEnabled(index > 1)
	frame.Next:SetEnabled(index < #list)
	for key, tab in pairs(frame.Tabs) do
		tab:SetEnabled(key ~= filter)
	end
	local counts = L.ERRORS_COUNT:format(Errors:CountSession()) .. " · " .. L.ERRORS_TOTAL:format(Errors:CountAll())
	W.SetTitle(frame, ("%s%s|r %s  |cffaaaaaa(%s)|r"):format(ns.color, ns.name, L.ERRORS_TITLE, counts))
end

local function Reload(jumpToEnd)
	list = Errors:GetErrors(filter)
	if jumpToEnd or index > #list or index < 1 then
		index = #list
	end
	Refresh()
end

local function Build()
	frame = W.CreateWindow("ForeverHubErrorFrame", UIParent, ns.db.positions, true)
	frame:SetSize(620, 440)
	frame:RestorePosition("CENTER", 0, 60)

	-- session filter tabs
	frame.Tabs = {}
	local tabs = {{"current", L.SESSION_CURRENT}, {"previous", L.SESSION_PREVIOUS}, {"all", L.SESSION_ALL}}
	local anchor
	for _, info in ipairs(tabs) do
		local tab = W.CreateButton(frame, info[2], 90, function()
			filter = info[1]
			Reload(true)
		end)
		if anchor then
			tab:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
		else
			tab:SetPoint("TOPLEFT", 14, -30)
		end
		frame.Tabs[info[1]] = tab
		anchor = tab
	end

	local locals = W.CreateCheck(frame, L.LOCALS,
		function() return ns.db.errors.showLocals end,
		function(value) ns.db.errors.showLocals = value; Refresh() end)
	locals:SetPoint("TOPRIGHT", -70, -28)

	-- text area: the edit box itself is the scroll child, with an explicit width, so
	-- it grows with its text (a wrapper frame stays 1px tall and clips everything)
	local scroll = W.CreateWithTemplates("ScrollFrame", nil, frame, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 14, -60)
	scroll:SetPoint("BOTTOMRIGHT", -32, 42)
	frame.Scroll = scroll

	local text = CreateFrame("EditBox", nil, scroll)
	scroll:SetScrollChild(text)
	text:SetMultiLine(true)
	text:SetAutoFocus(false)
	text:SetMaxLetters(0)
	text:EnableMouse(true)
	text:SetFontObject(GameFontHighlightSmall)
	text:SetTextColor(1, 1, 1, 1)
	text:SetWidth(frame:GetWidth() - 46)
	text:SetTextInsets(2, 2, 2, 2)
	scroll:HookScript("OnSizeChanged", function(_, width)
		if width and width > 0 then
			text:SetWidth(width)
		end
	end)
	text:SetScript("OnEscapePressed", text.ClearFocus)
	text:SetScript("OnTextChanged", function(self, userInput)
		if userInput then
			self:SetText(frame.plain) -- read-only
			self:HighlightText()
		end
	end)
	text:SetScript("OnEditFocusGained", function(self)
		self:SetText(frame.plain)
		self:HighlightText()
	end)
	text:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		self:SetText(frame.colored)
	end)
	W.AttachTooltip(text, L.CLICK_TO_COPY)
	text.tooltipAnchor = "ANCHOR_CURSOR"
	frame.Text = text

	-- bottom bar
	frame.Prev = W.CreateButton(frame, "<", 40, function()
		index = index - 1
		Refresh()
	end)
	frame.Prev:SetPoint("BOTTOMLEFT", 14, 12)

	frame.Next = W.CreateButton(frame, ">", 40, function()
		index = index + 1
		Refresh()
	end)
	frame.Next:SetPoint("LEFT", frame.Prev, "RIGHT", 4, 0)

	frame.Index = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	frame.Index:SetPoint("LEFT", frame.Next, "RIGHT", 12, 0)

	local clear = W.CreateButton(frame, L.CLEAR, 90, function()
		Errors:Clear()
		ns:Print(L.ERRORS_CLEARED)
	end)
	clear:SetPoint("BOTTOMRIGHT", -14, 12)

	frame:SetScript("OnShow", function() Reload(true) end)
end

function Window:Open(err)
	if not frame then
		Build()
	end
	if err then
		filter = err.session == Errors:GetSession() and "current" or "all"
	end
	frame:Show()
	Reload(true)
	if err then
		for i, e in ipairs(list) do
			if e == err then
				index = i
				break
			end
		end
		Refresh()
	end
end

function Window:Toggle()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		self:Open()
	end
end


--[[ Notifications ]]--

local function ChatLink(err)
	local id = tostring(err):match("0x%x+") or tostring(err):sub(8)
	linked[id] = err
	return ("|Haddon:ForeverHub:err:%s|h|cffff4040[%s]|r|h"):format(id, L.ERRORS_TITLE)
end

local lastChat = 0

local function OnError(err, isNew)
	if frame and frame:IsShown() then
		Reload(err ~= nil and index == #list)
	end
	if not err or not isNew then return end

	local settings = ns.db.errors
	local now = GetTime()
	if settings.chat and now - lastChat > 2 then
		lastChat = now
		local first = err.message:gsub("Interface[/\\]AddOns[/\\]", ""):match("^[^\n]*"):sub(1, 120)
		ns:Print(L.ERROR_CAUGHT:format(ChatLink(err) .. " |cffaaaaaa" .. first:gsub("|", "||") .. "|r"))
	end
	if settings.sound then
		PlaySound(SOUNDKIT.RAID_WARNING or 8959, "Master")
	end
	if settings.popup and not (frame and frame:IsShown()) then
		Window:Open(err)
	end
end

function Window:OnInitialize()
	if not Errors:IsActive() or not ns.db.modules.errors then return end

	Errors:RegisterListener(OnError)

	EventRegistry:RegisterCallback("SetItemRef", function(_, link)
		local id = link:match("^addon:ForeverHub:err:(.+)$")
		if id then
			Window:Open(linked[id])
		end
	end)

	local function Open() Window:Toggle() end
	ns:RegisterCommand("errors", Open, "Open the error window")
	ns:RegisterCommand("bugs", Open, "Open the error window")
	ns:RegisterCommand("test", function() error("ForeverHub test error") end, "Raise a test error")
end

function Window:OnLogin()
	-- Errors raised while loading are announced once the chat is ready.
	if not Errors:IsActive() then return end
	local count = Errors:CountSession()
	if count > 0 and ns.db.errors.chat then
		ns:Print(L.ERRORS_COUNT:format(count) .. " - |cffffd200/fh errors|r")
	end
end
