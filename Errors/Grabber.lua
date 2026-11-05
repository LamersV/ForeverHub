--[[
	Errors - capture
	Installed as early as possible (this file runs before almost every other addon)
	so load-time errors of other addons are caught too.
--]]

local _, ns = ...
local L = ns.L
local Errors = ns:NewModule("Errors")

local MAX_ERRORS = 300
local RATE = 10 -- errors per second allowed before capture pauses
local LOCALS_LIMIT = 4000

local tostring, time, GetTime, min = tostring, time, GetTime, math.min
local tremove = table.remove
local debugstack, debuglocals = debugstack, debuglocals
local GetCallstackHeight, GetErrorCallstackHeight = GetCallstackHeight, GetErrorCallstackHeight
local issecretvalue = issecretvalue or function() return false end

local log = {} -- ordered oldest -> newest; becomes the saved table after login
local byMessage = {} -- message -> error, makes duplicate detection O(1)
local session = 0
local listeners = {}
local installed, previousHandler
local realSetErrorHandler = seterrorhandler


--[[ Storage ]]--

local function Remove(err)
	for i = #log, 1, -1 do
		if log[i] == err then
			tremove(log, i)
			return
		end
	end
end

local function Store(err)
	log[#log + 1] = err
	while #log > MAX_ERRORS do
		local old = tremove(log, 1)
		if byMessage[old.message] == old then
			byMessage[old.message] = nil
		end
	end
end


--[[ Stack inspection ]]--

-- Mirrors how the default handler finds the frame where the error happened.
-- Must be called directly from Grab so the computed level stays correct.
local function GetStack()
	local level = 3
	local current, errorHeight = GetCallstackHeight and GetCallstackHeight(), GetErrorCallstackHeight and GetErrorCallstackHeight()
	if current and errorHeight then
		level = current - (errorHeight - 1)
	end

	local stack = debugstack(level)
	if stack == nil then
		return "debugstack() returned nil", level
	elseif issecretvalue(stack) then
		return "debugstack() returned a secret value", level
	end
	return stack, level
end

local function GetLocals(level)
	local locals = debuglocals(level)
	if locals == nil or issecretvalue(locals) then
		return nil
	elseif #locals > LOCALS_LIMIT then
		return locals:sub(1, LOCALS_LIMIT) .. "\n..."
	end
	return locals
end


--[[ Capture ]]--

local function Fire(err, isNew)
	for i = 1, #listeners do
		listeners[i](err, isNew)
	end
end

local tokens, lastGrab, throttled = RATE, GetTime(), false

local function Grab(message, simple)
	local now = GetTime()
	tokens = min(RATE, tokens + (now - lastGrab) * RATE)
	lastGrab = now
	if tokens < 1 then
		if not throttled then
			throttled = true
			print(ns.color .. ns.name .. "|r:", L.ERRORS_THROTTLED)
		end
		return
	end
	tokens, throttled = tokens - 1, false

	if issecretvalue(message) then
		message = "<error message is a secret value>"
	else
		message = tostring(message)
	end

	local err = byMessage[message]
	if err and err.session == session then
		err.count = err.count + 1
		err.time = time()
		return Fire(err, false)
	end

	if err then
		Remove(err) -- seen in an older session: move it to the end
	else
		err = {message = message}
		byMessage[message] = err
	end

	err.session, err.count, err.time = session, 1, time()
	err.stack, err.locals = nil, nil
	Store(err) -- store first, in case inspecting the stack fails

	if not simple then
		local stack, level = GetStack()
		err.stack = stack
		err.locals = GetLocals(level)
	end

	Fire(err, true)
end

local function Handler(message)
	Grab(message, false)
end

-- Respect a BugGrabber that already took over; the module stays off in that case.
if not BugGrabber then
	previousHandler = geterrorhandler()
	realSetErrorHandler(Handler)
	seterrorhandler = function() end -- keep other addons from stealing the handler
	installed = true
end

local function Uninstall()
	if installed then
		realSetErrorHandler(previousHandler)
		seterrorhandler = realSetErrorHandler
		installed = false
	end
end


--[[ Game events ]]--

local function OnBlocked(event, addon, func)
	Grab(L.ERROR_BLOCKED:format(event, addon or "?", func or "?"), true)
end

local function OnWarning(_, text)
	Grab("LUA_WARNING: " .. tostring(text or ""), true)
end

if installed then
	ns:RegisterEvent("ADDON_ACTION_BLOCKED", OnBlocked)
	ns:RegisterEvent("ADDON_ACTION_FORBIDDEN", OnBlocked)
	ns:RegisterEvent("LUA_WARNING", OnWarning)
end


--[[ Module ]]--

function Errors:OnInitialize()
	local db = ns.db
	if not installed or not db.modules.errors then
		Uninstall()
		ns:UnregisterEvent("ADDON_ACTION_BLOCKED", OnBlocked)
		ns:UnregisterEvent("ADDON_ACTION_FORBIDDEN", OnBlocked)
		ns:UnregisterEvent("LUA_WARNING", OnWarning)
		return
	end

	db.errorSession = (db.errorSession or 0) + 1
	session = db.errorSession

	-- Merge errors caught before saved variables were available.
	local early = log
	log = type(db.errorLog) == "table" and db.errorLog or {}
	wipe(byMessage)
	for i = 1, #log do
		byMessage[log[i].message] = log[i]
	end
	for i = 1, #early do
		local err = early[i]
		local old = byMessage[err.message]
		if old then
			Remove(old)
		end
		err.session = session
		byMessage[err.message] = err
		Store(err)
	end
	db.errorLog = log

	if ScriptErrorsFrame then
		ScriptErrorsFrame:UnregisterEvent("LUA_WARNING")
	end
	if db.errors.suppressBlizzard then
		UIParent:UnregisterEvent("ADDON_ACTION_FORBIDDEN")
		UIParent:UnregisterEvent("ADDON_ACTION_BLOCKED")
		if GameEvent and GameEvent.UnregisterInternalEvent then
			GameEvent.UnregisterInternalEvent("ADDON_ACTION_BLOCKED")
			GameEvent.UnregisterInternalEvent("ADDON_ACTION_FORBIDDEN")
		end
	end
end

function Errors:IsActive()
	return installed
end

function Errors:RegisterListener(func)
	listeners[#listeners + 1] = func
end

function Errors:GetSession()
	return session
end

-- Returns a new list of errors for a session filter: "current", "previous" or "all".
function Errors:GetErrors(filter)
	local result = {}
	local target = filter == "previous" and session - 1 or session
	for i = 1, #log do
		local err = log[i]
		if filter == "all" or err.session == target then
			result[#result + 1] = err
		end
	end
	return result
end

function Errors:CountAll()
	return #log
end

function Errors:CountSession()
	local count = 0
	for i = #log, 1, -1 do
		if log[i].session == session then
			count = count + 1
		end
	end
	return count
end

function Errors:Clear()
	wipe(log)
	wipe(byMessage)
	Fire(nil, false)
end

-- Allows other code (and /fh test) to push an error manually.
function Errors:Report(message)
	Grab(message, true)
end
