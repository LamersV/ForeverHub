--[[
	Small UI building blocks shared by the windows and the options panel.
--]]

local _, ns = ...
local Widgets = {}
ns.Widgets = Widgets

-- Creates a frame with the first template that exists in this client.
function Widgets.CreateWithTemplates(frameType, name, parent, ...)
	for i = 1, select("#", ...) do
		local ok, frame = pcall(CreateFrame, frameType, name, parent, (select(i, ...)))
		if ok and frame then
			return frame
		end
	end
	return CreateFrame(frameType, name, parent)
end

function Widgets.SetTitle(frame, text)
	if frame.SetTitle then
		frame:SetTitle(text)
	else
		local title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
		if title then
			title:SetText(text)
		end
	end
end

-- A standard Blizzard-looking window that can be dragged and remembers its position.
-- positions: table where the point is stored, under key name.
function Widgets.CreateWindow(name, parent, positions, noPortrait)
	local frame = CreateFrame("Frame", name, parent or UIParent, "ButtonFrameTemplate")
	if ButtonFrameTemplate_HideButtonBar then
		ButtonFrameTemplate_HideButtonBar(frame)
	end
	if noPortrait and ButtonFrameTemplate_HidePortrait then
		ButtonFrameTemplate_HidePortrait(frame)
	end
	if frame.Inset then
		frame.Inset:Hide()
	end

	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		if positions then
			ns:SavePosition(positions, name, self)
		end
	end)

	function frame:RestorePosition(defaultPoint, x, y)
		self:ClearAllPoints()
		if not ns:ApplyPosition(positions, name, self) then
			self:SetPoint(defaultPoint, UIParent, defaultPoint, x, y)
		end
	end

	tinsert(UISpecialFrames, name)
	frame:Hide()
	return frame
end

function Widgets.CreateButton(parent, text, width, onClick)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	button:SetSize(width or 90, 22)
	button:SetText(text)
	if onClick then
		button:SetScript("OnClick", onClick)
	end
	return button
end

local function ShowTooltip(self)
	if self.tooltip then
		GameTooltip:SetOwner(self, self.tooltipAnchor or "ANCHOR_TOP")
		GameTooltip:SetText(self.tooltipTitle or self.tooltip, 1, 1, 1)
		if self.tooltipTitle then
			GameTooltip:AddLine(self.tooltip, nil, nil, nil, true)
		end
		GameTooltip:Show()
	end
end

local function HideTooltip()
	GameTooltip:Hide()
end

function Widgets.AttachTooltip(frame, text, title)
	frame.tooltip, frame.tooltipTitle = text, title
	frame:HookScript("OnEnter", ShowTooltip)
	frame:HookScript("OnLeave", HideTooltip)
end

-- Square button with an icon, used in window title bars.
function Widgets.CreateIconButton(parent, icon, size, tooltip)
	local button = CreateFrame("Button", nil, parent)
	button:SetSize(size, size)
	button:SetNormalTexture(icon)
	button:SetPushedTexture(icon)
	button:GetPushedTexture():SetVertexColor(0.7, 0.7, 0.7)
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	if tooltip then
		Widgets.AttachTooltip(button, tooltip)
	end
	return button
end

-- Checkbox bound to get/set callbacks.
function Widgets.CreateCheck(parent, label, get, set, tooltip)
	local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	check:SetSize(26, 26)

	local text = check:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	text:SetPoint("LEFT", check, "RIGHT", 2, 1)
	text:SetText(label)
	check.Label = text
	check:SetHitRectInsets(0, -text:GetStringWidth() - 4, 0, 0)

	check:SetScript("OnShow", function(self) self:SetChecked(get()) end)
	check:SetChecked(get())
	check:SetScript("OnClick", function(self)
		set(self:GetChecked() and true or false)
	end)
	if tooltip then
		Widgets.AttachTooltip(check, tooltip, label)
	end
	return check
end

-- Horizontal slider without relying on version-specific templates.
function Widgets.CreateSlider(parent, label, minValue, maxValue, step, get, set, format)
	local holder = CreateFrame("Frame", nil, parent)
	holder:SetSize(220, 40)

	local title = holder:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	title:SetPoint("TOPLEFT")

	local slider = CreateFrame("Slider", nil, holder, "BackdropTemplate")
	slider:SetOrientation("HORIZONTAL")
	slider:SetPoint("TOPLEFT", 0, -16)
	slider:SetSize(220, 16)
	slider:SetHitRectInsets(0, 0, -6, -6)
	slider:SetBackdrop({
		bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
		edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
		tile = true, tileSize = 8, edgeSize = 8,
		insets = {left = 3, right = 3, top = 6, bottom = 6},
	})
	slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
	slider:SetMinMaxValues(minValue, maxValue)
	slider:SetValueStep(step)
	slider:SetObeyStepOnDrag(true)
	slider:EnableMouseWheel(true)

	local function Refresh(value)
		title:SetText(("%s: |cffffffff%s|r"):format(label, (format or "%d"):format(value)))
	end

	slider:SetScript("OnValueChanged", function(_, value, userInput)
		value = floor(value / step + 0.5) * step
		Refresh(value)
		if userInput then
			set(value)
		end
	end)
	slider:SetScript("OnMouseWheel", function(self, delta)
		local value = math.max(minValue, math.min(maxValue, self:GetValue() + delta * step))
		self:SetValue(value)
		set(value)
	end)
	local function Load()
		local value = get()
		slider:SetValue(value)
		Refresh(value)
	end
	holder:SetScript("OnShow", Load)
	Load()

	holder.Slider = slider
	return holder
end

-- Button that cycles through a list of {value, text} choices.
function Widgets.CreateCycle(parent, label, choices, get, set, width)
	local button = Widgets.CreateButton(parent, "", width or 220)

	local function Refresh()
		local current = get()
		for _, choice in ipairs(choices) do
			if choice[1] == current then
				button:SetText(("%s: |cffffffff%s|r"):format(label, choice[2]))
				return
			end
		end
		button:SetText(label)
	end

	button:SetScript("OnShow", Refresh)
	button:SetScript("OnClick", function()
		local current = get()
		local index = 1
		for i, choice in ipairs(choices) do
			if choice[1] == current then
				index = i % #choices + 1
				break
			end
		end
		set(choices[index][1])
		Refresh()
	end)
	Refresh()
	return button
end

function Widgets.CreateScrollFrame(parent)
	local scroll = Widgets.CreateWithTemplates("ScrollFrame", nil, parent, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	scroll:SetScript("OnSizeChanged", function(self, width)
		child:SetWidth(width)
	end)
	return scroll, child
end
