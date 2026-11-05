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

-- Ranges follow the usual console values; the client may clamp them further,
-- which is why every write is read back.
CVars.list = {
	{name = "groundEffectDensity", label = "CV_DENSITY", desc = "CV_DENSITY_DESC", min = 16, max = 256, step = 8, format = "%d"},
	{name = "groundEffectDist", label = "CV_DIST", desc = "CV_DIST_DESC", min = 10, max = 500, step = 10, format = "%d"},
	{name = "groundEffectFade", label = "CV_FADE", desc = "CV_FADE_DESC", min = 0, max = 500, step = 10, format = "%d"},
	{name = "cameraDistanceMaxZoomFactor", label = "CV_ZOOM", desc = "CV_ZOOM_DESC", min = 1, max = 4, step = 0.1, format = "%.1f"},
}

-- Changing one of these makes the game reset the ground effect variables.
local presets = {graphicsGroundEffects = true, graphicsQuality = true, RAIDgraphicsGroundEffects = true, RAIDgraphicsQuality = true}

local managed = {} -- name -> true for the variables in CVars.list
for _, info in ipairs(CVars.list) do
	managed[info.name] = info
end

local saved -- ns.db.cvars: name -> value chosen by the player
local writing -- set while this module writes, so its own writes are not adopted

function CVars:Exists(name)
	return GetCVar(name) ~= nil
end

function CVars:Get(name)
	return tonumber(GetCVar(name))
end

function CVars:GetDefault(name)
	return GetCVarDefault and tonumber(GetCVarDefault(name))
end

function CVars:IsManaged(name)
	return saved[name] ~= nil
end

local function Write(name, value)
	if not CVars:Exists(name) then return end
	ns:RunOutOfCombat("cvar:" .. name, function()
		writing = true
		SetCVar(name, value)
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
	local default = GetCVarDefault and GetCVarDefault(name)
	if default then
		Write(name, default)
	end
end

function CVars:ResetAll()
	for _, info in ipairs(self.list) do
		self:Reset(info.name)
	end
end

function CVars:ApplyAll()
	for name, value in pairs(saved) do
		if managed[name] and self:Get(name) ~= tonumber(value) then
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
			text = L.CV_GAME:format(info.format:format(current), info.format:format(CVars:GetDefault(name) or current))
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
