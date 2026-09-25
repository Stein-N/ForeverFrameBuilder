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
local HEADER_HEIGHT = 30
local CATEGORY_HEIGHT = 22
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

-- Section header: Blizzard's list header with a +/- button; a click folds the section.
function Factories.header(row)
	local ok, header = pcall(CreateFrame, "Button", nil, row, "ListHeaderVisualTemplate")
	if not ok or not header.SetHeaderText then
		-- Fallback without the template: plain button with a text.
		header = CreateFrame("Button", nil, row)
		header.text = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		header.text:SetPoint("LEFT", 8, 0)
		header.SetHeaderText = function(self, text) self.text:SetText(text) end
	else
		-- Gold title, white while hovered (the template alone shows grey).
		header:SetTitleColor(false, NORMAL_FONT_COLOR)
		header:SetTitleColor(true, HIGHLIGHT_FONT_COLOR)
		header:SetScript("OnEnter", function(self) self:CheckHighlightTitle(true) end)
		header:SetScript("OnLeave", function(self) self:CheckHighlightTitle(false) end)
	end
	header:SetPoint("TOPLEFT", 4, -2)
	header:SetPoint("BOTTOMRIGHT", -4, 2)
	header:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Inspector:ToggleSection(row.field.section)
	end)
	row.header = header
	row.Setup = function(self, field)
		header:SetHeaderText(field.label)
		if header.CollapseButton then
			header.CollapseButton:UpdateCollapsedState(Inspector:IsCollapsed(field.section))
		end
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

-- Foldable category inside a section, styled like the categories of the AddOn list:
-- gold title with a "bag-arrow" pointing right (collapsed) or down (expanded), and an
-- optional button on the right (e.g. Remove for additional anchors).
function Factories.category(row)
	local button = CreateFrame("Button", nil, row)
	button:SetAllPoints()
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
	highlight:SetBlendMode("ADD")
	highlight:SetPoint("TOPLEFT", 4, 0)
	highlight:SetPoint("BOTTOMRIGHT", -4, 0)
	local arrow = button:CreateTexture(nil, "ARTWORK")
	arrow:SetAtlas("bag-arrow")
	arrow:SetSize(10, 16)
	arrow:SetPoint("LEFT", 12, 0)
	local title = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetJustifyH("LEFT")
	title:SetWordWrap(false)
	local action = W.Button(row, "", 76)
	action:SetHeight(18)
	action:SetPoint("RIGHT", -8, 0)
	action:SetFrameLevel(button:GetFrameLevel() + 2)
	action:SetScript("OnClick", function()
		row.field.action()
	end)
	button:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Inspector:ToggleSection(row.field.section)
	end)
	row.Setup = function(self, field)
		action:SetShown(field.action ~= nil)
		action:SetText(field.actionText or "")
		title:ClearAllPoints()
		title:SetPoint("LEFT", arrow, "RIGHT", 8, 0)
		title:SetPoint("RIGHT", field.action and -90 or -8, 0)
		arrow:SetRotation(Inspector:IsCollapsed(field.section) and math.pi or math.pi / 2)
	end
	row.Refresh = function(self)
		title:SetText(self.field.getTitle and self.field.getTitle() or self.field.label)
	end
end

-- A single button in the control column.
function Factories.action(row)
	local button = W.Button(row, "", 160)
	button:SetPoint("LEFT", CONTROL_LEFT, 0)
	button:SetScript("OnClick", function()
		row.field.action()
	end)
	row.Setup = function(self, field)
		button:SetText(field.text)
	end
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
		if kind ~= "header" and kind ~= "category" then
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
	local height = (field.kind == "header" and HEADER_HEIGHT) or (field.kind == "category" and CATEGORY_HEIGHT) or ROW_HEIGHT
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

-- Elements an anchor may be relative to: the parent, or any element that doesn't
-- (directly or indirectly) depend on this one.
local function AnchorTargetOptions(id)
	local node = Doc:Get(id)
	local options = { { value = 0, label = L["(Parent)"] } }
	Doc:Walk(function(other, depth)
		if other.id ~= node.parent and Doc:CanAnchorTo(id, other.id) then
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

	Add({ kind = "header", label = L["Element"], section = "element" })
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

	Add({ kind = "header", label = L["Layout"], section = "layout" })

	-- General: size and display settings.
	Add({ kind = "category", label = L["General"], section = "layout.general" })
	NodeField("bool", L["Fill parent"], "fill")
	NodeField("number", L["Width"], "w", { step = 1, min = 1 })
	NodeField("number", L["Height"], "h", { step = 1, min = 1 })
	NodeField("number", L["Alpha"], "alpha", { step = 0.05, min = 0, max = 1 })
	NodeField("bool", L["Shown"], "shown")
	if not def.region then
		NodeField("select", L["Strata"], "strata", { options = ns.STRATAS })
	end

	-- One category per anchor point; the first one can't be removed.
	if not node.fill then
		for index = 1, #Doc.GetAnchors(node) do
			local function A()
				local n = N()
				return n and Doc.GetAnchors(n)[index]
			end
			local function SetOffset(axis)
				return function(value, mergeKey, noCheckpoint)
					local list = Doc.GetAnchors(N())
					list[index][axis] = value
					Doc:SetAnchors(id, list, noCheckpoint, mergeKey and (mergeKey .. ":" .. id .. ":" .. index))
				end
			end
			Add({
				kind = "category", label = L["Anchor point %d"]:format(index), section = "layout.anchor" .. index,
				-- The title summarizes the anchor so it stays readable while folded.
				getTitle = function()
					local a = A()
					if not a then return "" end
					local target = a.target ~= 0 and Doc:Get(a.target)
					return ("%s  |cffaaaaaa%s » %s|r"):format(L["Anchor point %d"]:format(index), a.point,
						target and target.name or L["(Parent)"])
				end,
				action = index > 1 and function() ns.Canvas:RemoveAnchor(id, index) end or nil,
				actionText = L["Remove"],
			})
			Add({
				kind = "select", label = L["Anchor"], options = ns.POINTS,
				get = function() local a = A() return a and a.point end,
				set = function(value) ns.Canvas:SetAnchorField(id, index, "point", value) end,
			})
			Add({
				kind = "select", label = L["Relative to"],
				options = function() return AnchorTargetOptions(id) end,
				get = function() local a = A() return a and a.target end,
				set = function(value) ns.Canvas:SetAnchorField(id, index, "target", value) end,
			})
			Add({
				kind = "select", label = L["Relative point"], options = ns.POINTS,
				get = function() local a = A() return a and a.relPoint end,
				set = function(value) ns.Canvas:SetAnchorField(id, index, "relPoint", value) end,
			})
			Add({ kind = "number", label = L["X offset"], step = 1, get = function() local a = A() return a and a.x end, set = SetOffset("x") })
			Add({ kind = "number", label = L["Y offset"], step = 1, get = function() local a = A() return a and a.y end, set = SetOffset("y") })
		end
		if #Doc.GetAnchors(node) < #ns.POINTS then
			-- Belongs to the section, not to the last anchor's category.
			Add({ kind = "action", label = "", text = L["Add anchor point"], outside = true,
				action = function() ns.Canvas:AddAnchor(id) end })
		end
	end

	if #def.props > 0 then
		Add({ kind = "header", label = L["Appearance"], section = "appearance" })
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

	Add({ kind = "header", label = L["Scripts"], section = "scripts" })
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
	local scroll, content = W.ScrollArea(host)
	self.scroll, self.content = scroll, content

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
	local node = id and Doc:Get(id)
	-- Remembered so a change in the number of anchor blocks triggers a rebuild.
	self.builtFill = node and node.fill
	self.builtAnchors = node and #node.anchors
	if node then
		-- Rows of a collapsed section or category are skipped; their headers stay.
		local sectionCollapsed, categoryCollapsed = false, false
		for _, field in ipairs(self:BuildFields(id)) do
			if field.kind == "header" then
				sectionCollapsed = self:IsCollapsed(field.section)
				categoryCollapsed = false
				self:AddRow(field)
			elseif sectionCollapsed then
				-- hidden with its section
			elseif field.kind == "category" then
				categoryCollapsed = self:IsCollapsed(field.section)
				self:AddRow(field)
			elseif field.outside then
				categoryCollapsed = false
				self:AddRow(field)
			elseif not categoryCollapsed then
				self:AddRow(field)
			end
		end
	end
	self.content:SetHeight(math.max(1, self.offset + 4))
	self.empty:SetShown(#self.rows == 0)
end

function Inspector:IsCollapsed(section)
	return section and ns.db.settings.collapsedSections[section] or false
end

function Inspector:ToggleSection(section)
	if not section then return end
	local sections = ns.db.settings.collapsedSections
	sections[section] = not sections[section] or nil
	-- Keep the scroll position so the clicked header stays under the cursor.
	local scroll = self.scroll and self.scroll:GetVerticalScroll()
	self:Rebuild()
	if scroll then
		self.scroll:SetVerticalScroll(math.min(scroll, self.scroll:GetVerticalScrollRange()))
	end
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
	if id ~= Doc.selected then return end
	local node = Doc:Get(id)
	if node and (node.fill ~= Inspector.builtFill or #node.anchors ~= Inspector.builtAnchors) then
		Inspector:Rebuild()
	else
		Inspector:Refresh()
	end
end)
