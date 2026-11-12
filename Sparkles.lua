--[[
	Quest item sparkle: the game's own loot sparkle on quest items
	(outlineModeShowLootEffectWhenDisabled) is kept on; graphics presets switch it off, so
	it is set again after them.

	The light on the object you are about to use (ore, herbs, quest objects, chests...) is
	the Glow module (Glow\Glow.lua). Both belong to the "sparkles" module switch, which
	stays off while ForeverLootSparkles or Lueur is enabled.
--]]

local _, ns = ...

local Sparkles = ns:NewModule("Sparkles")

local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar

local LOOT_EFFECT = "outlineModeShowLootEffectWhenDisabled"
-- the game resets the sparkle when one of these changes
local PRESETS = {graphicsquality = true, raidgraphicsquality = true, [LOOT_EFFECT:lower()] = true}

local settings
local active

local function Write(name, value)
	value = tostring(value)
	local ok, current = pcall(GetCVar, name)
	if not ok or current == nil or current == value then return end
	pcall(SetCVar, name, value)
end

local function ApplyLootEffect()
	if not active or not settings.questLoot then return end
	ns:RunOutOfCombat("sparkles-loot", function() Write(LOOT_EFFECT, 1) end)
end

function Sparkles:Refresh()
	active = ns:IsModuleActive("sparkles")
	ApplyLootEffect()
	if ns.Glow then ns.Glow:Refresh() end
end

-- Switching the quest sparkle off only takes effect after restarting the game.
function Sparkles:SetQuestLoot(value)
	settings.questLoot = value
	if value then
		ApplyLootEffect()
	elseif active then
		ns:RunOutOfCombat("sparkles-loot", function() Write(LOOT_EFFECT, 0) end)
		ns:Print(ns.L.SPARKLES_RESTART)
	end
end

function Sparkles:OnInitialize()
	settings = ns.db.sparkles
end

function Sparkles:OnLogin()
	active = ns:IsModuleActive("sparkles")
	ApplyLootEffect()
	-- account settings can arrive after login and overwrite it
	C_Timer.After(5, ApplyLootEffect)
	pcall(ns.RegisterEvent, ns, "CVAR_UPDATE", function(_, name)
		if type(name) == "string" and PRESETS[name:lower()] and active and settings.questLoot then
			C_Timer.After(1, ApplyLootEffect)
		end
	end)
end
