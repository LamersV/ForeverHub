--[[
	Glow window. Two pages, picked by the tabs on its right edge:

	Look: at the top, the kinds of objects that glow, each with its icon, its box and its
	color; below, on the left, the preview of the kind picked there (Preview.lua) and, on
	the right, its look: effect, size, intensity, height, name and icon. "All" sets the look
	of every object; a kind may have its own.

	Settings: detection (range, direction, exclusive mode, interact key, ignored objects),
	general switches, when to hide the light, and the area cut out around the character.

	The window only shows settings and asks Glow.lua to change them; it rebuilds nothing
	when they change, it refreshes its controls.
--]]

local ADDON, ns = ...
local L, W = ns.L, ns.Widgets
local FX = ns.GlowFX

local Window = {}
ns.GlowWindow = Window

local WIDTH, HEIGHT = 860, 662
local EDGE, TOP, FOOT, GAP, PAD = 12, 62, 42, 6, 16
local STRIP = 76 -- height of the band of object kinds
local VIEW = 300 -- width of the preview panel
local SLOT = 40 -- side of an icon button (the game's spell button frame)
local ROW = 30 -- height of a checkbox row
local PER_ROW = 5 -- effects per row
local VALUE = 46 -- room for a slider's value, on its right
local CONFIRM_TIME = 4

local frame
local pages = {}
local refreshers = {}
local refreshing = false
local openPage, scope = "look", "all" -- scope: a category, or "all"
local previewCategory = "ore"
local stopListening

local function Glow()
	return ns.Glow
end

local function ScopeCategory()
	return scope ~= "all" and scope or nil
end

local function CategoryName(category)
	return L["GLOW_CAT_" .. category:upper()]
end


--[[ Pieces ]]--

local CARD = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 14, insets = {left = 3, right = 3, top = 3, bottom = 3},
}

local function Card(parent, width, height)
	local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	card:SetBackdrop(CARD)
	card:SetBackdropColor(0.03, 0.03, 0.03, 0.72)
	card:SetBackdropBorderColor(0.62, 0.56, 0.46, 0.9)
	card:SetSize(width, height)
	return card
end

local function HasAtlas(atlas)
	return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) ~= nil
end

-- Icon slot drawn on a frame: black ground, the picture, and the rim of the spell buttons.
local function Slot(owner, size, point, x, y)
	local back = owner:CreateTexture(nil, "BACKGROUND")
	back:SetSize(size - 6, size - 6)
	back:SetPoint(point, x, y)
	back:SetColorTexture(0, 0, 0, 0.85)
	local icon = owner:CreateTexture(nil, "BORDER")
	icon:SetAllPoints(back)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	local rim = owner:CreateTexture(nil, "OVERLAY")
	rim:SetPoint("CENTER", back, "CENTER")
	if HasAtlas("Profession-square-frame") then
		rim:SetAtlas("Profession-square-frame", true)
	else
		rim:SetTexture("Interface\\Buttons\\UI-Quickslot2")
		rim:SetSize(size * 1.7, size * 1.7)
	end
	return icon, back
end

local function Tooltip(owner, title, text, ...)
	local lines = {...}
	owner:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, type(title) == "function" and title() or title)
		local body = type(text) == "function" and text() or text
		if body then GameTooltip_AddNormalLine(GameTooltip, body) end
		for _, line in ipairs(lines) do GameTooltip_AddInstructionLine(GameTooltip, line) end
		GameTooltip:Show()
	end)
	owner:HookScript("OnLeave", function() GameTooltip:Hide() end)
end

local function Dim(fontString, available, r, g, b)
	if available then fontString:SetTextColor(r, g, b) else fontString:SetTextColor(0.5, 0.5, 0.5) end
end

-- A column of controls inside a card: each control goes at column.y, which then goes down.
local function NewCard(page, x, y, width, height, title)
	local card = Card(page, width, height)
	card:SetPoint("TOPLEFT", x, y)
	local column = {parent = card, x = PAD, width = width - 2 * PAD, y = -14}
	if title then
		local text = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		text:SetPoint("TOPLEFT", column.x, column.y)
		text:SetText(title)
		column.y = column.y - 26
	end
	return column
end

local function Getter(key, scoped)
	return function() return Glow():Get(key, scoped and ScopeCategory() or nil) end
end

local function Setter(key, scoped)
	return function(value) Glow():Set(key, value, scoped and ScopeCategory() or nil) end
end

local function AddCheck(column, text, tip, get, set)
	local check = CreateFrame("CheckButton", nil, column.parent, "MinimalCheckboxTemplate")
	check:SetPoint("TOPLEFT", column.x - 3, column.y + 1)
	column.y = column.y - ROW
	local label = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT", check, "RIGHT", 1, 0)
	label:SetText(text)
	check:SetHitRectInsets(0, -(label:GetStringWidth() + 3), 0, 0)
	check:SetScript("OnClick", function(self)
		local checked = self:GetChecked()
		PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
		set(checked)
	end)
	Tooltip(check, text, tip)
	function check:SetAvailable(available)
		self:SetEnabled(available)
		Dim(label, available, 1, 1, 1)
	end
	refreshers[#refreshers + 1] = function() check:SetChecked(get() and true or false) end
	return check
end

local function AddOption(column, text, tip, key, scoped)
	return AddCheck(column, text, tip, Getter(key, scoped), Setter(key, scoped))
end

-- Slider: name on the left, value on the right; inline puts the bar between them.
local function AddSlider(column, text, tip, key, format, scoped, inline)
	local limits = Glow().LIMITS[key]
	local get, set = Getter(key, scoped), Setter(key, scoped)
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, inline and 28 or 40)
	row:SetPoint("TOPLEFT", column.x, column.y)
	row:EnableMouse(true)
	column.y = column.y - (inline and 28 or 44)
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	local value = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	if inline then
		label:SetPoint("LEFT")
		value:SetPoint("RIGHT")
		slider:SetSize(inline, 20)
		slider:SetPoint("RIGHT", -VALUE, 0)
	else
		label:SetPoint("TOPLEFT", 0, -3)
		value:SetPoint("TOPRIGHT", 0, -3)
		slider:SetSize(column.width, 20)
		slider:SetPoint("BOTTOMLEFT")
	end
	label:SetText(text)
	local function Format(number)
		return (format or "%d"):format(number)
	end
	slider:Init(get(), limits[1], limits[2], limits[2] - limits[1])
	slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, number)
		number = math.floor(number + 0.5)
		value:SetText(Format(number))
		if not refreshing and number ~= get() then set(number) end
	end, row)
	Tooltip(row, text, tip)
	Tooltip(slider.Slider, text, tip)
	local was
	function row:SetAvailable(available)
		if available == was then return end -- never while a slider is being dragged
		was = available
		slider:SetEnabled(available)
		Dim(label, available, 1, 1, 1)
		Dim(value, available, 1, 0.82, 0)
	end
	refreshers[#refreshers + 1] = function()
		slider:SetValue(get())
		value:SetText(Format(get()))
	end
	return row
end

-- The font of the name, one at a time between the arrows of a slider without its bar;
-- the name is written in the font itself.
local function AddFont(column, width)
	local get, set = Getter("font", true), Setter("font", true)
	local fonts = Glow().FONTS
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, 28)
	row:SetPoint("TOPLEFT", column.x, column.y)
	row:EnableMouse(true)
	column.y = column.y - 28
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT")
	label:SetText(L.GLOW_FONT)
	local stepper = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
	stepper:SetSize(width, 20)
	stepper:SetPoint("RIGHT", -VALUE, 0)
	stepper.Slider:Hide()
	local text = stepper:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	text:SetPoint("CENTER", stepper.Slider, "CENTER")
	local file, height, flags = text:GetFont()
	local function Show(index)
		local font = fonts[index]
		text:SetText(font[2] or L.GLOW_FONT_GAME)
		text:SetFont(font[3] or file, height, flags)
	end
	stepper:Init(1, 1, #fonts, #fonts - 1)
	stepper:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, number)
		local index = math.floor(number + 0.5)
		if not fonts[index] then return end
		Show(index)
		if not refreshing and fonts[index][1] ~= get() then set(fonts[index][1]) end
	end, row)
	Tooltip(row, L.GLOW_FONT, L.GLOW_FONT_TIP)
	local was
	function row:SetAvailable(available)
		if available == was then return end
		was = available
		stepper:SetEnabled(available)
		Dim(label, available, 1, 1, 1)
		Dim(text, available, 1, 0.82, 0)
	end
	refreshers[#refreshers + 1] = function()
		local key = get()
		for index, font in ipairs(fonts) do
			if font[1] == key then
				stepper:SetValue(index)
				Show(index)
			end
		end
	end
	return row
end

-- Radio buttons, perRow per row, under the choice's name. choices: {value, text}.
local function AddChoice(column, text, tip, choices, get, set, perRow)
	local top = 22
	local height = top + math.ceil(#choices / perRow) * 22
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, height - 4)
	row:SetPoint("TOPLEFT", column.x, column.y)
	row:EnableMouse(true)
	column.y = column.y - height
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("TOPLEFT", 0, -3)
	label:SetText(text)
	Tooltip(row, text, tip)
	local radios = {}
	for index, choice in ipairs(choices) do
		local radio = CreateFrame("CheckButton", nil, row, "UIRadioButtonTemplate")
		radio:SetPoint("TOPLEFT", (index - 1) % perRow * column.width / perRow + 2, -top - math.floor((index - 1) / perRow) * 22)
		local caption = radio.text or radio.Text
		if caption then
			caption:SetFontObject(GameFontHighlight)
			caption:SetText(choice[2])
			radio:SetHitRectInsets(0, -(caption:GetStringWidth() + 5), 0, 0)
		end
		radio:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			set(choice[1])
		end)
		Tooltip(radio, choice[2], tip)
		radios[index] = radio
	end
	refreshers[#refreshers + 1] = function()
		local value = get()
		for index, choice in ipairs(choices) do radios[index]:SetChecked(value == choice[1]) end
	end
	return row
end

local function AddDivider(column)
	local line = column.parent:CreateTexture(nil, "ARTWORK")
	line:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
	line:SetSize(column.width, 8)
	line:SetPoint("TOPLEFT", column.x, column.y)
	line:SetAlpha(0.7)
	column.y = column.y - 8
end

local function AddButton(parent, text, tip, width, onClick)
	local button = W.CreateButton(parent, text, width, function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		onClick()
	end)
	if tip then Tooltip(button, text, tip) end
	return button
end

local function LookColor()
	local category = ScopeCategory()
	if category then return Glow():GetColor(category) end
	return 1, 0.82, 0
end

-- Effect grid: a button per effect with its drawing, tinted with the color of the objects
-- the page sets, and its name below.
local function AddEffects(column)
	local cell = column.width / PER_ROW
	local order = FX.ORDER
	local lines = math.ceil(#order / PER_ROW)
	local top, pitch = 24, SLOT + 18
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, top + lines * pitch - 4)
	row:SetPoint("TOPLEFT", column.x, column.y)
	column.y = column.y - top - lines * pitch
	local title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	title:SetPoint("TOPLEFT", 0, -2)
	title:SetText(L.GLOW_EFFECT)
	local get, set = Getter("effect", true), Setter("effect", true)
	local buttons, drawings = {}, {}
	for index, key in ipairs(order) do
		local button = CreateFrame("CheckButton", nil, row)
		button:SetSize(SLOT, SLOT)
		button:SetPoint("TOP", row, "TOPLEFT", ((index - 1) % PER_ROW + 0.5) * cell, -top - math.floor((index - 1) / PER_ROW) * pitch)
		Slot(button, SLOT, "CENTER", 0, 0)
		button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		button:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
		local checked = button:GetCheckedTexture()
		if checked then checked:SetBlendMode("ADD") end
		drawings[#drawings + 1] = FX.DrawIcon(button, key, SLOT - 8)
		local name = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		name:SetPoint("TOP", button, "BOTTOM", 0, 0)
		name:SetText(L["GLOW_FX_" .. key:upper()])
		button:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
			set(key)
		end)
		Tooltip(button, L["GLOW_FX_" .. key:upper()], L["GLOW_FX_" .. key:upper() .. "_TIP"])
		buttons[key] = button
	end
	refreshers[#refreshers + 1] = function()
		local current = get()
		for key, button in pairs(buttons) do button:SetChecked(key == current) end
		local r, g, b = LookColor()
		for _, drawing in ipairs(drawings) do FX.TintIcon(drawing, r, g, b) end
	end
end

-- Color swatch: left-click opens the color picker, right-click gives the original back.
local function AddSwatch(parent, category)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetSize(18, 18)
	swatch:RegisterForClicks("AnyUp")
	local border = swatch:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0.62, 0.56, 0.46, 1)
	local groove = swatch:CreateTexture(nil, "BORDER")
	groove:SetPoint("TOPLEFT", 1, -1)
	groove:SetSize(16, 16)
	groove:SetColorTexture(0, 0, 0, 1)
	local fill = swatch:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 2, -2)
	fill:SetSize(14, 14)
	swatch:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	swatch:SetScript("OnClick", function(_, button)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		if button == "RightButton" then
			Glow():SetColor(category)
			return
		end
		if not (ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow) then return end
		local r, g, b = Glow():GetColor(category)
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, hasOpacity = false,
			swatchFunc = function() Glow():SetColor(category, ColorPickerFrame:GetColorRGB()) end,
			cancelFunc = function(previous) Glow():SetColor(category, previous.r, previous.g, previous.b) end,
		})
	end)
	Tooltip(swatch, L.GLOW_COLOR, L.GLOW_COLOR_TIP, L.GLOW_COLOR_SET, L.GLOW_COLOR_RESET)
	refreshers[#refreshers + 1] = function() fill:SetColorTexture(Glow():GetColor(category)) end
	return swatch
end

local Open

-- Entry of the band of objects: icon and name; for a category, its box and its color too.
local function AddEntry(parent, x, width, text, icon, category)
	local entryScope = category or "all"
	local row = CreateFrame("CheckButton", nil, parent)
	row:SetSize(width - 2, STRIP - 10)
	row:SetPoint("TOPLEFT", x, -5)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	local content = SLOT + (category and 52 or 0)
	local image, slot = Slot(row, SLOT, "TOPLEFT", (width - 2 - content) / 2 + 3, -6)
	if image:SetTexture(icon) == false then image:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
	local chosen = row:CreateTexture(nil, "BACKGROUND")
	chosen:SetBlendMode("ADD")
	chosen:SetTexture(FX.MEDIA .. "glow.tga")
	chosen:SetSize(SLOT * 3.2, SLOT * 2.3)
	chosen:SetPoint("CENTER", slot, "CENTER", 0, -4)
	chosen:SetVertexColor(1, 0.74, 0.2, 0.85)
	local ring = row:CreateTexture(nil, "OVERLAY", nil, 1)
	ring:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	ring:SetBlendMode("ADD")
	ring:SetSize(SLOT, SLOT)
	ring:SetPoint("CENTER", slot, "CENTER")
	local title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	title:SetPoint("BOTTOM", 0, 4)
	title:SetText(text)
	row:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Open("look", entryScope)
	end)
	Tooltip(row, text, category and L.GLOW_SCOPE_ONE_TIP or L.GLOW_SCOPE_ALL_TIP)
	local toggle
	if category then
		toggle = CreateFrame("CheckButton", nil, row, "MinimalCheckboxTemplate")
		toggle:SetPoint("LEFT", slot, "RIGHT", 5, 0)
		toggle:SetScript("OnClick", function(self)
			local checked = self:GetChecked()
			PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
			Glow():SetCategoryShown(category, checked)
		end)
		Tooltip(toggle, text, L["GLOW_CAT_" .. category:upper() .. "_TIP"])
		AddSwatch(row, category):SetPoint("LEFT", toggle, "RIGHT", 1, 0)
	end
	refreshers[#refreshers + 1] = function()
		local selected = scope == entryScope
		local shown = not category or Glow():IsCategoryShown(category)
		row:SetChecked(selected)
		chosen:SetShown(selected)
		ring:SetShown(selected)
		image:SetDesaturated(not shown)
		Dim(title, shown, 1, 0.82, 0)
		if toggle then toggle:SetChecked(shown) end
	end
end

-- Interact key: a button showing it. Left-click waits for the next key (or mouse button,
-- or wheel), Escape cancels; right-click removes it. A key already used elsewhere must be
-- pressed twice. Returns a function that stops listening.
local MODIFIERS = {LALT = true, RALT = true, LCTRL = true, RCTRL = true, LSHIFT = true, RSHIFT = true, LMETA = true,
	RMETA = true, UNKNOWN = true}

local function AddKeybind(column)
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, 26)
	row:SetPoint("TOPLEFT", column.x, column.y)
	row:EnableMouse(true)
	column.y = column.y - ROW
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT")
	label:SetText(L.GLOW_KEY)
	Tooltip(row, L.GLOW_KEY, L.GLOW_KEY_TIP)
	local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	button:SetSize(150, 22)
	button:SetPoint("RIGHT")
	button:RegisterForClicks("AnyUp")
	button:EnableKeyboard(false)
	local listening, contested = false, nil

	local function Update()
		local key = Glow():GetInteractKey()
		button:SetText(contested and L.GLOW_CONFIRM or listening and L.GLOW_KEY_LISTEN
			or key and (GetBindingText and GetBindingText(key) or key) or L.GLOW_KEY_NONE)
	end

	local function Listen(on)
		listening, contested = on, nil
		button:EnableKeyboard(on)
		button:EnableMouseWheel(on)
		Update()
	end

	local function Assign(key)
		local owner = key and Glow():KeyOwner(key)
		local ok, reason = Glow():SetInteractKey(key)
		if not ok then
			ns:Print(reason)
		elseif owner then
			ns:Print(L.GLOW_KEY_REPLACED:format(key, owner))
		end
	end

	local function Press(key)
		if key == "ESCAPE" then
			Listen(false)
			return
		end
		if MODIFIERS[key] then return end
		local chord = (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
			.. (IsShiftKeyDown() and "SHIFT-" or "") .. key
		local owner = Glow():KeyOwner(chord)
		if owner and chord ~= contested then
			contested = chord
			ns:Print(L.GLOW_KEY_TAKEN:format(chord, owner))
			Update()
			return
		end
		Listen(false)
		Assign(chord)
	end

	button:SetScript("OnKeyDown", function(_, key)
		if listening then Press(key) end
	end)
	button:SetScript("OnMouseWheel", function(_, delta) Press(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
	button:SetScript("OnClick", function(_, mouse)
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
		if listening then
			local extra = mouse == "MiddleButton" and "BUTTON3" or mouse:match("^Button(%d+)$") and "BUTTON" .. mouse:match("(%d+)")
			if extra then Press(extra) else Listen(false) end
		elseif mouse == "RightButton" then
			Assign(nil)
		elseif InCombatLockdown() then
			ns:Print(L.GLOW_KEY_COMBAT)
		else
			Listen(true)
		end
	end)
	Tooltip(button, L.GLOW_KEY, function() return listening and L.GLOW_KEY_LISTEN_TIP or L.GLOW_KEY_TIP end,
		L.GLOW_KEY_SET, L.GLOW_KEY_CLEAR)
	button:SetScript("OnEvent", Update)
	button:RegisterEvent("UPDATE_BINDINGS")
	refreshers[#refreshers + 1] = Update
	return function()
		if listening then Listen(false) end
	end
end

-- Ignored objects: how many (their names on mouse over), and a button that ignores the
-- object targeted now, or stops ignoring it.
local function AddIgnore(column)
	local row = CreateFrame("Frame", nil, column.parent)
	row:SetSize(column.width, 26)
	row:SetPoint("TOPLEFT", column.x, column.y)
	row:EnableMouse(true)
	column.y = column.y - ROW
	local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	label:SetPoint("LEFT")
	row:SetScript("OnEnter", function(self)
		local names = Glow():IgnoredNames()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.GLOW_IGNORED_COUNT:format(#names))
		GameTooltip_AddNormalLine(GameTooltip, L.GLOW_IGNORED_TIP)
		for i = 1, math.min(#names, 15) do GameTooltip_AddInstructionLine(GameTooltip, names[i]) end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and IsShiftKeyDown() then Glow():ClearIgnored() end
	end)
	local button = AddButton(row, L.GLOW_IGNORE_TARGET, L.GLOW_IGNORE_TARGET_TIP, 150, function() Glow():IgnoreTarget() end)
	button:SetPoint("RIGHT")
	refreshers[#refreshers + 1] = function() label:SetText(L.GLOW_IGNORED_COUNT:format(#Glow():IgnoredNames())) end
end

-- Side tab on the right edge of the window.
local function SideTab(previous, icon, tooltip, onClick)
	local ok, tab = pcall(CreateFrame, "Frame", nil, frame, "LargeSideTabButtonTemplate")
	if ok and tab and tab.Icon and tab.SetChecked and tab.SetCustomOnMouseUpHandler then
		tab.Icon:SetTexture(icon)
		if tab.SetFillToInterior then tab:SetFillToInterior(true) end
		tab.tooltipText = tooltip
		tab:SetCustomOnMouseUpHandler(function(_, button, inside)
			if button == "LeftButton" and inside then onClick() end
		end)
	else
		if tab then tab:Hide() end
		tab = CreateFrame("CheckButton", nil, frame)
		tab:SetSize(32, 32)
		local back = tab:CreateTexture(nil, "BACKGROUND")
		back:SetTexture("Interface\\SpellBook\\SpellBook-SkillLineTab")
		back:SetSize(64, 64)
		back:SetPoint("TOPLEFT", -3, 11)
		local face = tab:CreateTexture(nil, "ARTWORK")
		face:SetAllPoints()
		face:SetTexture(icon)
		tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
		tab:SetCheckedTexture("Interface\\Buttons\\CheckButtonHilight")
		tab:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			onClick()
		end)
		Tooltip(tab, tooltip)
	end
	if previous then
		tab:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -4)
	else
		tab:SetPoint("TOPLEFT", frame, "TOPRIGHT", 0, -60)
	end
	return tab
end


--[[ Window ]]--

local function Refresh()
	if not (frame and frame:IsShown()) then return end
	refreshing = true
	for _, refresh in ipairs(refreshers) do refresh() end
	refreshing = false
	if ns.GlowPreview then ns.GlowPreview:Refresh() end
end

function Open(name, newScope)
	openPage = name
	if newScope then
		scope = newScope
		if newScope ~= "all" then previewCategory = newScope end
		if ns.GlowPreview then ns.GlowPreview:SetCategory(previewCategory, ScopeCategory()) end
	end
	for key, page in pairs(pages) do page:SetShown(key == name) end
	Refresh()
end

local function Build()
	frame = W.CreateWindow("ForeverHubGlowWindow", UIParent, ns.db.positions)
	frame:SetSize(WIDTH, HEIGHT)
	W.SetTitle(frame, L.GLOW_TITLE)
	local portrait = frame.PortraitContainer and frame.PortraitContainer.portrait or frame.portrait
	if portrait then portrait:SetTexture(FX.MEDIA .. "icon.tga") end
	frame:RestorePosition("LEFT", 30, 20)

	local heading = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	heading:SetPoint("TOPLEFT", 68, -33)
	refreshers[#refreshers + 1] = function()
		if openPage == "settings" then
			heading:SetText(L.GLOW_SETTINGS)
		else
			local category = ScopeCategory()
			heading:SetText(L.GLOW_LOOK_OF:format(category and CategoryName(category) or L.GLOW_ALL))
		end
	end

	local tabs = {{"look", FX.MEDIA .. "icon.tga", L.GLOW_TAB_LOOK}, {"settings", "Interface\\Icons\\Trade_Engineering", L.GLOW_SETTINGS}}
	local previous
	for _, info in ipairs(tabs) do
		local name = info[1]
		local tab = SideTab(previous, info[2], info[3], function() Open(name) end)
		refreshers[#refreshers + 1] = function() tab:SetChecked(openPage == name) end
		previous = tab
	end

	local height = HEIGHT - TOP - FOOT
	for _, info in ipairs(tabs) do
		local page = CreateFrame("Frame", nil, frame)
		page:SetSize(WIDTH - 2 * EDGE, height)
		page:SetPoint("TOPLEFT", EDGE, -TOP)
		pages[info[1]] = page
	end

	-- Look page: the band of objects
	local page = pages.look
	local strip = Card(page, page:GetWidth(), STRIP)
	strip:SetPoint("TOPLEFT")
	local categories = Glow().CATEGORIES
	local cell = (page:GetWidth() - 12) / (#categories + 1)
	AddEntry(strip, 6, cell, L.GLOW_ALL, FX.MEDIA .. "icon.tga")
	for index, category in ipairs(categories) do
		AddEntry(strip, 6 + index * cell, cell, CategoryName(category), Glow().ICONS[category], category)
	end

	-- below on the left, the preview
	local lower = height - STRIP - GAP
	local stage = Card(page, VIEW, lower)
	stage:SetPoint("TOPLEFT", 0, -STRIP - GAP)
	ns.GlowPreview:Create(stage, VIEW - 12, lower - 44):SetPoint("TOPLEFT", 6, -6)

	-- on the right, the look
	local column = NewCard(page, VIEW + GAP, -STRIP - GAP, page:GetWidth() - VIEW - GAP, lower)
	local shared = AddButton(frame, L.GLOW_SHARED, L.GLOW_SHARED_TIP, 200, function() Glow():ClearOwn(ScopeCategory()) end)
	shared:SetPoint("TOPRIGHT", -EDGE - 2, -30)
	refreshers[#refreshers + 1] = function()
		shared:SetShown(openPage == "look" and Glow():HasOwn(ScopeCategory()))
	end
	AddEffects(column)
	AddDivider(column)
	AddSlider(column, L.GLOW_SIZE, L.GLOW_SIZE_TIP, "size", nil, true, 200)
	AddSlider(column, L.GLOW_INTENSITY, L.GLOW_INTENSITY_TIP, "intensity", "%d%%", true, 200)
	AddSlider(column, L.GLOW_OFFSET, L.GLOW_OFFSET_TIP, "offsetY", nil, true, 200)
	AddDivider(column)
	AddCheck(column, L.GLOW_SILHOUETTE, L.GLOW_SILHOUETTE_TIP, Getter("silhouette", true), function(value)
		Glow():Set("silhouette", value, ScopeCategory())
		local failure = Glow():SilhouetteFailure()
		if value and failure then ns:Print(failure) end
	end)
	AddOption(column, L.GLOW_FADE, L.GLOW_FADE_TIP, "followAlpha", true)
	local left = column.x
	local showName = AddOption(column, L.GLOW_SHOW_NAME, L.GLOW_SHOW_NAME_TIP, "showName", true)
	column.x, column.y = left + column.width / 2, column.y + ROW
	local showIcon = AddOption(column, L.GLOW_SHOW_ICON, L.GLOW_SHOW_ICON_TIP, "showIcon", true)
	column.x = left
	local textSize = AddSlider(column, L.GLOW_TEXT_SIZE, L.GLOW_TEXT_SIZE_TIP, "textSize", "%d%%", true, 200)
	local font = AddFont(column, 200)
	refreshers[#refreshers + 1] = function()
		local bare = Glow():Get("glowOnly")
		local named = Glow():Get("showName", ScopeCategory())
		showName:SetAvailable(not bare)
		showIcon:SetAvailable(not bare)
		textSize:SetAvailable(not bare and named)
		font:SetAvailable(not bare and named)
	end

	-- Settings page: four cards
	page = pages.settings
	local half = (page:GetWidth() - GAP) / 2
	local upper = 236
	column = NewCard(page, 0, 0, half, upper, L.GLOW_HEADER_DETECTION)
	AddSlider(column, L.GLOW_RANGE, L.GLOW_RANGE_TIP, "range", L.GLOW_YARDS, false, 170)
	AddChoice(column, L.GLOW_DIRECTION, L.GLOW_DIRECTION_TIP,
		{{0, L.GLOW_ARC_0}, {1, L.GLOW_ARC_1}, {2, L.GLOW_ARC_2}}, Getter("arc"), Setter("arc"), 3)
	AddOption(column, L.GLOW_EXCLUSIVE, L.GLOW_EXCLUSIVE_TIP, "exclusive")
	stopListening = AddKeybind(column)
	AddIgnore(column)

	column = NewCard(page, half + GAP, 0, half, upper, L.GLOW_HEADER_GENERAL)
	AddOption(column, L.GLOW_ENABLE, L.GLOW_ENABLE_TIP, "enabled")
	AddOption(column, L.GLOW_ONLY, L.GLOW_ONLY_TIP, "glowOnly")
	local sparkles = ns.db.sparkles
	AddCheck(column, L.OPT_SPARKLE_QUEST, L.OPT_SPARKLE_QUEST_TIP, function() return sparkles.questLoot end,
		function(value) ns.Sparkles:SetQuestLoot(value) end)
	AddCheck(column, L.OPT_QUEST_MOBS, L.OPT_QUEST_MOBS_TIP, function() return sparkles.questMobs end, function(value)
		sparkles.questMobs = value
		ns.QuestGlow:Refresh()
	end)
	AddOption(column, L.GLOW_OPT_DEBUG, L.GLOW_OPT_DEBUG_TIP, "debug")
	local status = column.parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	status:SetPoint("TOPLEFT", column.x, column.y - 4)
	status:SetWidth(column.width)
	status:SetJustifyH("LEFT")
	refreshers[#refreshers + 1] = function()
		local conflict = ns:GetConflict("sparkles")
		if conflict then
			status:SetText(L.CONFLICT_ACTIVE:format(conflict))
		elseif not ns.db.modules.sparkles then
			status:SetText("|cffff8040" .. L.GLOW_MODULE_OFF .. "|r")
		else
			status:SetText("")
		end
	end

	column = NewCard(page, 0, -upper - GAP, half, height - upper - GAP, L.GLOW_HEADER_HIDE)
	AddOption(column, L.GLOW_HIDE_COMBAT, L.GLOW_HIDE_COMBAT_TIP, "hideInCombat")
	AddOption(column, L.GLOW_HIDE_INSTANCE, L.GLOW_HIDE_INSTANCE_TIP, "hideInInstance")
	AddOption(column, L.GLOW_HIDE_LOCKED, L.GLOW_HIDE_LOCKED_TIP, "hideLocked")
	AddOption(column, L.GLOW_HIDE_UNTRAINED, L.GLOW_HIDE_UNTRAINED_TIP, "hideUntrained")

	column = NewCard(page, half + GAP, -upper - GAP, half, height - upper - GAP, L.GLOW_HEADER_SILHOUETTE)
	local zone = {
		AddSlider(column, L.GLOW_ZONE_SIZE, L.GLOW_ZONE_SIZE_TIP, "bodyScale", "%d%%"),
		AddSlider(column, L.GLOW_ZONE_HEIGHT, L.GLOW_ZONE_HEIGHT_TIP, "bodyShift", "%d%%"),
		AddCheck(column, L.GLOW_ZONE_SHOW, L.GLOW_ZONE_SHOW_TIP, function() return Glow():IsZoneShown() end,
			function(value) Glow():ShowZone(value) end),
	}
	refreshers[#refreshers + 1] = function()
		local available = not Glow():SilhouetteFailure()
		for _, control in ipairs(zone) do control:SetAvailable(available) end
	end

	-- footer: version and reset
	local confirmLeft
	local reset = AddButton(frame, L.GLOW_DEFAULTS, L.GLOW_DEFAULTS_TIP, 150, function()
		if confirmLeft then
			confirmLeft = nil
			Glow():Reset()
		else
			confirmLeft = CONFIRM_TIME
		end
	end)
	reset:SetPoint("BOTTOMRIGHT", -EDGE, 12)
	local version = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	version:SetPoint("BOTTOMLEFT", EDGE + 4, 17)
	version:SetText(L.GLOW_FOOTER:format(ns.version))

	frame:SetScript("OnUpdate", function(_, elapsed)
		if confirmLeft then
			confirmLeft = confirmLeft - elapsed
			if confirmLeft <= 0 then confirmLeft = nil end
		end
		local text = confirmLeft and L.GLOW_CONFIRM or L.GLOW_DEFAULTS
		if reset:GetText() ~= text then reset:SetText(text) end
	end)
	frame:HookScript("OnShow", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
		Refresh()
	end)
	frame:HookScript("OnHide", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
		confirmLeft = nil
		if Glow():IsZoneShown() then Glow():ShowZone(false) end
		stopListening()
	end)
	for name, shown in pairs(pages) do shown:SetShown(name == openPage) end
	Glow():OnChange(Refresh)
end

function Window:Toggle(show)
	if not frame then Build() end
	if show == nil then show = not frame:IsShown() end
	frame:SetShown(show)
end

function Window:Open(page)
	self:Toggle(true)
	Open(page or openPage)
end
