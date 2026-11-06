--[[
	Minimap button: left-click opens the error window, right-click the options.
	Drag it around the minimap edge; the angle is saved. A red number shows the
	errors of this session.
--]]

local _, ns = ...
local L = ns.L

local MinimapButton = ns:NewModule("MinimapButton")
local button, settings

local function UpdatePosition()
	local angle = math.rad(settings.angle)
	local x, y = math.cos(angle), math.sin(angle)
	local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
	if shape == "SQUARE" then
		-- push the button out to the corners of a square minimap
		x = math.max(-1, math.min(1, x * 1.414))
		y = math.max(-1, math.min(1, y * 1.414))
	end
	local radiusX = Minimap:GetWidth() / 2 + 5
	local radiusY = Minimap:GetHeight() / 2 + 5
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x * radiusX, y * radiusY)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local px, py = GetCursorPosition()
	local scale = Minimap:GetEffectiveScale()
	settings.angle = math.deg(math.atan2(py / scale - my, px / scale - mx)) % 360
	UpdatePosition()
end

local function UpdateCount()
	if not button then return end
	local count = ns.Errors and ns:IsModuleActive("errors") and ns.Errors:CountSession() or 0
	button.Count:SetText(count > 0 and (count > 99 and "99+" or count) or "")
end

-- A swarm of insects: the button opens the error ("bug") viewer. The first icon this
-- client has is used.
local ICONS = {
	"Interface\\Icons\\Spell_Nature_InsectSwarm",
	"Interface\\Icons\\INV_Misc_AhnQirajTrinket_01",
	"Interface\\Icons\\INV_Misc_Bag_10",
}

local function ButtonIcon()
	if not GetFileIDFromPath then return ICONS[1] end
	for _, path in ipairs(ICONS) do
		if GetFileIDFromPath(path) then
			return path
		end
	end
	return ICONS[#ICONS]
end

local function Create()
	button = CreateFrame("Button", "ForeverHubMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(20, 20)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("TOPLEFT", 7, -5)

	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetTexture(ButtonIcon())
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint("TOPLEFT", 7, -6)
	button.Icon = icon

	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	local count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	count:SetPoint("BOTTOMRIGHT", -3, 4)
	count:SetTextColor(1, 0.25, 0.25)
	button.Count = count

	button:SetScript("OnClick", function(self, mouse)
		ForeverHub_OnCompartmentClick(nil, mouse)
	end)
	button:SetScript("OnEnter", function(self)
		ForeverHub_OnCompartmentEnter(nil, self)
	end)
	button:SetScript("OnLeave", ForeverHub_OnCompartmentLeave)
	button:SetScript("OnDragStart", function(self)
		self:LockHighlight()
		self:SetScript("OnUpdate", OnDragUpdate)
		GameTooltip:Hide()
	end)
	button:SetScript("OnDragStop", function(self)
		self:UnlockHighlight()
		self:SetScript("OnUpdate", nil)
	end)
	-- icon "pressed" feedback
	button:SetScript("OnMouseDown", function() icon:SetTexCoord(0, 1, 0, 1) end)
	button:SetScript("OnMouseUp", function() icon:SetTexCoord(0.05, 0.95, 0.05, 0.95) end)

	UpdatePosition()
	UpdateCount()
end

function MinimapButton:SetShown(shown)
	settings.hide = not shown
	if shown and not button then
		Create()
	end
	if button then
		button:SetShown(shown)
	end
end

function MinimapButton:OnInitialize()
	settings = ns.db.minimap
end

function MinimapButton:OnLogin()
	if not settings.hide then
		Create()
	end
	if ns.Errors and ns.Errors:IsActive() then
		ns.Errors:RegisterListener(function() ns:Defer("minimap-count", UpdateCount) end)
	end
	ns:RegisterCommand("minimap", function()
		MinimapButton:SetShown(settings.hide)
	end, "Show or hide the minimap button")
end
