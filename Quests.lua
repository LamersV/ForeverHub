--[[
	Quests:
	  - the quest level before its name, in the color of its difficulty, in the
	    objective tracker and in the quest log;
	  - the XP of the quests ready to hand in (read by Experience.lua);
	  - on a reward choice, the most valuable item at a vendor and the biggest upgrade,
	    marked on the reward buttons and told in the chat (DialogueUI shows its own
	    window, so the chat line is what is always seen).
--]]

local _, ns = ...
local L = ns.L

local Quests = ns:NewModule("Quests")

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local settings


--[[ Levels ]]--

local function QuestLevel(questID)
	local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
	local info = index and C_QuestLog.GetInfo(index)
	local level = info and info.level
	if type(level) == "number" and level > 0 then
		return level
	end
end

-- "[16] Name", the number in the difficulty color; nil when already tagged or unknown.
-- Forever's quest log already writes "[16] Name" itself, so any leading "[number]"
-- (colored or not) counts as tagged.
local function Tagged(level, text)
	if type(text) ~= "string" or text == "" then return end
	local plain = text:gsub("^%s*|c%x%x%x%x%x%x%x%x", "")
	if plain:find("^%s*%[%d") then return end
	local color = GetQuestDifficultyColor(level)
	return ("|cff%02x%02x%02x[%d]|r %s"):format(color.r * 255, color.g * 255, color.b * 255, level, text)
end

local QUEST_MODULES = {}

local function TagBlock(block)
	if not settings.questLevels or not block then return end
	local module = block.parentModule
	if module and next(QUEST_MODULES) and not QUEST_MODULES[module] then return end
	local questID, header = block.id, block.HeaderText
	if type(questID) ~= "number" or not header then return end
	local level = QuestLevel(questID)
	local text = level and Tagged(level, header:GetText())
	if text then
		header:SetText(text)
	end
end

local function TagLog()
	if not settings.questLevels then return end
	local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
	if pool and pool.EnumerateActive then
		for button in pool:EnumerateActive() do
			local level = button.questID and QuestLevel(button.questID)
			local fontString = button.Text or (button.GetFontString and button:GetFontString())
			local text = level and fontString and Tagged(level, fontString:GetText())
			if text then
				fontString:SetText(text)
			end
		end
	end
end

-- Older quest log (QuestLogFrame with QuestLogTitleN buttons).
local function TagClassicLog()
	if not settings.questLevels or not GetQuestLogTitle then return end
	for i = 1, QUESTS_DISPLAYED or 0 do
		local button = _G["QuestLogTitle" .. i]
		if button and button:IsShown() then
			local title, level, _, isHeader = GetQuestLogTitle(button:GetID())
			local text = not isHeader and type(level) == "number" and level > 0 and Tagged(level, title)
			if text then
				button:SetText(text)
			end
		end
	end
end

local function HookTracker()
	local tag = ns:Track("quests:tracker", TagBlock) -- /fh mem
	for _, name in ipairs({"QuestObjectiveTracker", "CampaignQuestObjectiveTracker"}) do
		local module = _G[name]
		if module then
			QUEST_MODULES[module] = true
			if module.UpdateSingle then
				hooksecurefunc(module, "UpdateSingle", function(self, quest)
					local questID = quest and quest.GetID and quest:GetID()
					local block = questID and self.GetExistingBlock and self:GetExistingBlock(questID)
					if block then tag(block) end
				end)
			end
		end
	end
	if ObjectiveTrackerBlockMixin and ObjectiveTrackerBlockMixin.SetHeader then
		hooksecurefunc(ObjectiveTrackerBlockMixin, "SetHeader", tag)
	end
	-- older tracker
	if QUEST_TRACKER_MODULE and QUEST_TRACKER_MODULE.SetBlockHeader then
		QUEST_MODULES[QUEST_TRACKER_MODULE] = true
		hooksecurefunc(QUEST_TRACKER_MODULE, "SetBlockHeader", function(_, block) tag(block) end)
	end
	if QuestLogQuests_Update then
		hooksecurefunc("QuestLogQuests_Update", ns:Track("quests:log", TagLog))
	end
	if QuestLog_Update then
		hooksecurefunc("QuestLog_Update", ns:Track("quests:log", TagClassicLog))
	end
end


--[[ XP of the quests ready to hand in ]]--

local readyXP, readyCount, readyDirty = 0, 0, true

local function IsReady(questID)
	if C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(questID) then return true end
	return C_QuestLog.IsComplete and C_QuestLog.IsComplete(questID) or false
end

function Quests:ReadyXP()
	if readyDirty then
		readyDirty = false
		readyXP, readyCount = 0, 0
		for index = 1, C_QuestLog.GetNumQuestLogEntries() do
			local info = C_QuestLog.GetInfo(index)
			local questID = info and not info.isHeader and info.questID
			if questID and questID > 0 and IsReady(questID) then
				local ok, xp = pcall(GetQuestLogRewardXP, questID)
				readyCount = readyCount + 1
				if ok and type(xp) == "number" then
					readyXP = readyXP + xp
				end
			end
		end
	end
	return readyXP, readyCount
end


--[[ Best reward ]]--

local marks = {} -- reward button -> {Coin, Upgrade}

local function Mark(index, value, upgrade)
	local button = QuestInfo_GetRewardButton and QuestInfoFrame and QuestInfoFrame.rewardsFrame
		and QuestInfo_GetRewardButton(QuestInfoFrame.rewardsFrame, index)
	if not button then return end
	local mark = marks[button]
	if not mark then
		mark = {}
		mark.Coin = button:CreateTexture(nil, "OVERLAY", nil, 7)
		mark.Coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
		mark.Coin:SetSize(14, 14)
		mark.Coin:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
		mark.Upgrade = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
		mark.Upgrade:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 2, 2)
		mark.Upgrade:SetTextColor(0.2, 1, 0.2)
		marks[button] = mark
	end
	mark.Coin:SetShown(value)
	mark.Upgrade:SetText(upgrade or "")
end

local function ClearMarks()
	for _, mark in pairs(marks) do
		mark.Coin:Hide()
		mark.Upgrade:SetText("")
	end
end

local function UpgradeText(result)
	if result == "new" then return "+" end
	if type(result) == "number" and result >= 0.5 then
		return ("+%d%%"):format(math.floor(result + 0.5))
	end
end

local rewardRound = 0 -- a new QUEST_COMPLETE makes the pending retries of the last one stop

local function CheckRewards(tries, round)
	if round and round ~= rewardRound then return end
	if not round then
		rewardRound = rewardRound + 1
		round = rewardRound
	end
	ClearMarks()
	if not settings.bestReward then return end
	local count = GetNumQuestChoices and GetNumQuestChoices() or 0
	if count < 2 then return end

	local bestValue, valueIndex, bestUp, upIndex = 0, nil, 0, nil
	local links, missing = {}, false
	for index = 1, count do
		local link = GetQuestItemLink("choice", index)
		local _, _, amount = GetQuestItemInfo("choice", index)
		links[index] = link
		if link then
			local price = select(11, GetItemInfo(link))
			if price == nil then
				missing = true
			elseif price * (amount or 1) > bestValue then
				bestValue, valueIndex = price * (amount or 1), index
			end
			local ok, result = pcall(ns.Upgrade.Compare, ns.Upgrade, link)
			local score = ok and (result == "new" and 1000 or type(result) == "number" and result) or nil
			if score and score >= 0.5 and score > bestUp then
				bestUp, upIndex = score, index
			end
		else
			missing = true
		end
	end
	-- item data still loading: try again shortly
	if missing and (tries or 0) < 3 then
		C_Timer.After(0.4, function() CheckRewards((tries or 0) + 1, round) end)
		return
	end

	for index = 1, count do
		local upgrade
		if index == upIndex then
			local ok, result = pcall(ns.Upgrade.Compare, ns.Upgrade, links[index])
			upgrade = ok and UpgradeText(result)
		end
		Mark(index, index == valueIndex, upgrade)
	end

	local parts = {}
	if valueIndex and links[valueIndex] then
		parts[#parts + 1] = L.REWARD_VALUE:format(links[valueIndex], GetMoneyString(bestValue, true))
	end
	if upIndex and links[upIndex] then
		local ok, result = pcall(ns.Upgrade.Compare, ns.Upgrade, links[upIndex])
		parts[#parts + 1] = L.REWARD_UPGRADE:format(links[upIndex], ok and UpgradeText(result) or "")
	end
	if #parts > 0 then
		ns:Print(table.concat(parts, "  ·  "))
	end
end


--[[ Module ]]--

function Quests:OnInitialize()
	settings = ns.db.qol
end

function Quests:OnLogin()
	HookTracker()
	local function Changed()
		readyDirty = true
		ns:Defer("quests-ready", function()
			if ns.Experience and ns.Experience.UpdateText then ns.Experience:UpdateText() end
		end)
	end
	ns:RegisterEvent("QUEST_LOG_UPDATE", Changed)
	ns:RegisterEvent("PLAYER_LEVEL_UP", Changed)
	ns:RegisterEvent("QUEST_COMPLETE", function() CheckRewards() end)
end

-- The tracker and the log redraw themselves; this asks them to after an option change.
function Quests:Refresh()
	if ObjectiveTrackerManager and ObjectiveTrackerManager.UpdateAll then
		pcall(ObjectiveTrackerManager.UpdateAll, ObjectiveTrackerManager)
	elseif ObjectiveTracker_Update then
		pcall(ObjectiveTracker_Update)
	end
end
