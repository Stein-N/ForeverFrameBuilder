-- Forever Frame Builder
-- Inspector: property editor for the selected element.
--
-- Rows are built from field descriptors { kind, label, get, set, options, step, min, max }.
-- set(value, mergeKey, noCheckpoint) writes through the document so every edit is undoable.

local _, ns = ...
local L = ns.L
local Doc = ns.Doc
local W = ns.W

local Inspector = {}
ns.Inspector = Inspector

local ROW_HEIGHT = 26
local HEADER_HEIGHT = 24
local LABEL_WIDTH = 92
local CONTROL_LEFT = LABEL_WIDTH + 14

Inspector.pools = {}
Inspector.rows = {}

---------------------------------------------------------------------------
-- Row factories
---------------------------------------------------------------------------

local function FormatNumber(value)
	return ns.LuaNum(ns.Round(tonumber(value) or 0, 2))
end

local function OptionLabel(options, value)
	for _, option in ipairs(ns.OptionList(options)) do
		if option.value == value then
			return option.label
		end
	end
	return tostring(value)
end

local function ResolveOptions(field)
	if type(field.options) == "function" then
		return field.options()
	end
	return field.options
end

local Factories = {}

function Factories.header(row)
	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.text:SetPoint("BOTTOMLEFT", 8, 4)
	local line = row:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 0.82, 0, 0.25)
	line:SetHeight(1)
	line:SetPoint("BOTTOMLEFT", 6, 1)
	line:SetPoint("BOTTOMRIGHT", -6, 1)
	row.Setup = function(self, field)
		self.text:SetText(field.label)
	end
end

function Factories.label(row)
	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.value:SetPoint("LEFT", CONTROL_LEFT, 0)
	row.value:SetPoint("RIGHT", -8, 0)
	row.value:SetJustifyH("LEFT")
	row.Refresh = function(self)
		self.value:SetText(tostring(self.field.get()))
	end
end

-- Shared by "string" and "number": commits on Enter or when focus is lost.
local function CreateTextControl(row, numeric)
	local box = W.EditBox(row)
	box:SetPoint("LEFT", CONTROL_LEFT + 4, 0)
	box:SetPoint("RIGHT", -8, 0)
	row.box = box

	box:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEscapePressed", function(self)
		row.cancel = true
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self:HighlightText(0, 0)
		if row.cancel then
			row.cancel = false
		elseif row.field then
			local text = self:GetText()
			if numeric then
				local value = tonumber(text)
				if value then
					row:SetValue(value)
				end
			else
				row.field.set(text)
			end
		end
		if row.field then
			row:Refresh()
		end
	end)

	row.Refresh = function(self)
		if box:HasFocus() or not self.field then return end
		local value = self.field.get()
		box:SetText(numeric and FormatNumber(value) or tostring(value or ""))
		box:SetCursorPosition(0)
	end
end

function Factories.string(row)
	CreateTextControl(row, false)
end

function Factories.number(row)
	CreateTextControl(row, true)
	row.SetValue = function(self, value, mergeKey)
		local field = self.field
		if field.min then value = math.max(field.min, value) end
		if field.max then value = math.min(field.max, value) end
		field.set(value, mergeKey)
	end
	-- Mouse wheel changes the value by one step (Shift: ten steps).
	row.box:EnableMouseWheel(true)
	row.box:SetScript("OnMouseWheel", function(_, delta)
		local field = row.field
		local step = (field.step or 1) * (IsShiftKeyDown() and 10 or 1)
		local value = ns.Round((tonumber(field.get()) or 0) + delta * step, 3)
		row:SetValue(value, "wheel:" .. field.label)
		row:Refresh()
	end)
end

function Factories.bool(row)
	local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	check:SetSize(24, 24)
	check:SetPoint("LEFT", CONTROL_LEFT - 2, 0)
	check:SetScript("OnClick", function(self)
		row.field.set(self:GetChecked() and true or false)
	end)
	row.Refresh = function(self)
		check:SetChecked(self.field.get() and true or false)
	end
end

function Factories.color(row)
	local swatch = CreateFrame("Button", nil, row)
	swatch:SetSize(36, 18)
	swatch:SetPoint("LEFT", CONTROL_LEFT, 0)
	local border = swatch:CreateTexture(nil, "BACKGROUND")
	border:SetAllPoints()
	border:SetColorTexture(0.6, 0.6, 0.6, 1)
	local checker = swatch:CreateTexture(nil, "BORDER")
	checker:SetPoint("TOPLEFT", 1, -1)
	checker:SetPoint("BOTTOMRIGHT", -1, 1)
	checker:SetColorTexture(0.15, 0.15, 0.15, 1)
	local color = swatch:CreateTexture(nil, "ARTWORK")
	color:SetPoint("TOPLEFT", 1, -1)
	color:SetPoint("BOTTOMRIGHT", -1, 1)
	swatch:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

	local value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	value:SetPoint("LEFT", swatch, "RIGHT", 6, 0)

	swatch:SetScript("OnClick", function()
		local field = row.field
		local current = field.get()
		local previous = CopyTable(current)
		Doc:Checkpoint()
		local function Apply()
			local r, g, b = ColorPickerFrame:GetColorRGB()
			local a = ColorPickerFrame.GetColorAlpha and ColorPickerFrame:GetColorAlpha() or 1
			field.set({ r = r, g = g, b = b, a = a }, nil, true)
		end
		ColorPickerFrame:SetupColorPickerAndShow({
			r = current.r, g = current.g, b = current.b,
			opacity = current.a or 1,
			hasOpacity = true,
			swatchFunc = Apply,
			opacityFunc = Apply,
			cancelFunc = function()
				field.set(previous, nil, true)
			end,
		})
	end)

	row.Refresh = function(self)
		local c = self.field.get()
		if not c then return end
		color:SetColorTexture(c.r, c.g, c.b, c.a or 1)
		value:SetText(("%02X%02X%02X  %d%%"):format(c.r * 255, c.g * 255, c.b * 255, (c.a or 1) * 100))
	end
end

function Factories.select(row)
	local dropdown = W.Dropdown(row)
	dropdown:SetPoint("LEFT", CONTROL_LEFT, 0)
	dropdown:SetPoint("RIGHT", -8, 0)
	row.dropdown = dropdown
	dropdown:SetupMenu(function(_, root)
		local field = row.field
		if not field then return end
		local options = ns.OptionList(ResolveOptions(field))
		if #options > 20 then
			root:SetScrollMode(400)
		end
		for _, option in ipairs(options) do
			root:CreateRadio(option.label,
				function() return row.field.get() == option.value end,
				function() row.field.set(option.value) end)
		end
	end)
	row.Refresh = function(self)
		dropdown:OverrideText(OptionLabel(ResolveOptions(self.field), self.field.get()))
	end
end

function Factories.template(row)
	CreateTextControl(row, false)
	row.box:ClearAllPoints()
	row.box:SetPoint("LEFT", CONTROL_LEFT + 4, 0)
	row.box:SetPoint("RIGHT", -40, 0)
	local browse = W.Button(row, "…", 28, function()
		ns.Dialogs:PickTemplate(function(entry, catalog)
			row.field.set(entry[1], entry, catalog)
		end)
	end, L["Browse all Blizzard templates"])
	browse:SetPoint("LEFT", row.box, "RIGHT", 4, 0)
end

function Factories.script(row)
	local button = W.Button(row, "", 110)
	button:SetPoint("LEFT", CONTROL_LEFT, 0)
	button:SetScript("OnClick", function()
		row.field.open()
	end)
	row.Refresh = function(self)
		local code = self.field.get() or ""
		if code == "" then
			button:SetText(L["Add…"])
		else
			local lines = select(2, code:gsub("\n", "\n")) + 1
			button:SetText(L["Edit"] .. " |cff80ff80(" .. lines .. ")|r")
		end
	end
end

---------------------------------------------------------------------------
-- Row management
---------------------------------------------------------------------------

function Inspector:AcquireRow(kind)
	local pool = self.pools[kind]
	local row = pool and table.remove(pool)
	if not row then
		row = CreateFrame("Frame", nil, self.content)
		row.kind = kind
		if kind ~= "header" then
			row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			row.label:SetPoint("LEFT", 8, 0)
			row.label:SetWidth(LABEL_WIDTH)
			row.label:SetJustifyH("LEFT")
			row.label:SetWordWrap(false)
		end
		Factories[kind](row)
	end
	return row
end

function Inspector:ReleaseRows()
	for _, row in ipairs(self.rows) do
		row:Hide()
		row.field = nil
		self.pools[row.kind] = self.pools[row.kind] or {}
		table.insert(self.pools[row.kind], row)
	end
	wipe(self.rows)
end

function Inspector:AddRow(field)
	local row = self:AcquireRow(field.kind)
	row.field = field
	local height = field.kind == "header" and HEADER_HEIGHT or ROW_HEIGHT
	row:SetHeight(height)
	row:ClearAllPoints()
	row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -self.offset)
	row:SetPoint("RIGHT", self.content, "RIGHT")
	self.offset = self.offset + height
	if row.label then
		row.label:SetText(field.label)
	end
	if row.Setup then
		row:Setup(field)
	end
	if row.Refresh then
		row:Refresh()
	end
	row:Show()
	table.insert(self.rows, row)
end

---------------------------------------------------------------------------
-- Field lists
---------------------------------------------------------------------------

local function ParentOptions(id)
	local options = { { value = 0, label = L["(Screen)"] } }
	Doc:Walk(function(other, depth)
		if other.id ~= id and not Doc:IsAncestor(id, other.id) and ns.Elements[other.type].allowChildren then
			table.insert(options, { value = other.id, label = ("  "):rep(depth) .. other.name })
		end
	end)
	return options
end

function Inspector:BuildFields(id)
	local node = Doc:Get(id)
	local def = ns.Elements[node.type]
	local fields = {}
	local function N()
		return Doc:Get(id)
	end
	local function Add(field)
		table.insert(fields, field)
	end
	local function NodeField(kind, label, key, extra)
		local isNodeKey = Doc.NODE_KEYS[key]
		local field = {
			kind = kind, label = label,
			get = function()
				local n = N()
				if not n then return nil end
				if isNodeKey then return n[key] end
				return n.props[key]
			end,
			set = function(value, mergeKey, noCheckpoint)
				Doc:Set(id, key, value, noCheckpoint, mergeKey and (mergeKey .. ":" .. id))
			end,
		}
		for k, v in pairs(extra or {}) do
			field[k] = v
		end
		Add(field)
	end

	Add({ kind = "header", label = L["Element"] })
	Add({ kind = "label", label = L["Type"], get = function() return def.label end })
	Add({
		kind = "string", label = L["Name"],
		get = function() local n = N() return n and n.name end,
		set = function(value)
			if not Doc:Set(id, "name", value) then
				ns.Print(L["\"%s\" is not a valid or unique name."], tostring(value))
			end
		end,
	})
	if not def.region then
		NodeField("string", L["Global name"], "globalName")
	end
	Add({
		kind = "select", label = L["Parent"],
		options = function() return ParentOptions(id) end,
		get = function() local n = N() return n and n.parent or 0 end,
		set = function(value) ns.Canvas:Reparent(id, value ~= 0 and value or nil) end,
	})

	Add({ kind = "header", label = L["Layout"] })
	Add({
		kind = "select", label = L["Anchor"], options = ns.POINTS,
		get = function() local n = N() return n and n.point end,
		set = function(value) ns.Canvas:SetAnchor(id, value, N().relPoint) end,
	})
	Add({
		kind = "select", label = L["Relative to"], options = ns.POINTS,
		get = function() local n = N() return n and n.relPoint end,
		set = function(value) ns.Canvas:SetAnchor(id, N().point, value) end,
	})
	NodeField("bool", L["Fill parent"], "fill")
	NodeField("number", L["X offset"], "x", { step = 1 })
	NodeField("number", L["Y offset"], "y", { step = 1 })
	NodeField("number", L["Width"], "w", { step = 1, min = 1 })
	NodeField("number", L["Height"], "h", { step = 1, min = 1 })
	NodeField("number", L["Alpha"], "alpha", { step = 0.05, min = 0, max = 1 })
	NodeField("bool", L["Shown"], "shown")
	if not def.region then
		NodeField("select", L["Strata"], "strata", { options = ns.STRATAS })
	end

	if #def.props > 0 then
		Add({ kind = "header", label = L["Appearance"] })
		for _, prop in ipairs(def.props) do
			NodeField(prop.kind, prop.label, prop.key, {
				options = prop.options, step = prop.step, min = prop.min, max = prop.max,
			})
		end
		-- Template names also pick the matching widget type (and size, from the picker).
		for _, field in ipairs(fields) do
			if field.kind == "template" then
				field.set = function(value, info, catalog)
					value = strtrim(value or "")
					local entry = info or ns.GetTemplateInfo(value)
					local changes = { template = value }
					if entry then
						changes.widget = entry[2]
						if info and entry[4] > 0 and entry[5] > 0 and not N().fill then
							changes.w, changes.h = entry[4], entry[5]
						end
					end
					Doc:SetMany(id, changes)
					-- Catalog templates bring the OnLoad code they need; it also runs while editing.
					if catalog and catalog[5] and (N().scripts.OnLoad or "") == "" then
						Doc:SetScript(id, "OnLoad", catalog[5])
						Doc:Set(id, "editorOnLoad", true, true)
					end
					-- No size in the XML: use what the template set in its OnLoad, if anything.
					if info and not changes.w and not N().fill then
						local holder = ns.Canvas.holders[id]
						local w, h = holder and holder.mfbNaturalWidth, holder and holder.mfbNaturalHeight
						if w and h and w > 0 and h > 0 then
							Doc:SetMany(id, { w = ns.Round(w), h = ns.Round(h) }, true)
						end
					end
				end
			end
		end
	end

	Add({ kind = "header", label = L["Scripts"] })
	for _, script in ipairs(def.scripts) do
		Add({
			kind = "script", label = script.name,
			get = function() local n = N() return n and n.scripts[script.name] end,
			open = function() ns.Dialogs:EditScript(id, script) end,
		})
	end
	return fields
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

function Inspector:Create(parent)
	local frame = W.Inset(parent)
	local title = W.Label(frame, L["Properties"])
	title:SetPoint("TOPLEFT", 8, -7)

	local host = CreateFrame("Frame", nil, frame)
	host:SetPoint("TOPLEFT", 0, -22)
	host:SetPoint("BOTTOMRIGHT")
	local _, content = W.ScrollArea(host)
	self.content = content

	self.empty = W.Label(host, "", "GameFontDisableSmall")
	self.empty:SetPoint("TOPLEFT", 10, -10)
	self.empty:SetPoint("RIGHT", -10, 0)
	self.empty:SetJustifyH("LEFT")
	self.empty:SetSpacing(3)
	self.empty:SetText(L["INSPECTOR_HELP"])

	self.frame = frame
	self:Rebuild()
	return frame
end

function Inspector:Rebuild()
	if not self.content then return end
	self:ReleaseRows()
	self.offset = 4
	local id = Doc.selected
	if id and Doc:Get(id) then
		for _, field in ipairs(self:BuildFields(id)) do
			self:AddRow(field)
		end
	end
	self.content:SetHeight(math.max(1, self.offset + 4))
	self.empty:SetShown(#self.rows == 0)
end

function Inspector:Refresh()
	for _, row in ipairs(self.rows) do
		if row.Refresh then
			row:Refresh()
		end
	end
end

local function Rebuild()
	Inspector:Rebuild()
end

ns.On("PROJECT_CHANGED", Rebuild)
ns.On("STRUCTURE_CHANGED", Rebuild)
ns.On("SELECTION_CHANGED", Rebuild)
ns.On("NODE_CHANGED", function(id)
	if id == Doc.selected then
		Inspector:Refresh()
	end
end)
