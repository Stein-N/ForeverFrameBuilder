-- Forever Frame Builder
-- Errors: a persistent log of errors that happened in the editor, with everything needed to
-- reproduce them: the element, its template, properties and all scripts of the project.
--
-- Entries are stored in ns.db.errors (newest first, at most MAX_ENTRIES). Identical errors
-- (same kind, element and message) are merged and counted. ns.Fire("ERRORS_CHANGED") is
-- sent whenever the log changes.

local _, ns = ...
local L = ns.L
local W = ns.W

local Errors = {}
ns.Errors = Errors

local MAX_ENTRIES = 50
local MAX_STACK_LINES = 20
local ROW_HEIGHT = 34

-- Kinds of errors, in the order they appear in reports.
Errors.KINDS = {
	template = L["Template could not be created"],
	apply = L["Applying properties failed"],
	script = L["Script error"],
	editorOnLoad = L["OnLoad in the editor failed"],
	lua = L["Lua error"],
}

local function Log()
	return ns.db and ns.db.errors
end

local function Stack(skip)
	local stack = debugstack and debugstack(skip or 3) or ""
	local lines = {}
	for line in stack:gmatch("[^\n]+") do
		table.insert(lines, line)
		if #lines >= MAX_STACK_LINES then break end
	end
	return table.concat(lines, "\n")
end
Errors.Stack = Stack

-- Like pcall, but also returns the stack of the error (pcall loses it).
function Errors.Call(fn, ...)
	local args, count = { ... }, select("#", ...)
	local stack
	local ok, result = xpcall(function()
		return fn(unpack(args, 1, count))
	end, function(message)
		stack = Stack(3)
		return message
	end)
	return ok, result, stack
end

-- Everything about an element that helps to reproduce an error.
local function DescribeNode(node)
	if not node then return nil end
	local info = {
		name = node.name, type = node.type, parent = ns.Doc:Get(node.parent) and ns.Doc:Get(node.parent).name,
		props = CopyTable(node.props or {}), scripts = CopyTable(node.scripts or {}),
		anchors = ns.Doc.GetAnchors and ns.Doc.GetAnchors(node) or nil,
		w = node.w, h = node.h, fill = node.fill,
	}
	-- Target names are stored now: the report may be read after switching projects.
	for _, anchor in ipairs(info.anchors or {}) do
		local target = anchor.target ~= 0 and ns.Doc:Get(anchor.target)
		anchor.targetName = target and target.name or nil
	end
	local template = node.props and node.props.template
	if node.type == "Template" and template then
		local entry = ns.GetTemplateInfo(template)
		info.template = template
		if entry then
			info.templateInfo = { widget = entry[2], addon = entry[3], width = entry[4], height = entry[5],
				shared = entry[6], needs = entry[7], needsName = entry[8] }
		end
		local catalog = ns.GetCatalogEntry(template)
		info.catalogSetup = catalog and catalog[5]
	end
	return info
end

-- Scripts of every element in the current project, keyed by element name.
local function ProjectScripts()
	local all = {}
	if not ns.Doc.project then return all end
	ns.Doc:Walk(function(node)
		if next(node.scripts) then
			all[node.name] = CopyTable(node.scripts)
		end
	end)
	return all
end

local function ClientInfo()
	local version, build = "?", "?"
	if GetBuildInfo then
		version, build = GetBuildInfo()
	end
	return ("%s (%s) %s"):format(tostring(version), tostring(build), GetLocale and GetLocale() or "?")
end

-- Records an error. data: { kind, message, node, script, stack }
function Errors:Add(data)
	local log = Log()
	if not log then return end
	local message = tostring(data.message or "?")
	local element = DescribeNode(data.node)
	local key = table.concat({ data.kind or "lua", element and element.name or "", data.script or "", message }, "\1")
	for i, entry in ipairs(log) do
		if entry.key == key then
			-- Same error again: count it and keep the newest state.
			table.remove(log, i)
			entry.count = entry.count + 1
			entry.time = date("%Y-%m-%d %H:%M:%S")
			entry.element = element
			entry.projectScripts = ProjectScripts()
			table.insert(log, 1, entry)
			ns.Fire("ERRORS_CHANGED")
			return entry
		end
	end
	local entry = {
		key = key,
		time = date("%Y-%m-%d %H:%M:%S"),
		count = 1,
		kind = data.kind or "lua",
		message = message,
		stack = data.stack or Stack(3),
		script = data.script,
		project = ns.Doc.CurrentName and ns.Doc:CurrentName() or "?",
		preview = ns.Canvas and ns.Canvas.preview or false,
		client = ClientInfo(),
		version = ns.version,
		element = element,
		projectScripts = ProjectScripts(),
	}
	table.insert(log, 1, entry)
	while #log > MAX_ENTRIES do
		table.remove(log)
	end
	ns.Fire("ERRORS_CHANGED")
	return entry
end

function Errors:Count()
	local log = Log()
	return log and #log or 0
end

function Errors:Clear()
	local log = Log()
	if log then wipe(log) end
	ns.Fire("ERRORS_CHANGED")
end

function Errors:Remove(entry)
	local log = Log()
	if log then tDeleteItem(log, entry) end
	ns.Fire("ERRORS_CHANGED")
end

---------------------------------------------------------------------------
-- Report text
---------------------------------------------------------------------------

local function SortedKeys(t)
	local keys = {}
	for key in pairs(t or {}) do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	return keys
end

local function ValueText(value)
	if type(value) == "table" then
		if value.r then
			return ("{ r = %s, g = %s, b = %s, a = %s }"):format(ns.LuaNum(value.r), ns.LuaNum(value.g), ns.LuaNum(value.b), ns.LuaNum(value.a or 1))
		end
		return "{…}"
	end
	return tostring(value)
end

local function AddScripts(lines, scripts, indent)
	for _, name in ipairs(SortedKeys(scripts)) do
		table.insert(lines, indent .. "-- " .. name)
		for line in (tostring(scripts[name]) .. "\n"):gmatch("(.-)\r?\n") do
			table.insert(lines, indent .. line)
		end
	end
end

-- Plain-text report meant to be pasted into a bug report.
function Errors:Report(entry)
	local lines = {
		("%s %s – error report"):format(ns.title, tostring(entry.version)),
		("Time: %s   Count: %d"):format(entry.time, entry.count),
		("Client: %s"):format(entry.client or "?"),
		("Project: %s%s"):format(entry.project or "?", entry.preview and "   (preview)" or ""),
		("Kind: %s"):format(Errors.KINDS[entry.kind] or entry.kind),
	}
	local element = entry.element
	if element then
		table.insert(lines, ("Element: %s (%s)%s%s"):format(element.name, element.type,
			element.parent and (", parent " .. element.parent) or "", entry.script and (", script " .. entry.script) or ""))
		if element.template then
			local t = element.templateInfo
			table.insert(lines, ("Template: %s%s"):format(element.template, t and
				(" – widget %s, addon %s, size %sx%s%s%s"):format(t.widget, t.addon, t.width, t.height,
					t.needs and (", needs " .. t.needs) or "", t.needsName and ", needs a global name" or "")
				or " – not in the template list"))
			if element.catalogSetup then
				table.insert(lines, "Catalog setup code:")
				for line in (element.catalogSetup .. "\n"):gmatch("(.-)\r?\n") do
					table.insert(lines, "  " .. line)
				end
			end
		end
	end
	table.insert(lines, "")
	table.insert(lines, "Message:")
	table.insert(lines, "  " .. entry.message)
	if entry.stack and entry.stack ~= "" then
		table.insert(lines, "")
		table.insert(lines, "Stack:")
		for line in (entry.stack .. "\n"):gmatch("(.-)\r?\n") do
			if line ~= "" then table.insert(lines, "  " .. line) end
		end
	end
	if element then
		table.insert(lines, "")
		table.insert(lines, ("Layout: %s x %s%s"):format(ns.LuaNum(element.w or 0), ns.LuaNum(element.h or 0), element.fill and ", fill parent" or ""))
		for i, anchor in ipairs(element.anchors or {}) do
			table.insert(lines, ("  anchor %d: %s -> %s %s (%s, %s)"):format(i, anchor.point,
				anchor.targetName or (anchor.target ~= 0 and ("#" .. tostring(anchor.target))) or "parent", anchor.relPoint, ns.LuaNum(anchor.x), ns.LuaNum(anchor.y)))
		end
		table.insert(lines, "Properties:")
		for _, key in ipairs(SortedKeys(element.props)) do
			table.insert(lines, ("  %s = %s"):format(key, ValueText(element.props[key])))
		end
		table.insert(lines, "")
		table.insert(lines, "Scripts of " .. element.name .. ":")
		if next(element.scripts) then
			AddScripts(lines, element.scripts, "  ")
		else
			table.insert(lines, "  (none)")
		end
	end
	local others = {}
	for _, name in ipairs(SortedKeys(entry.projectScripts)) do
		if not element or name ~= element.name then
			table.insert(others, name)
		end
	end
	if #others > 0 then
		table.insert(lines, "")
		table.insert(lines, "Other scripts in the project:")
		for _, name in ipairs(others) do
			table.insert(lines, "  [" .. name .. "]")
			AddScripts(lines, entry.projectScripts[name], "    ")
		end
	end
	return table.concat(lines, "\n")
end

---------------------------------------------------------------------------
-- Lua errors outside the editor's own checks
---------------------------------------------------------------------------

-- Wraps the current error handler: errors from this addon or during the preview are
-- logged, and every error is still passed on (to the default handler, BugSack, …).
function Errors:HookErrorHandler()
	if self.hooked or not geterrorhandler then return end
	self.hooked = true
	local previous = geterrorhandler()
	seterrorhandler(function(message, ...)
		local ok = pcall(function()
			local stack = Stack(3)
			local ours = tostring(message):find("ForeverFrameBuilder", 1, true) or stack:find("ForeverFrameBuilder", 1, true)
			if ours or (ns.Canvas and ns.Canvas.preview) then
				Errors:Add({ kind = "lua", message = message, stack = stack, node = ns.Doc:GetSelected() })
			end
		end)
		if previous then
			return previous(message, ...)
		end
	end)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

function Errors:GetFrame()
	if self.frame then return self.frame end

	local frame = CreateFrame("Frame", "ForeverFrameBuilderErrors", UIParent, "ButtonFrameTemplate")
	frame:SetSize(820, 520)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	ButtonFrameTemplate_HidePortrait(frame)
	ButtonFrameTemplate_HideButtonBar(frame)
	if frame.Inset then frame.Inset:Hide() end
	ns.SetFrameTitle(frame, L["Errors"])
	table.insert(UISpecialFrames, frame:GetName())

	local hint = W.Label(frame, L["ERRORS_HINT"], "GameFontHighlightSmall")
	hint:SetPoint("TOPLEFT", 14, -30)
	hint:SetPoint("RIGHT", -14, 0)
	hint:SetJustifyH("LEFT")

	-- List of entries
	local listInset = W.Inset(frame)
	listInset:SetPoint("TOPLEFT", 10, -48)
	listInset:SetPoint("BOTTOMLEFT", 10, 36)
	listInset:SetWidth(260)
	local _, list = W.ScrollArea(listInset)
	frame.list = list
	frame.rows = {}
	frame.empty = W.Label(listInset, L["No errors recorded."], "GameFontDisableSmall")
	frame.empty:SetPoint("TOPLEFT", 10, -10)

	-- Report of the selected entry
	local reportInset = W.Inset(frame)
	reportInset:SetPoint("TOPLEFT", listInset, "TOPRIGHT", 6, 0)
	reportInset:SetPoint("BOTTOMRIGHT", -10, 36)
	local editor = CreateFrame("Frame", nil, reportInset, "ScrollingEditBoxTemplate")
	editor:SetPoint("TOPLEFT", 8, -6)
	editor:SetPoint("BOTTOMRIGHT", -26, 6)
	local scrollBar = CreateFrame("EventFrame", nil, reportInset, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", editor, "TOPRIGHT", 8, 0)
	scrollBar:SetPoint("BOTTOMLEFT", editor, "BOTTOMRIGHT", 8, 0)
	ScrollUtil.RegisterScrollBoxWithScrollBar(editor:GetScrollBox(), scrollBar)
	frame.editor = editor
	-- Keep the report read-only: typing restores the text.
	editor:GetEditBox():HookScript("OnTextChanged", function(box, userInput)
		if userInput and frame.selected then
			box:SetText(Errors:Report(frame.selected))
		end
	end)

	local selectAll = W.Button(frame, L["Select all"], 120, function()
		local box = editor:GetEditBox()
		box:SetFocus()
		box:HighlightText()
	end, L["Then copy the report with Ctrl+C."])
	selectAll:SetPoint("BOTTOMLEFT", reportInset, "BOTTOMLEFT", 0, -30)
	local remove = W.Button(frame, L["Delete"], 100, function()
		if frame.selected then
			Errors:Remove(frame.selected)
		end
	end)
	remove:SetPoint("LEFT", selectAll, "RIGHT", 4, 0)
	frame.removeButton = remove
	local clear = W.Button(frame, L["Clear all"], 100, function()
		Errors:Clear()
	end)
	clear:SetPoint("BOTTOMLEFT", 10, 8)
	local close = W.Button(frame, CLOSE, 100, function()
		frame:Hide()
	end)
	close:SetPoint("BOTTOMRIGHT", -10, 8)

	frame:SetScript("OnShow", function()
		Errors:Refresh()
	end)
	frame:Hide()
	self.frame = frame
	return frame
end

local function CreateRow(frame)
	local row = CreateFrame("Button", nil, frame.list)
	row:SetHeight(ROW_HEIGHT)
	row.selectedTexture = row:CreateTexture(nil, "BACKGROUND")
	row.selectedTexture:SetAllPoints()
	row.selectedTexture:SetColorTexture(0.2, 0.6, 1, 0.35)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.title = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	row.title:SetPoint("TOPLEFT", 6, -3)
	row.title:SetPoint("RIGHT", -6, 0)
	row.title:SetJustifyH("LEFT")
	row.title:SetWordWrap(false)
	row.message = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.message:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -2)
	row.message:SetPoint("RIGHT", -6, 0)
	row.message:SetJustifyH("LEFT")
	row.message:SetWordWrap(false)
	row:SetScript("OnClick", function(self)
		Errors:Select(self.entry)
	end)
	return row
end

function Errors:Select(entry)
	local frame = self.frame
	if not frame then return end
	frame.selected = entry
	frame.editor:SetText(entry and self:Report(entry) or "")
	frame.removeButton:SetEnabled(entry ~= nil)
	for _, row in ipairs(frame.rows) do
		row.selectedTexture:SetShown(row:IsShown() and row.entry == entry)
	end
end

function Errors:Refresh()
	local frame = self.frame
	if not frame or not frame:IsShown() then return end
	local log = Log() or {}
	for i, entry in ipairs(log) do
		local row = frame.rows[i]
		if not row then
			row = CreateRow(frame)
			row:SetPoint("TOPLEFT", frame.list, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
			row:SetPoint("RIGHT", frame.list, "RIGHT")
			frame.rows[i] = row
		end
		row.entry = entry
		local where = entry.element and entry.element.name or (Errors.KINDS[entry.kind] or entry.kind)
		row.title:SetText(("%s  |cffaaaaaa%s%s|r"):format(where, entry.time:sub(12),
			entry.count > 1 and ("  x" .. entry.count) or ""))
		row.message:SetText("|cffff6060" .. entry.message:gsub("\n.*", "") .. "|r")
		row:Show()
	end
	for i = #log + 1, #frame.rows do
		frame.rows[i]:Hide()
	end
	frame.list:SetHeight(math.max(1, #log * ROW_HEIGHT))
	frame.empty:SetShown(#log == 0)
	if not frame.selected or not tIndexOf(log, frame.selected) then
		frame.selected = log[1]
	end
	self:Select(frame.selected)
end

function Errors:Toggle()
	local frame = self:GetFrame()
	frame:SetShown(not frame:IsShown())
	if frame:IsShown() then
		frame:Raise()
		self:Refresh()
	end
end

ns.On("ERRORS_CHANGED", function()
	Errors:Refresh()
end)
