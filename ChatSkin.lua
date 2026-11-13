--[[
	Chat skin: the whole chat in the look of the channel bar (ChatBar.lua): dark strips with
	the thin golden border of the game's windows, places split by thin lines.

	  * tabs: the docked tabs stand on one strip, split by thin lines; the selected tab has
	    golden text on a faint golden fill, the others light grey; the strip fades with them
	  * chat windows: the game's background and frame give way to the dark box
	  * edit box: the same box, its border in the color of the channel being typed to

	The game's own textures are only emptied (SetTexture(nil)), never moved or hidden: their
	places and sizes keep working for the game and for the other modules. The new message
	glow of the tabs is kept. Switching it off takes a /reload.
--]]

local _, ns = ...

local ChatSkin = ns:NewModule("ChatSkin")

local HEIGHT, INSET = 24, 3 -- the strip of the tabs, as tall as the channel bar
local GOLD = {0.8, 0.65, 0.25, 0.9}
local LINE = {0.8, 0.65, 0.25, 0.45}
local TEXT_SELECTED = {1, 0.82, 0}
local TEXT_OTHER = {0.72, 0.72, 0.72}

local settings
local ours = {} -- textures this module made: never emptied


--[[ Shared look ]]--

local BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 12, insets = {left = INSET, right = INSET, top = INSET, bottom = INSET},
}

-- A dark box with the thin golden border (also used by the channel bar).
function ChatSkin.Style(frame, alpha)
	frame:SetBackdrop(BACKDROP)
	frame:SetBackdropColor(0, 0, 0, alpha or 0.6)
	frame:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
end

local function Box(parent, alpha)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetFrameLevel(math.max(parent:GetFrameLevel() - 1, 0))
	ChatSkin.Style(box, alpha)
	return box
end

local function Empty(texture)
	if texture and not ours[texture] and texture.GetObjectType and texture:GetObjectType() == "Texture" then
		texture:SetTexture(nil)
	end
end

-- Walks the regions as arguments: no table is made (this runs on every tab update).
local function EmptyEach(keep, region, ...)
	if not region then return end
	if region ~= keep then Empty(region) end
	return EmptyEach(keep, ...)
end

local function EmptyRegions(frame, keep)
	EmptyEach(keep, frame:GetRegions())
end

local function Own(texture)
	ours[texture] = true
	return texture
end


--[[ Chat windows ]]--

local FRAME_TEXTURES = CHAT_FRAME_TEXTURES or {"Background", "TopLeftTexture", "BottomLeftTexture",
	"TopRightTexture", "BottomRightTexture", "LeftTexture", "RightTexture", "BottomTexture", "TopTexture"}

local windows = {} -- chat frame -> its box: the edge every other piece lines up with

-- The box of a chat window (the channel bar lines up with it too).
function ChatSkin:WindowBox(frame)
	return windows[frame]
end

local function SkinWindow(frame)
	if windows[frame] then return end
	local name = frame:GetName()
	if not name then return end
	for _, suffix in ipairs(FRAME_TEXTURES) do
		Empty(_G[name .. suffix])
	end
	local background = _G[name .. "Background"]
	local box = Box(frame, 0.4)
	if background then
		box:SetPoint("TOPLEFT", background, "TOPLEFT", -2, 2)
		box:SetPoint("BOTTOMRIGHT", background, "BOTTOMRIGHT", 2, -2)
	else
		box:SetPoint("TOPLEFT", frame, "TOPLEFT", -6, 6)
		box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 6, -6)
	end
	windows[frame] = box
end

-- Horizontal distance from a frame's edges to its window box's edges (nil before layout).
local function EdgesTo(frame, box)
	if not (box and frame:GetLeft() and box:GetLeft()) then return end
	return box:GetLeft() - frame:GetLeft(), box:GetRight() - frame:GetRight()
end


--[[ Edit box ]]--

local boxes = {} -- edit box -> its box

-- The border takes the color of where the text goes (guild green, party blue...).
local function TintEditBox(editBox)
	local box = boxes[editBox]
	if not box then return end
	EmptyRegions(editBox) -- the game sets its focus art again on some changes
	local chatType = editBox:GetAttribute("chatType")
	if chatType == "CHANNEL" then
		local target = editBox:GetAttribute("channelTarget")
		chatType = target and ("CHANNEL" .. target) or chatType
	end
	local info = chatType and ChatTypeInfo and ChatTypeInfo[chatType]
	if info and editBox:HasFocus() then
		box:SetBackdropBorderColor(info.r or 1, info.g or 1, info.b or 1, 1)
	else
		box:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], GOLD[4])
	end
end

-- The box hangs under the chat window's box, as wide, GAP below it (the same space as between
-- the tabs and the window); the game's edit box is placed inside it, so the typed text is
-- centered. Anchors, not measured numbers: the edit box and the window may differ in scale.
-- When the game places the edit box again (docking...), it goes back.
-- The golden lines sit about 3 px inside each box: -4 leaves 2 px between the lines, as
-- between the tabs and the window.
local GAP, EDIT_HEIGHT = -4, 26
local placing = false

local function AlignEditBox(editBox)
	local box = boxes[editBox]
	if not box or placing then return end
	local window = windows[editBox.chatFrame or editBox:GetParent()]
	placing = true
	box:ClearAllPoints()
	if window then
		box:SetPoint("TOPLEFT", window, "BOTTOMLEFT", 0, -GAP)
		box:SetPoint("TOPRIGHT", window, "BOTTOMRIGHT", 0, -GAP)
		box:SetHeight(EDIT_HEIGHT)
		editBox:ClearAllPoints()
		editBox:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
		editBox:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
	else
		box:SetPoint("TOPLEFT", editBox, "TOPLEFT", 2, -2)
		box:SetPoint("BOTTOMRIGHT", editBox, "BOTTOMRIGHT", -2, 2)
	end
	placing = false
end

local function SkinEditBox(editBox)
	if not editBox or boxes[editBox] then return end
	EmptyRegions(editBox)
	local box = Box(editBox, 0.6)
	boxes[editBox] = box
	AlignEditBox(editBox)
	editBox:HookScript("OnShow", AlignEditBox)
	-- the game anchors it again on some changes: back under the window right after
	local function Align() AlignEditBox(editBox) end
	hooksecurefunc(editBox, "SetPoint", function()
		if not placing then
			ns:Defer("chat-skin-edit", Align)
		end
	end)
	editBox:HookScript("OnEditFocusGained", TintEditBox)
	editBox:HookScript("OnEditFocusLost", TintEditBox)
	if editBox.UpdateHeader then
		hooksecurefunc(editBox, "UpdateHeader", TintEditBox)
	end
end


--[[ Tabs ]]--

local tabs = {} -- tab -> {fill, light, line}
local strips = {} -- the docked tabs' strip, and one per undocked tab

local function TabText(tab)
	local name = tab:GetName()
	return tab.Text or (name and _G[name .. "Text"])
end

-- How far the tab's text sits above the tab's middle: the strip is centered on the text.
local function TextOffset(tab)
	local text = TabText(tab)
	local _, textY = (text or tab):GetCenter()
	local _, tabY = tab:GetCenter()
	return textY and tabY and (textY - tabY) or 0
end

local function SkinTab(tab)
	local parts = tabs[tab]
	if not parts then
		parts = {}
		parts.fill = Own(tab:CreateTexture(nil, "BACKGROUND"))
		parts.fill:SetColorTexture(1, 0.82, 0.2, 0.14)
		parts.light = Own(tab:CreateTexture(nil, "HIGHLIGHT"))
		parts.light:SetColorTexture(1, 1, 1, 0.1)
		parts.line = Own(tab:CreateTexture(nil, "ARTWORK"))
		parts.line:SetWidth(1)
		parts.line:SetColorTexture(LINE[1], LINE[2], LINE[3], LINE[4])
		tabs[tab] = parts
	end
	EmptyRegions(tab, tab.glow) -- the new message glow stays
	if tab.conversationIcon then ours[tab.conversationIcon] = true end
	return parts
end

local function ColorTab(tab, selected)
	local parts = tabs[tab]
	if not parts then return end
	EmptyRegions(tab, tab.glow)
	parts.fill:SetShown(selected and true or false)
	local text = TabText(tab)
	local color = selected and TEXT_SELECTED or TEXT_OTHER
	if text then text:SetTextColor(color[1], color[2], color[3]) end
end

-- The fill, light and line of a tab, from the top to the bottom of the strip.
local function PlaceFill(texture, tab, top, bottom)
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", tab, "LEFT", 0, top)
	texture:SetPoint("BOTTOMRIGHT", tab, "RIGHT", 0, bottom)
end

local function PlaceParts(tab, offset, previous)
	local parts = tabs[tab]
	local top, bottom = offset + HEIGHT / 2 - INSET, offset - HEIGHT / 2 + INSET
	PlaceFill(parts.fill, tab, top, bottom)
	PlaceFill(parts.light, tab, top, bottom)
	parts.line:ClearAllPoints()
	if previous and previous:GetRight() and tab:GetLeft() then
		local gap = tab:GetLeft() - previous:GetRight()
		parts.line:SetPoint("TOPLEFT", tab, "LEFT", -math.floor(gap / 2 + 0.5) - 1, top)
		parts.line:SetPoint("BOTTOMLEFT", tab, "LEFT", -math.floor(gap / 2 + 0.5) - 1, bottom)
		parts.line:Show()
	else
		parts.line:Hide()
	end
end

-- A strip from the first tab to the last, child of the first so it fades with the tabs.
local function Strip(key, first, last, offset, box)
	local strip = strips[key]
	if not strip then
		strip = CreateFrame("Frame", nil, first, "BackdropTemplate")
		ChatSkin.Style(strip, 0.6)
		strips[key] = strip
	end
	strip:SetParent(first)
	strip:SetFrameLevel(math.max(first:GetFrameLevel() - 1, 0))
	strip:SetHeight(HEIGHT)
	strip:ClearAllPoints()
	local left = EdgesTo(first, box)
	strip:SetPoint("LEFT", first, "LEFT", left or -INSET, offset)
	strip:SetPoint("RIGHT", last, "RIGHT", INSET, offset)
	strip:Show()
end

local function SelectedWindow()
	return FCFDock_GetSelectedWindow and GENERAL_CHAT_DOCK and FCFDock_GetSelectedWindow(GENERAL_CHAT_DOCK)
end

local FALLBACK_DOCK = {}
local function DockList()
	if GENERAL_CHAT_DOCK and GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES then
		return GENERAL_CHAT_DOCK.DOCKED_CHAT_FRAMES
	end
	FALLBACK_DOCK[1] = ChatFrame1
	return FALLBACK_DOCK
end

local docked = {} -- reused by every layout

local function Layout()
	local selected = SelectedWindow()
	wipe(docked)
	local dockList = DockList()
	for _, frame in ipairs(dockList) do
		docked[frame] = true
	end

	-- docked tabs, in their order, on one strip
	local first, last, previous, offset
	for _, frame in ipairs(dockList) do
		local tab = _G[frame:GetName() .. "Tab"]
		if tab and tab:IsShown() then
			SkinTab(tab)
			if not first then
				first, offset = tab, TextOffset(tab)
			end
			PlaceParts(tab, offset, previous)
			ColorTab(tab, frame == selected)
			previous, last = tab, tab
		end
	end
	if first then
		Strip("dock", first, last, offset, windows[ChatFrame1])
	end

	-- windows out of the dock: each tab on its own strip
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. i]
		local tab = frame and _G["ChatFrame" .. i .. "Tab"]
		if tab and not docked[frame] and tab:IsShown() then
			SkinTab(tab)
			local own = TextOffset(tab)
			PlaceParts(tab, own)
			ColorTab(tab, true)
			Strip(tab, tab, tab, own, windows[frame])
		elseif tab and strips[tab] then
			strips[tab]:Hide()
		end
	end
end

local function Relayout()
	Layout()
	for editBox in pairs(boxes) do AlignEditBox(editBox) end
end

local function Update()
	ns:Defer("chat-skin", Relayout)
end

-- What the tabs' layout depends on, kept from the last check and compared in place: the game
-- calls FCFDock_UpdateTabs every frame (it returns at once when nothing changed), and a
-- layout on each call filled the memory with garbage. Four slots per docked tab.
local seen = {count = 0}

local function DockChanged()
	local changed = false
	local selected = SelectedWindow() or false
	if seen.selected ~= selected then
		seen.selected, changed = selected, true
	end
	local n = 0
	for _, frame in ipairs(DockList()) do
		local name = frame:GetName()
		local tab = name and _G[name .. "Tab"]
		local shown = tab and tab:IsShown() or false
		local left = tab and tab:GetLeft() or 0
		local width = tab and tab:GetWidth() or 0
		local slot = n * 4
		if seen[slot + 1] ~= frame or seen[slot + 2] ~= shown or seen[slot + 3] ~= left or seen[slot + 4] ~= width then
			seen[slot + 1], seen[slot + 2], seen[slot + 3], seen[slot + 4] = frame, shown, left, width
			changed = true
		end
		n = n + 1
	end
	if seen.count ~= n then
		seen.count, changed = n, true
	end
	return changed
end

local function OnDockTabs()
	if DockChanged() then Update() end
end


--[[ Module ]]--

local function SkinAll()
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local frame = _G["ChatFrame" .. i]
		if frame then
			SkinWindow(frame)
			SkinEditBox(frame.editBox or _G["ChatFrame" .. i .. "EditBox"])
		end
	end
	Update()
end

function ChatSkin:OnInitialize()
	settings = ns.db.chat
end

function ChatSkin:OnLogin()
	if not settings.skin then return end
	SkinAll()
	for _, name in ipairs({"FCF_DockFrame", "FCF_UnDockFrame", "FCF_Close", "FCF_OpenNewWindow"}) do
		if _G[name] then hooksecurefunc(name, SkinAll) end
	end
	-- called every frame by the game: lays out only when the tabs really changed
	if FCFDock_UpdateTabs then
		hooksecurefunc("FCFDock_UpdateTabs", ns:Track("chat-skin:dock-tabs", OnDockTabs))
	end
	if FCFTab_UpdateColors then
		hooksecurefunc("FCFTab_UpdateColors", ns:Track("chat-skin:tab-colors", ColorTab))
	end
	if FCFDock_SelectWindow then
		hooksecurefunc("FCFDock_SelectWindow", Update)
	end
	if ChatEdit_UpdateHeader then
		hooksecurefunc("ChatEdit_UpdateHeader", TintEditBox)
	end
	-- a real change of size only (the event can repeat with the same size)
	local sizes = {} -- chat frame -> {width, height}
	local OnSizeChanged = ns:Track("chat-skin:size", function(frame, width, height)
		local last = sizes[frame]
		if not last then
			last = {}
			sizes[frame] = last
		elseif last[1] and math.abs(last[1] - (width or 0)) < 0.5 and math.abs(last[2] - (height or 0)) < 0.5 then
			return
		end
		last[1], last[2] = width or 0, height or 0
		Update()
		for editBox in pairs(boxes) do AlignEditBox(editBox) end
		if ns.ChatBar then ns.ChatBar:Refresh() end
	end)
	for frame in pairs(windows) do
		frame:HookScript("OnSizeChanged", OnSizeChanged)
	end
	-- the tabs are laid out a moment after login
	C_Timer.After(1, function()
		Update()
		for editBox in pairs(boxes) do AlignEditBox(editBox) end
		if ns.ChatBar then ns.ChatBar:Refresh() end
	end)
end
