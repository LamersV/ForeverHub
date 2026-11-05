--[[
	Performance: a small always-visible line with FPS, latency, Lua memory and
	the clock. One update per second using only cheap calls; the per-addon memory
	(costly: it walks every addon) is read only while the tooltip is open, at
	most every 10 seconds and never in combat.
--]]

local _, ns = ...
local L = ns.L

local Performance = ns:NewModule("Performance")

local GetFramerate, GetNetStats, GetTime = GetFramerate, GetNetStats, GetTime
local floor, max, min = math.floor, math.max, math.min

local POSITION = "ForeverHubPerformance"
local SAMPLES = 60 -- seconds of FPS kept for the average
local ADDON_ROWS = 8
local GREEN, YELLOW, RED = "|cff40ff40", "|cffffd200", "|cffff4030"

local frame, settings, ticker
local samples, sampleIndex, sampleCount = {}, 0, 0
local lowest
local ignoreUntil = 0 -- loading screens drag the FPS down; skip a few seconds after them
local parts = {}
local addons, addonCount, addonTime = {}, 0, -math.huge

local function FpsColor(fps)
	if fps >= 50 then return GREEN elseif fps >= 30 then return YELLOW end
	return RED
end

local function MsColor(ms)
	if ms < 100 then return GREEN elseif ms < 250 then return YELLOW end
	return RED
end

local function Memory(kb)
	if kb >= 1024 then
		return ("%.1f MB"):format(kb / 1024)
	end
	return ("%.0f KB"):format(kb)
end

local function Latency()
	local _, _, home, world = GetNetStats()
	return home or 0, world or 0
end

local function Sample(fps)
	if GetTime() < ignoreUntil then return end
	sampleIndex = sampleIndex % SAMPLES + 1
	samples[sampleIndex] = fps
	sampleCount = min(sampleCount + 1, SAMPLES)
	if not lowest or fps < lowest then
		lowest = fps
	end
end

local function Average()
	if sampleCount == 0 then return end
	local total = 0
	for i = 1, sampleCount do
		total = total + samples[i]
	end
	return total / sampleCount
end

local function Update()
	if not frame then return end
	local fps = GetFramerate()
	Sample(fps)

	local n = 0
	if settings.fps then
		n = n + 1
		parts[n] = ("%s%d|r fps"):format(FpsColor(fps), floor(fps + 0.5))
	end
	if settings.latency then
		-- the worse of the two: either one makes the game feel slow
		local ms = max(Latency())
		n = n + 1
		parts[n] = ("%s%d|r ms"):format(MsColor(ms), ms)
	end
	if settings.memory then
		n = n + 1
		parts[n] = Memory(collectgarbage("count"))
	end
	if settings.clock then
		n = n + 1
		parts[n] = date("%H:%M")
	end
	for i = n + 1, #parts do
		parts[i] = nil
	end

	frame.Text:SetText(table.concat(parts, "  ·  "))
	frame:SetSize(floor(frame.Text:GetStringWidth() + 16), 20)
end


--[[ Tooltip ]]--

local function SortByMemory(a, b)
	return a.kb > b.kb
end

-- Fills the reused `addons` rows; returns the total of the addons' memory.
local function ReadAddons()
	if not (UpdateAddOnMemoryUsage and GetAddOnMemoryUsage) then return end
	if InCombatLockdown() then return end
	if GetTime() - addonTime >= 10 then
		addonTime = GetTime()
		UpdateAddOnMemoryUsage()
	end

	addonCount = 0
	for i = 1, C_AddOns.GetNumAddOns() do
		if C_AddOns.IsAddOnLoaded(i) then
			local kb = GetAddOnMemoryUsage(i)
			if kb and kb > 0 then
				addonCount = addonCount + 1
				local row = addons[addonCount]
				if not row then
					row = {}
					addons[addonCount] = row
				end
				local name, title = C_AddOns.GetAddOnInfo(i)
				row.name = title or name
				row.kb = kb
			end
		end
	end
	for i = addonCount + 1, #addons do
		addons[i] = nil
	end
	table.sort(addons, SortByMemory)
	return true
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
	GameTooltip:SetText(L.PERF_TITLE)

	local fps = GetFramerate()
	local average = Average()
	GameTooltip:AddDoubleLine(L.PERF_FPS, ("%s%.0f|r"):format(FpsColor(fps), fps), 1, 1, 1)
	if average then
		GameTooltip:AddDoubleLine(L.PERF_FPS_AVERAGE, ("%.0f"):format(average), 1, 1, 1, 1, 1, 1)
	end
	if lowest then
		GameTooltip:AddDoubleLine(L.PERF_FPS_LOWEST, ("%.0f"):format(lowest), 1, 1, 1, 1, 1, 1)
	end
	if fps > 0 then
		GameTooltip:AddDoubleLine(L.PERF_FRAME_TIME, ("%.1f ms"):format(1000 / fps), 1, 1, 1, 1, 1, 1)
	end

	local home, world = Latency()
	local bandwidthIn, bandwidthOut = GetNetStats()
	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L.PERF_LATENCY_HOME, ("%s%d|r ms"):format(MsColor(home), home), 1, 1, 1)
	GameTooltip:AddDoubleLine(L.PERF_LATENCY_WORLD, ("%s%d|r ms"):format(MsColor(world), world), 1, 1, 1)
	if bandwidthIn then
		GameTooltip:AddDoubleLine(L.PERF_BANDWIDTH, ("%.1f / %.1f KB/s"):format(bandwidthIn, bandwidthOut or 0), 1, 1, 1, 1, 1, 1)
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddDoubleLine(L.PERF_MEMORY, Memory(collectgarbage("count")), 1, 1, 1, 1, 1, 1)
	if ReadAddons() then
		for i = 1, min(addonCount, ADDON_ROWS) do
			local row = addons[i]
			GameTooltip:AddDoubleLine("   " .. row.name, Memory(row.kb), 0.8, 0.8, 0.8, 0.8, 0.8, 0.8)
		end
		if addonCount > ADDON_ROWS then
			GameTooltip:AddLine("   " .. L.PERF_MORE:format(addonCount - ADDON_ROWS), 0.6, 0.6, 0.6)
		end
	elseif InCombatLockdown() then
		GameTooltip:AddLine("   " .. L.PERF_ADDONS_COMBAT, 0.6, 0.6, 0.6)
	end

	GameTooltip:AddLine(" ")
	GameTooltip:AddLine(L.PERF_HINT, 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

local function RefreshTooltip()
	if frame and GameTooltip:IsOwned(frame) then
		OnEnter(frame)
	end
end


--[[ Frame ]]--

local function DefaultPoint()
	frame:ClearAllPoints()
	frame:SetPoint("TOP", UIParent, "TOP", 0, -4)
end

local function Tick()
	Update()
	RefreshTooltip()
end

local function CollectGarbage()
	if InCombatLockdown() then
		ns:Print(L.PERF_COMBAT)
		return
	end
	local before = collectgarbage("count")
	collectgarbage("collect")
	ns:Print(L.PERF_FREED:format(Memory(max(0, before - collectgarbage("count")))))
	Tick()
end

local function Create()
	frame = CreateFrame("Frame", "ForeverHubPerformance", UIParent, "BackdropTemplate")
	frame:SetFrameStrata("MEDIUM")
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8x8"})
	frame:SetBackdropColor(0, 0, 0, 0.45)

	frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.Text:SetPoint("CENTER")

	local pos = ns.db.positions[POSITION]
	if pos then
		frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
	else
		DefaultPoint()
	end

	frame:SetScript("OnDragStart", function(self)
		GameTooltip_Hide()
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		self:SetUserPlaced(false)
		local point, _, relPoint, x, y = self:GetPoint(1)
		ns.db.positions[POSITION] = {point, relPoint, x, y}
	end)
	frame:SetScript("OnMouseUp", function(_, mouse)
		if mouse == "RightButton" then
			Performance:ResetStats()
		elseif mouse == "LeftButton" and IsShiftKeyDown() then
			CollectGarbage()
		end
	end)
	frame:SetScript("OnEnter", OnEnter)
	frame:SetScript("OnLeave", GameTooltip_Hide)
	frame:SetScript("OnShow", function()
		Update()
		ticker = ticker or C_Timer.NewTicker(1, Tick)
	end)
	frame:SetScript("OnHide", function()
		if ticker then
			ticker:Cancel()
			ticker = nil
		end
	end)
	frame:Hide()
end

function Performance:ResetStats()
	wipe(samples)
	sampleIndex, sampleCount, lowest = 0, 0, nil
	RefreshTooltip()
end

function Performance:ResetPosition()
	ns.db.positions[POSITION] = nil
	if frame then
		DefaultPoint()
	end
end

function Performance:Refresh()
	local show = settings.show and (settings.fps or settings.latency or settings.memory or settings.clock)
	if show and not frame then
		Create()
	end
	if frame then
		frame:SetShown(show)
		if show then
			Update()
		end
	end
end

function Performance:Toggle()
	settings.show = not settings.show
	self:Refresh()
end

function Performance:OnInitialize()
	settings = ns.db.performance
end

function Performance:OnLogin()
	ns:RegisterEvent("LOADING_SCREEN_ENABLED", function()
		ignoreUntil = math.huge
	end)
	ns:RegisterEvent("PLAYER_ENTERING_WORLD", function()
		ignoreUntil = GetTime() + 5
	end)
	ns:RegisterCommand("perf", function() Performance:Toggle() end, L.PERF_COMMAND)
	self:Refresh()
end
