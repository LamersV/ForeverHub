--[[
	Graphics and camera console variables.

	Only values the player changed here are managed: they are stored in the saved
	variables, applied at login and re-applied when the game's graphics presets
	overwrite them. Untouched variables keep whatever the game decides.
--]]

local _, ns = ...
local L = ns.L

local CVars = ns:NewModule("CVars")

local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar
local GetCVarDefault = C_CVar and C_CVar.GetCVarDefault or GetCVarDefault

local function Choices(prefix)
	return function(value)
		return L[prefix .. math.floor(value + 0.5)] or tostring(value)
	end
end

local function Percent(value)
	return ("%d%%"):format(math.floor(value * 100 + 0.5))
end

local function FpsLimit(value)
	return value == 0 and L.CV_NOLIMIT or ("%d"):format(value)
end

--[[
	Ranges follow the usual console values; the client may clamp them further,
	which is why every write is read back.

	group:   section of the options pages (CVars.groups below)
	desc:    what it does; impact: what it costs, shown with its cost tag
	cost:    "cpu", "gpu" or "both"
	suggest: value applied by "Apply suggested values" (lighter on the CPU)
	toggle:  on/off variable that enables this one (0 here turns it off)
--]]
CVars.list = {
	-- performance: what weighs on the main thread, the usual bottleneck of the game
	{name = "graphicsShadowQuality", group = "perf", label = "CV_SHADOWS", desc = "CV_SHADOWS_DESC",
		impact = "CV_SHADOWS_IMPACT", cost = "both", suggest = 4, min = 0, max = 5, step = 1, format = Choices("CV_SHADOW_")},
	{name = "doodadLodScale", group = "perf", label = "CV_DOODAD", desc = "CV_DOODAD_DESC",
		impact = "CV_DOODAD_IMPACT", cost = "cpu", suggest = 100, min = 50, max = 200, step = 10, format = "%d"},
	{name = "lodObjectFadeScale", group = "perf", label = "CV_OBJFADE", desc = "CV_OBJFADE_DESC",
		impact = "CV_OBJFADE_IMPACT", cost = "cpu", suggest = 100, min = 50, max = 300, step = 10, format = "%d"},
	{name = "physicsLevel", group = "perf", label = "CV_PHYSICS", desc = "CV_PHYSICS_DESC",
		impact = "CV_PHYSICS_IMPACT", cost = "cpu", suggest = 1, min = 0, max = 2, step = 1, format = Choices("CV_PHYSICS_")},
	{name = "RenderScale", group = "perf", label = "CV_RENDERSCALE", desc = "CV_RENDERSCALE_DESC",
		impact = "CV_RENDERSCALE_IMPACT", cost = "gpu", suggest = 1, min = 0.5, max = 2, step = 0.05, format = Percent},
	{name = "maxFPS", group = "perf", toggle = "useMaxFPS", label = "CV_MAXFPS", desc = "CV_MAXFPS_DESC",
		impact = "CV_MAXFPS_IMPACT", cost = "both", min = 0, max = 300, step = 1, format = FpsLimit},

	-- scenery and distance
	{name = "groundEffectDensity", group = "world", label = "CV_DENSITY", desc = "CV_DENSITY_DESC",
		impact = "CV_DENSITY_IMPACT", cost = "both", min = 16, max = 256, step = 8, format = "%d"},
	{name = "groundEffectDist", group = "world", label = "CV_DIST", desc = "CV_DIST_DESC",
		impact = "CV_DIST_IMPACT", cost = "both", min = 10, max = 500, step = 10, format = "%d"},
	{name = "groundEffectFade", group = "world", label = "CV_FADE", desc = "CV_FADE_DESC",
		impact = "CV_FADE_IMPACT", cost = "gpu", min = 0, max = 500, step = 10, format = "%d"},
	{name = "terrainLodDist", group = "world", label = "CV_TERRAIN", desc = "CV_TERRAIN_DESC",
		impact = "CV_TERRAIN_IMPACT", cost = "both", min = 100, max = 1000, step = 25, format = "%d"},
	{name = "lodObjectCullSize", group = "world", label = "CV_OBJCULL", desc = "CV_OBJCULL_DESC",
		impact = "CV_OBJCULL_IMPACT", cost = "cpu", min = 0, max = 40, step = 1, format = "%d"},
	{name = "reflectionMode", group = "world", label = "CV_REFLECTION", desc = "CV_REFLECTION_DESC",
		impact = "CV_REFLECTION_IMPACT", cost = "both", min = 0, max = 3, step = 1, format = "%d"},
	{name = "weatherDensity", group = "world", label = "CV_WEATHER", desc = "CV_WEATHER_DESC",
		impact = "CV_WEATHER_IMPACT", cost = "gpu", min = 0, max = 3, step = 1, format = "%d"},
	{name = "ResampleAlwaysSharpen", group = "world", label = "CV_SHARPEN", desc = "CV_SHARPEN_DESC",
		impact = "CV_SHARPEN_IMPACT", cost = "gpu", bool = true},

	-- camera and nameplates
	{name = "cameraDistanceMaxZoomFactor", group = "camera", label = "CV_ZOOM", desc = "CV_ZOOM_DESC", min = 1, max = 4, step = 0.1, format = "%.1f"},
	{name = "nameplateMaxDistance", group = "camera", label = "CV_NAMEPLATES", desc = "CV_NAMEPLATES_DESC",
		impact = "CV_NAMEPLATES_IMPACT", cost = "cpu", min = 10, max = 60, step = 1, format = "%d"},

	-- buttons, loot and sound
	{name = "ActionButtonUseKeyDown", group = "gameplay", label = "CV_KEYDOWN", desc = "CV_KEYDOWN_DESC", bool = true},
	{name = "countdownForCooldowns", group = "gameplay", label = "CV_COOLDOWNS", desc = "CV_COOLDOWNS_DESC", bool = true},
	{name = "autoLootDefault", group = "gameplay", label = "CV_AUTOLOOT", desc = "CV_AUTOLOOT_DESC", bool = true},
	{name = "Sound_EnableSoundWhenGameIsInBG", group = "gameplay", label = "CV_BGSOUND", desc = "CV_BGSOUND_DESC", bool = true},
}
-- page: the options page each section goes to (Options.lua)
CVars.groups = {
	{key = "perf", page = "graphics", title = "GRAPHICS_PERF", note = "GRAPHICS_PERF_NOTE"},
	{key = "world", page = "graphics", title = "GRAPHICS_WORLD"},
	{key = "camera", page = "camera", title = "CAMERA_SECTION"},
	{key = "gameplay", page = "camera", title = "GAMEPLAY_SECTION"},
}
for _, info in ipairs(CVars.list) do
	if info.bool then
		info.min, info.max, info.step, info.format = 0, 1, 1, "%d"
	end
end

function CVars:Format(info, value)
	local format = info.format
	return type(format) == "function" and format(value) or format:format(value)
end

-- Changing one of these makes the game reset the variables above (ground effects,
-- view distance, objects, shadows, water and weather).
local presets = {}
for _, preset in ipairs({"graphicsQuality", "graphicsGroundEffects", "graphicsGroundClutter", "graphicsViewDistance",
	"graphicsEnvironmentDetail", "graphicsLiquidDetail", "graphicsParticleDensity"}) do
	presets[preset] = true
	presets["RAID" .. preset] = true
end

local managed = {} -- name -> info for the variables in CVars.list
local toggles = {} -- on/off variable -> info of the variable it enables
for _, info in ipairs(CVars.list) do
	managed[info.name] = info
	if info.toggle then
		toggles[info.toggle] = info
	end
end

local saved -- ns.db.cvars: name -> value chosen by the player
local writing -- set while this module writes, so its own writes are not adopted

function CVars:Exists(name)
	return GetCVar(name) ~= nil
end

-- A variable with an on/off toggle reads 0 while the toggle is off.
local function ToggledOff(info, getter)
	return info and info.toggle and GetCVar(info.toggle) ~= nil and getter(info.toggle) == "0"
end

function CVars:Get(name)
	if ToggledOff(managed[name], GetCVar) then return 0 end
	return tonumber(GetCVar(name))
end

function CVars:GetDefault(name)
	if not GetCVarDefault then return end
	if ToggledOff(managed[name], GetCVarDefault) then return 0 end
	return tonumber(GetCVarDefault(name))
end

function CVars:IsManaged(name)
	return saved[name] ~= nil
end

local function Write(name, value)
	if not CVars:Exists(name) then return end
	local toggle = managed[name] and managed[name].toggle
	ns:RunOutOfCombat("cvar:" .. name, function()
		writing = true
		if toggle and GetCVar(toggle) ~= nil then
			-- 0 turns the toggle off and leaves the value itself alone
			SetCVar(toggle, tonumber(value) == 0 and "0" or "1")
			if tonumber(value) ~= 0 then SetCVar(name, value) end
		else
			SetCVar(name, value)
		end
		writing = false
	end)
end

-- Stores and applies a value; returns the value the game actually kept.
function CVars:Set(name, value)
	saved[name] = value
	Write(name, value)
	return self:Get(name)
end

function CVars:Reset(name)
	saved[name] = nil
	if not GetCVarDefault or not self:Exists(name) then return end
	local toggle = managed[name] and managed[name].toggle
	ns:RunOutOfCombat("cvar:" .. name, function()
		writing = true
		local default = GetCVarDefault(name)
		if default then SetCVar(name, default) end
		local toggleDefault = toggle and GetCVar(toggle) ~= nil and GetCVarDefault(toggle)
		if toggleDefault then SetCVar(toggle, toggleDefault) end
		writing = false
	end)
end

-- Applies every suggested value (the lighter ones for the CPU).
function CVars:ApplySuggested()
	for _, info in ipairs(self.list) do
		if info.suggest ~= nil and self:Exists(info.name) then
			self:Set(info.name, info.suggest)
		end
	end
end

function CVars:ResetAll()
	for _, info in ipairs(self.list) do
		self:Reset(info.name)
	end
end

function CVars:ApplyAll()
	for name, value in pairs(saved) do
		local current, wanted = self:Get(name), tonumber(value)
		-- the game keeps floats with extra digits (1.1 reads back as 1.1000000238419)
		if managed[name] and wanted and (not current or math.abs(current - wanted) > 0.001) then
			Write(name, value)
		end
	end
end

local function OnCVarSet(name, value)
	if writing or type(name) ~= "string" then return end
	if managed[name] then
		-- changed by the game options or another addon: follow it when this one manages it
		if saved[name] ~= nil then
			saved[name] = tonumber(value) or saved[name]
		end
	elseif toggles[name] then
		local info = toggles[name]
		if saved[info.name] ~= nil then
			saved[info.name] = CVars:Get(info.name) or saved[info.name]
		end
	elseif presets[name] then
		ns:Defer("cvars-apply", function() CVars:ApplyAll() end)
	end
end

local function PrintValues()
	for _, info in ipairs(CVars.list) do
		local name = info.name
		local current = CVars:Get(name)
		local text
		if current == nil then
			text = L.CV_MISSING
		else
			text = L.CV_GAME:format(CVars:Format(info, current), CVars:Format(info, CVars:GetDefault(name) or current))
			if CVars:IsManaged(name) then
				text = text .. " |cff4fc3f7" .. L.CV_MANAGED .. "|r"
			end
		end
		print(("  |cffffd200%s|r (%s): %s"):format(L[info.label], name, text))
	end
end


--[[ Module ]]--

function CVars:OnInitialize()
	saved = ns.db.cvars
end

function CVars:OnLogin()
	if C_CVar and C_CVar.SetCVar then
		hooksecurefunc(C_CVar, "SetCVar", OnCVarSet)
	end
	if _G.SetCVar and _G.SetCVar ~= (C_CVar and C_CVar.SetCVar) then
		hooksecurefunc("SetCVar", OnCVarSet)
	end
	self:ApplyAll()

	ns:RegisterCommand("cvars", function(arg)
		if arg == "reset" then
			CVars:ResetAll()
			ns:Print(L.CVARS_RESET)
		else
			ns:Print(L.MODULE_GRAPHICS)
			PrintValues()
		end
	end, "Show graphics/camera values (\"/fh cvars reset\" restores the game defaults)")

	-- The game's own taint log (Logs\taint.log) names which addon code tainted a blocked call.
	ns:RegisterCommand("taintlog", function()
		local on = GetCVar("taintLog") ~= "0"
		SetCVar("taintLog", on and "0" or "1")
		ns:Print(on and L.TAINTLOG_OFF or L.TAINTLOG_ON)
	end, "Turn the game's taint log (Logs\\taint.log) on or off")
end
