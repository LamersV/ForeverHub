--[[
	Action bars: the mana cost of each spell, in blue, on the action buttons.

	Only text is added to Blizzard's secure buttons (no hooks, no attributes),
	so nothing taints them. Events are coalesced into one pass on the next
	frame, when Blizzard has already updated each button's action slot.
--]]

local _, ns = ...

local ActionBars = ns:NewModule("ActionBars")

local issecretvalue = issecretvalue or function() return false end
local GetActionInfo, GetMacroSpell = GetActionInfo, GetMacroSpell
local GetPowerCost = C_Spell and C_Spell.GetSpellPowerCost or GetSpellPowerCost
local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0

local BARS = {"ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
	"MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button"}

local buttons = {} -- every action button found
local labels = {} -- button -> cost font string (created when first needed)
local macroButtons = {} -- buttons showing a macro: their spell changes with modifiers and target
local settings

local function ActionSlot(button)
	local slot = button.action
	if not slot or issecretvalue(slot) then
		slot = button:GetAttribute("action")
	end
	return type(slot) == "number" and slot or nil
end

local function SpellOf(slot)
	local actionType, id, subType = GetActionInfo(slot)
	if actionType == "spell" then
		return id, false
	elseif actionType == "macro" then
		-- newer clients give the macro's spell directly; older ones the macro index
		if subType == "spell" then
			return id, true
		end
		return id and GetMacroSpell(id), true
	end
end

-- Mana cost by spell: the game's answer is a new table each time, so it is read once per
-- spell until level or talents change. Costs that depend on an aura are always read again.
local costCache = {} -- spellID -> cost, or false for none

local function ReadManaCost(spellID)
	local costs = GetPowerCost(spellID)
	if not costs or issecretvalue(costs) then return nil, false end
	local cacheable = true
	local found
	for _, info in ipairs(costs) do
		local cost = info.cost
		local needsAura = info.requiredAuraID and info.requiredAuraID ~= 0
		if needsAura then
			cacheable = false
		end
		if not found and info.type == MANA and cost and not issecretvalue(cost) and cost > 0
			and (not needsAura or info.hasRequiredAura) then
			found = cost
		end
	end
	return found, cacheable
end

local function ManaCost(spellID)
	if not spellID or issecretvalue(spellID) or not GetPowerCost then return end
	local cached = costCache[spellID]
	if cached ~= nil then
		return cached or nil
	end
	local cost, cacheable = ReadManaCost(spellID)
	if cacheable then
		costCache[spellID] = cost or false
	end
	return cost
end

local function UpdateButton(button, slot)
	slot = slot or ActionSlot(button)
	local spellID, isMacro
	if slot then
		spellID, isMacro = SpellOf(slot)
	end
	macroButtons[button] = isMacro or nil

	local cost = settings.manaCost and ManaCost(spellID)
	local label = labels[button]
	if cost then
		if not label then
			label = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
			label:SetPoint("TOPLEFT", 2, -2)
			label:SetTextColor(0.35, 0.65, 1)
			labels[button] = label
		end
		if label.cost ~= cost then
			label.cost = cost
			label:SetText(cost)
		end
		label:Show()
	elseif label then
		label:Hide()
	end
end

local function UpdateAll()
	for i = 1, #buttons do
		UpdateButton(buttons[i])
	end
end

-- Slots named by ACTIONBAR_SLOT_CHANGED this frame: only the buttons showing them are redone.
local changedSlots = {}
local function UpdateSlots()
	for i = 1, #buttons do
		local button = buttons[i]
		local slot = ActionSlot(button)
		if slot and changedSlots[slot] then
			UpdateButton(button, slot)
		end
	end
	wipe(changedSlots)
end

local function UpdateMacros()
	for button in pairs(macroButtons) do
		UpdateButton(button)
	end
end

function ActionBars:Refresh()
	UpdateAll()
end

function ActionBars:OnInitialize()
	settings = ns.db.actionbars
end

function ActionBars:OnLogin()
	for _, prefix in ipairs(BARS) do
		for i = 1, 12 do
			local button = _G[prefix .. i]
			if button then
				buttons[#buttons + 1] = button
			end
		end
	end
	if #buttons == 0 then return end

	local function All()
		if settings.manaCost or next(labels) then
			ns:Defer("actionbars", UpdateAll)
		end
	end
	local function Macros()
		if settings.manaCost and next(macroButtons) then
			ns:Defer("actionbarsMacros", UpdateMacros)
		end
	end

	for _, event in ipairs({"PLAYER_ENTERING_WORLD", "ACTIONBAR_PAGE_CHANGED",
		"UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "UPDATE_MACROS"}) do
		pcall(ns.RegisterEvent, ns, event, All)
	end
	-- costs change with level and talents
	local function CostsChanged()
		wipe(costCache)
		All()
	end
	for _, event in ipairs({"PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE"}) do
		pcall(ns.RegisterEvent, ns, event, CostsChanged)
	end
	-- one slot changed (0 or none: all of them)
	pcall(ns.RegisterEvent, ns, "ACTIONBAR_SLOT_CHANGED", function(_, slot)
		if not settings.manaCost and not next(labels) then return end
		if issecretvalue(slot) or type(slot) ~= "number" or slot == 0 then
			All()
			return
		end
		changedSlots[slot] = true
		ns:Defer("actionbarsSlots", UpdateSlots)
	end)
	-- a macro's spell can depend on [mod] and [harm]/[help] conditions
	ns:RegisterEvent("MODIFIER_STATE_CHANGED", Macros)
	ns:RegisterEvent("PLAYER_TARGET_CHANGED", Macros)
	All()
end
