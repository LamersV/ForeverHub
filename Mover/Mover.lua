--[[
	Mover - drag and scale Blizzard windows.

	Positions are re-applied from a SetPoint hook, so they survive the UI panel
	manager (and anything else) repositioning a window, with no polling.
--]]

local _, ns = ...
local L = ns.L

local Mover = ns:NewModule("Mover")

local MIN_SCALE, MAX_SCALE, SCALE_STEP = 0.5, 2, 0.05

local registry = {} -- frame -> data
local handleOwner = {} -- drag handle -> root frame
local sessionPositions = {}
local moving
local settings

-- Frames owned by the bags module while it is active.
local bagFrames = {BankFrame = true, ContainerFrameCombinedBags = true}

local InCombatLockdown = InCombatLockdown

local function Resolve(path)
	local object
	for key in path:gmatch("[^%.]+") do
		if object == nil then
			object = _G[key]
		else
			object = object[key]
		end
		if type(object) ~= "table" then
			return nil
		end
	end
	return object and object.GetObjectType and object or nil
end

local function Positions()
	return settings.save == "always" and settings.positions or sessionPositions
end

local function IsLocked(frame)
	return InCombatLockdown() and frame:IsProtected()
end

local function ModifierDown()
	local mod = settings.modifier
	return mod == "NONE"
		or (mod == "SHIFT" and IsShiftKeyDown())
		or (mod == "CTRL" and IsControlKeyDown())
		or (mod == "ALT" and IsAltKeyDown())
end


--[[ Positioning ]]--

local function Apply(frame)
	local data = registry[frame]
	local pos = data and Positions()[data.name]
	if not pos then return end

	if IsLocked(frame) then
		return ns:RunOutOfCombat("mover:" .. data.name, function() Apply(frame) end)
	end
	if frame.IsMaximized and frame:IsMaximized() then return end -- world map

	data.applying = true
	if pos.scale and frame:GetScale() ~= pos.scale then
		frame:SetScale(pos.scale)
	end
	if pos.point then
		frame:ClearAllPoints()
		frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
	end
	data.applying = false
end

-- Keeps the original anchors so a reset puts the window back where Blizzard had it.
local function RememberOriginal(frame, data)
	if data.original then return end
	data.original = {}
	for i = 1, frame:GetNumPoints() do
		data.original[i] = {frame:GetPoint(i)}
	end
end

local function Save(frame)
	local data = registry[frame]
	local point, _, relPoint, x, y = frame:GetPoint(1)
	if not point then return end

	local pos = Positions()[data.name] or {}
	pos.point, pos.relPoint, pos.x, pos.y = point, relPoint, x, y
	local scale = frame:GetScale()
	pos.scale = math.abs(scale - 1) > 0.001 and scale or nil
	Positions()[data.name] = pos
end

local function Reset(frame)
	local data = registry[frame]
	if IsLocked(frame) then return end

	Positions()[data.name] = nil
	data.applying = true
	frame:SetScale(1)
	if data.original and #data.original > 0 then
		frame:ClearAllPoints()
		for _, point in ipairs(data.original) do
			frame:SetPoint(unpack(point))
		end
	end
	data.applying = false
	data.original = nil
end


--[[ Scripts ]]--

local function OnMouseDown(self, button)
	local frame = handleOwner[self] or self
	if IsLocked(frame) then return end

	if button == "LeftButton" and ModifierDown() then
		RememberOriginal(frame, registry[frame])
		frame:StartMoving()
		moving = frame
	elseif button == "RightButton" and IsShiftKeyDown() then
		Reset(frame)
	end
end

local function OnMouseUp()
	if moving then
		local frame = moving
		moving = nil
		frame:StopMovingOrSizing()
		frame:SetUserPlaced(false) -- keep it out of the layout cache
		Save(frame)
	end
end

local function OnMouseWheel(self, delta)
	if not (settings.scaling and IsControlKeyDown()) then return end
	local frame = handleOwner[self] or self
	if IsLocked(frame) then return end

	local old = frame:GetScale()
	local new = math.max(MIN_SCALE, math.min(MAX_SCALE, old + delta * SCALE_STEP))
	if new == old then return end

	-- scale around the top-left corner so the window does not jump
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left then return end
	RememberOriginal(frame, registry[frame])

	local before = frame:GetEffectiveScale()
	frame:SetScale(new)
	local after = frame:GetEffectiveScale()
	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * before / after, top * before / after)
	Save(frame)
end

local function OnHide(frame)
	if moving == frame then
		OnMouseUp()
	end
	if settings.save == "off" then
		local data = registry[frame]
		if Positions()[data.name] then
			Reset(frame)
		end
	end
end

local OnSetPoint = ns:Track("mover:setpoint", function(frame) -- /fh mem
	local data = registry[frame]
	if not data.applying and moving ~= frame then
		Apply(frame)
	end
end)


--[[ Registration ]]--

local function Setup(frame, data, handles)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	if not frame:IsMouseEnabled() then
		frame:EnableMouse(true)
	end

	frame:HookScript("OnMouseDown", OnMouseDown)
	frame:HookScript("OnMouseUp", OnMouseUp)
	frame:HookScript("OnHide", OnHide)
	frame:HookScript("OnShow", Apply) -- for windows that Blizzard positions only once
	if settings.scaling then
		frame:EnableMouseWheel(true)
		frame:HookScript("OnMouseWheel", OnMouseWheel)
	end
	hooksecurefunc(frame, "SetPoint", OnSetPoint)

	if type(handles) == "table" then
		for _, path in ipairs(handles) do
			local handle = Resolve(path)
			if handle and not handleOwner[handle] and not registry[handle] and handle.HookScript then
				handleOwner[handle] = frame
				handle:HookScript("OnMouseDown", OnMouseDown)
				handle:HookScript("OnMouseUp", OnMouseUp)
			end
		end
	end

	if frame:IsShown() then
		Apply(frame)
	end
end

local function Register(name, handles)
	local frame = Resolve(name)
	if not frame or registry[frame] or handleOwner[frame] then return end
	if frame.IsForbidden and frame:IsForbidden() then return end

	local data = {name = name}
	registry[frame] = data

	if IsLocked(frame) then
		ns:RunOutOfCombat("mover-setup:" .. name, function() Setup(frame, data, handles) end)
	else
		Setup(frame, data, handles)
	end
end

local function RegisterAddon(addon)
	local frames = ns.MoverFrames[addon]
	if not frames then return end

	local skipBags = addon == "" and ns:IsModuleActive("bags")
	for name, handles in pairs(frames) do
		if not (skipBags and bagFrames[name]) then
			Register(name, handles)
		end
	end
	ns.MoverFrames[addon] = nil -- processed
end


--[[ Module ]]--

function Mover:OnInitialize()
	settings = ns.db.mover
end

function Mover:OnLogin()
	if not ns:IsModuleActive("mover") then return end

	RegisterAddon("")
	for addon in pairs(ns.MoverFrames) do
		if C_AddOns.IsAddOnLoaded(addon) then
			RegisterAddon(addon)
		end
	end
	ns:RegisterEvent("ADDON_LOADED", function(_, addon)
		RegisterAddon(addon)
	end)

	ns:RegisterCommand("reset", function() Mover:ResetAll() end, "Reset positions of moved frames")
	self.active = true
end

function Mover:ResetAll()
	for frame in pairs(registry) do
		Reset(frame)
	end
	wipe(sessionPositions)
	wipe(settings.positions)
	ns:Print(L.MOVER_RESET)
end

-- Switching save mode keeps the current layout.
function Mover:SetSaveMode(mode)
	local from = Positions()
	settings.save = mode
	local to = Positions()
	if from ~= to then
		wipe(to)
		for k, v in pairs(from) do
			to[k] = v
		end
		if mode ~= "always" then
			wipe(settings.positions)
		end
	end
end
