-- Forever Frame Builder
-- Core: namespace, saved variables, callbacks, shared helpers and slash commands.

local addonName, ns = ...
local L = ns.L

ns.name = addonName
ns.title = "Forever Frame Builder"
ns.version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or "0.1.0"

local DEFAULTS = {
	version = 1,
	current = nil,
	projects = {},
	settings = {
		gridSize = 8,
		snap = true,
		showGrid = true,
		collapsedSections = {}, -- inspector sections the user folded away
		leftTab = 1, -- 1 = elements, 2 = layers
		window = nil, -- { point, x, y, w, h }
	},
}

local function ApplyDefaults(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = CopyTable(value)
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			ApplyDefaults(target[key], value)
		end
	end
end

function ns.Print(fmt, ...)
	local msg = select("#", ...) > 0 and fmt:format(...) or fmt
	DEFAULT_CHAT_FRAME:AddMessage("|cffffd100" .. ns.title .. ":|r " .. msg)
end

-- Tiny callback registry so the UI modules can react to document changes.
ns.callbacks = {}

function ns.On(event, fn)
	ns.callbacks[event] = ns.callbacks[event] or {}
	table.insert(ns.callbacks[event], fn)
end

function ns.Fire(event, ...)
	local list = ns.callbacks[event]
	if not list then return end
	for _, fn in ipairs(list) do
		fn(...)
	end
end

function ns.Round(value, decimals)
	local mult = 10 ^ (decimals or 0)
	return math.floor(value * mult + 0.5) / mult
end

-- Rounds to the grid when snapping is enabled, otherwise to whole pixels.
function ns.Snap(value)
	local settings = ns.db.settings
	if settings.snap and settings.gridSize > 0 then
		return ns.Round(value / settings.gridSize) * settings.gridSize
	end
	return ns.Round(value)
end

local LUA_KEYWORDS = {}
for word in ("and break do else elseif end false for function if in local nil not or repeat return then true until while"):gmatch("%a+") do
	LUA_KEYWORDS[word] = true
end

-- Removes everything that is not valid in a Lua identifier.
function ns.SanitizeName(name)
	name = tostring(name or ""):gsub("[^%w_]", "")
	if name:match("^%d") or LUA_KEYWORDS[name] then
		name = "_" .. name
	end
	return name
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= addonName then return end
		ForeverFrameBuilderDB = ForeverFrameBuilderDB or {}
		ApplyDefaults(ForeverFrameBuilderDB, DEFAULTS)
		ns.db = ForeverFrameBuilderDB
		ns.Doc:Init()
		eventFrame:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_REGEN_DISABLED" then
		ns.Fire("COMBAT", true)
	elseif event == "PLAYER_REGEN_ENABLED" then
		ns.Fire("COMBAT", false)
	end
end)

function ns.ToggleEditor()
	ns.Editor:Toggle()
end

function ForeverFrameBuilder_OnAddonCompartmentClick()
	ns.ToggleEditor()
end

SLASH_FOREVERFRAMEBUILDER1 = "/ffb"
SLASH_FOREVERFRAMEBUILDER2 = "/framebuilder"
SlashCmdList.FOREVERFRAMEBUILDER = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "reset" then
		ns.db.settings.window = nil
		ns.Editor:ResetPosition()
		ns.Print(L["Window position reset."])
	else
		ns.ToggleEditor()
	end
end
