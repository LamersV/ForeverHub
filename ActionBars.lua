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

local function ManaCost(spellID)
	if not spellID or issecretvalue(spellID) or not GetPowerCost then return end
	local costs = GetPowerCost(spellID)
	if not costs or issecretvalue(costs) then return end
	for _, info in ipairs(costs) do
		local cost = info.cost
		if info.type == MANA and cost and not issecretvalue(cost) and cost > 0
			and (not info.requiredAuraID or info.requiredAuraID == 0 or info.hasRequiredAura) then
			return cost
		end
	end
end

local function UpdateButton(button)
	local slot = ActionSlot(button)
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
		label:SetText(cost)
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

	for _, event in ipairs({"PLAYER_ENTERING_WORLD", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
		"UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED", "UPDATE_MACROS",
		"PLAYER_LEVEL_UP", "PLAYER_TALENT_UPDATE"}) do
		pcall(ns.RegisterEvent, ns, event, All)
	end
	-- a macro's spell can depend on [mod] and [harm]/[help] conditions
	ns:RegisterEvent("MODIFIER_STATE_CHANGED", Macros)
	ns:RegisterEvent("PLAYER_TARGET_CHANGED", Macros)
	All()
end
