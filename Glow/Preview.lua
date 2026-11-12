--[[
	Glow preview: like the game's dressing room shows gear on the character, the preview
	shows the effect on a world object: its 3D model (drag to turn, right-drag to move,
	wheel to zoom), the nameplate the game would give it and the light riding it, going
	through its states in a loop.

	The light sits a fixed number of pixels under the nameplate, not on the object. To
	show it where the game would, the preview copies the game's geometry: the nameplate
	floats about two yards above the foot of the object, and its place on the screen is
	that point seen by the camera. Zooming in moves the light away from the object exactly
	as walking towards it does.

	The preview has its own glow, so the light on a real target stays where it is.
--]]

local _, ns = ...
local L = ns.L
local FX = ns.GlowFX

local Preview = {}
ns.GlowPreview = Preview

local FOV = math.rad(30)
local PITCH = math.asin(0.36) -- the camera looks down like the game's usual camera
local START_YAW = math.pi - 0.5 -- three-quarter view
local TURN_SPEED = 0.012 -- radians per pixel dragged
local ZOOM_STEP = 0.88
local ZOOM_NEAR, ZOOM_FAR = 0.25, 2.5 -- distance limits, in fractions of the starting one
local PAN_REACH = 4 -- yards the camera may move away from the object
local PLATE_HEIGHT = 2 -- the nameplate of an object floats about 2 yards above its foot
local UNITS_PER_YARD = 40 -- at the usual distance, a yard covers about 40 interface units
local MAX_HEIGHT, MAX_WIDTH = 1.8, 2.4 -- model files are bigger than the objects in game
local PLATE_CLEAR = 0.2 -- the nameplate stays at least this far above the model
local STAGES = {{"far", 3}, {"ready", 4.5}, {"locked", 2.5}}

-- client file IDs of a model per category (from the community listfile); loot shows the
-- character itself, lying dead
local MODELS = {
	ore = 219514, -- copper_miningnode_01
	herb = 219481, -- bush_peacebloom01
	quest = 198168, -- stormwindcrate01
	chest = 219372, -- treasurechest01
	bobber = 201000, -- g_fishingbobber
	other = 199999, -- postboxhuman
}
local DEAD_ANIMATION = 6

local view, scene, actor, plate, glow, label
local caption, notice, hint
local category, lookCategory = "ore", nil
local fitted, dirty = true, true
local foot, target = {0, 0, 0}, {0, 0, 0}
local plateHeight = PLATE_HEIGHT
local yaw, distance, fitDistance = START_YAW, 10, 10
local signX, signY = 1, 1
local drag
local stage, stageLeft = 1, STAGES[1][2]

local function Project(x, y, z)
	local px, py = scene:Project3DPointTo2D(x, y, z)
	if not px or not py then return end
	local scale = scene:GetEffectiveScale()
	return px / scale, py / scale
end

local function PlaceCamera()
	local flat = math.cos(PITCH)
	local x, y, z = flat * math.cos(yaw), flat * math.sin(yaw), -math.sin(PITCH)
	scene:SetCameraPosition(target[1] - x * distance, target[2] - y * distance, target[3] - z * distance)
	scene:SetCameraOrientationByYawPitchRoll(yaw, PITCH, 0)
	scene:SetLightDirection(x, y, z)
end

-- The nameplate goes where this camera sees the point above the object's foot.
local function UpdateView()
	PlaceCamera()
	local x, y = Project(foot[1], foot[2], foot[3] + plateHeight)
	if x then
		plate:ClearAllPoints()
		plate:SetPoint("CENTER", view, "BOTTOMLEFT", x, y)
	end
	dirty = false
end

-- Frames the model once loaded: small models as they are, big ones shrunk to the size of
-- the object in game; the camera far enough for a yard to cover UNITS_PER_YARD.
local function Fit()
	fitted = true
	local ok, x1, y1, z1, x2, y2, z2 = pcall(actor.GetActiveBoundingBox, actor)
	local scale = 1
	plateHeight = PLATE_HEIGHT
	if ok and x1 and z2 then
		local height, width = z2 - z1, math.max(x2 - x1, y2 - y1)
		if height > 0 and width > 0 then scale = math.min(1, MAX_HEIGHT / height, MAX_WIDTH / width) end
		foot[1], foot[2], foot[3] = (x1 + x2) / 2 * scale, (y1 + y2) / 2 * scale, z1 * scale
		plateHeight = math.max(PLATE_HEIGHT, height * scale + PLATE_CLEAR)
	else
		foot[1], foot[2], foot[3] = 0, 0, 0
	end
	if actor.SetScale then pcall(actor.SetScale, actor, scale) end
	target[1], target[2], target[3] = foot[1], foot[2], foot[3] + plateHeight / 2
	yaw = START_YAW
	fitDistance = view:GetHeight() / (2 * math.tan(FOV / 2) * UNITS_PER_YARD)
	distance = fitDistance
	PlaceCamera()
	-- which way the camera's axes go on the screen, for panning
	local rx, ry, rz = scene:GetCameraRight()
	local ux, uy, uz = scene:GetCameraUp()
	local x, y = Project(target[1], target[2], target[3])
	local right = Project(target[1] + rx, target[2] + ry, target[3] + rz)
	local _, up = Project(target[1] + ux, target[2] + uy, target[3] + uz)
	if x and right and up then
		signX, signY = right >= x and 1 or -1, up >= y and 1 or -1
	end
	UpdateView()
	actor:Show()
end

local function Drag()
	local scale = view:GetEffectiveScale()
	local x, y = GetCursorPosition()
	x, y = x / scale, y / scale
	local dx, dy = x - drag.x, y - drag.y
	if dx == 0 and dy == 0 then return end
	drag.x, drag.y = x, y
	dirty = true
	if not drag.pan then
		yaw = yaw - dx * TURN_SPEED
		return
	end
	-- the object follows the cursor: the point looked at slides the other way
	local perYard = UNITS_PER_YARD * fitDistance / distance
	local right, up = -dx / perYard * signX, -dy / perYard * signY
	local rx, ry, rz = scene:GetCameraRight()
	local ux, uy, uz = scene:GetCameraUp()
	local home = {foot[1], foot[2], foot[3] + plateHeight / 2}
	local axes = {{rx, ux}, {ry, uy}, {rz, uz}}
	local away = 0
	for i = 1, 3 do
		target[i] = target[i] + axes[i][1] * right + axes[i][2] * up
		away = away + (target[i] - home[i]) ^ 2
	end
	away = math.sqrt(away)
	if away > PAN_REACH then
		for i = 1, 3 do target[i] = home[i] + (target[i] - home[i]) * PAN_REACH / away end
	end
end

local function CreateScene()
	local ok, frame = pcall(CreateFrame, "ModelScene", nil, view)
	if not ok or not frame then return end
	local made
	ok = pcall(function()
		frame:SetAllPoints()
		frame:SetCameraFieldOfView(FOV)
		frame:SetCameraNearClip(0.05)
		frame:SetCameraFarClip(500)
		frame:SetLightVisible(true)
		frame:SetLightAmbientColor(0.75, 0.75, 0.75)
		frame:SetLightDiffuseColor(1, 1, 1)
		made = frame:CreateActor(nil, "ModelSceneActorTemplate")
	end)
	if ok and made then
		scene, actor = frame, made
	else
		frame:Hide()
	end
end

local function SampleName()
	return L["GLOW_SAMPLE_" .. category:upper()]
end

-- Puts the glow and the label on the nameplate with the current settings.
local function Restyle(instant)
	local Glow = ns.Glow
	Glow:Style(glow, lookCategory, instant, category)
	glow:Move(plate, Glow:Get("offsetY", lookCategory), Glow:Get("followAlpha", lookCategory))
	label:Show(plate, nil, SampleName(), lookCategory, category == "quest" and "0/1" or nil,
		Glow:Get("followAlpha", lookCategory), category)
	label:SetState(STAGES[stage][1], Glow:GetColor(category))
end

local function StartLoop()
	stage, stageLeft = 1, STAGES[1][2]
	glow:SetState("far", true)
	Restyle(true)
	if not glow:IsAttached() then
		local Glow = ns.Glow
		glow:Attach(plate, Glow:Get("offsetY", lookCategory), Glow:Get("followAlpha", lookCategory))
	end
end

local function LoadModel()
	local loaded = false
	if actor then
		actor:Hide()
		if actor.SetScale then pcall(actor.SetScale, actor, 1) end
		if category == "loot" then
			loaded = pcall(actor.SetModelByUnit, actor, "player") and true or false
			if loaded then pcall(actor.SetAnimation, actor, DEAD_ANIMATION) end
		else
			local ok, success = pcall(actor.SetModelByFileID, actor, MODELS[category] or MODELS.other)
			loaded = ok and success ~= false
		end
		scene:SetShown(loaded)
	end
	fitted = not loaded
	plate:ClearAllPoints()
	plate:SetPoint("CENTER", view, "CENTER", 0, 45)
	notice:SetShown(not loaded)
	hint:SetShown(loaded)
end

local function OnUpdate(_, elapsed)
	stageLeft = stageLeft - elapsed
	if stageLeft <= 0 then
		stage = stage % #STAGES + 1
		stageLeft = STAGES[stage][2]
		local stateName = STAGES[stage][1]
		glow:SetState(stateName)
		label:SetState(stateName, ns.Glow:GetColor(category))
		caption:SetText(L["GLOW_STATE_" .. stateName:upper()])
	end
	if not fitted then
		if actor:IsLoaded() then Fit() end
	elseif scene and scene:IsShown() then
		if drag then Drag() end
		if dirty then UpdateView() end
	end
end

-- Creates the preview in parent, at that size. Returns the view.
function Preview:Create(parent, width, height)
	view = CreateFrame("Frame", nil, parent)
	view:SetSize(width, height)
	view:SetClipsChildren(true)
	view:EnableMouse(true)
	view:EnableMouseWheel(true)
	local background = view:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.05, 0.05, 0.07, 1)
	-- the dressing room backdrop, on the clients that have it
	local class = select(2, UnitClass("player"))
	local atlas = class and "dressingroom-background-" .. class:lower()
	if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then background:SetAtlas(atlas) end

	CreateScene()
	plate = CreateFrame("Frame", nil, view)
	plate:SetSize(1, 1)
	plate:SetFrameLevel(view:GetFrameLevel() + 5)
	glow = FX.New()
	label = ns.Glow.NewLabel()

	local texts = CreateFrame("Frame", nil, view)
	texts:SetAllPoints()
	texts:SetFrameLevel(view:GetFrameLevel() + 8)
	caption = texts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	caption:SetPoint("BOTTOM", 0, 8)
	notice = texts:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	notice:SetPoint("TOP", 0, -8)
	notice:SetText(L.GLOW_PREVIEW_NO_MODEL)
	hint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	hint:SetPoint("TOP", view, "BOTTOM", 0, -6)
	hint:SetWidth(width - 8)
	hint:SetText(L.GLOW_PREVIEW_HINT)

	view:SetScript("OnMouseDown", function(_, button)
		if not scene or not fitted then return end
		local scale = view:GetEffectiveScale()
		local x, y = GetCursorPosition()
		drag = {x = x / scale, y = y / scale, pan = button == "RightButton"}
	end)
	view:SetScript("OnMouseUp", function() drag = nil end)
	view:SetScript("OnMouseWheel", function(_, delta)
		if not scene or not fitted then return end
		distance = math.max(fitDistance * ZOOM_NEAR, math.min(fitDistance * ZOOM_FAR, distance * ZOOM_STEP ^ delta))
		dirty = true
	end)
	view:SetScript("OnShow", function()
		LoadModel()
		StartLoop()
		caption:SetText(L.GLOW_STATE_FAR)
	end)
	view:SetScript("OnHide", function()
		drag = nil
		glow:Detach()
		label:Hide()
	end)
	view:SetScript("OnUpdate", OnUpdate)
	if view:IsVisible() then view:GetScript("OnShow")(view) end
	return view
end

-- Shows a category's model (look: the category whose settings apply, nil for all objects).
function Preview:SetCategory(shown, look)
	local changed = shown ~= category
	category, lookCategory = shown, look
	if not (view and view:IsVisible()) then return end
	if changed then LoadModel() end
	Restyle(changed)
end

-- Settings changed: the preview follows at once.
function Preview:Refresh()
	if view and view:IsVisible() then Restyle() end
end
