-- Forever Frame Builder
-- Editor: main window with toolbar, palette, layer tree, canvas and inspector.

local _, ns = ...
local L = ns.L
local Doc = ns.Doc
local W = ns.W

local Editor = {}
ns.Editor = Editor

local DEFAULT_WIDTH, DEFAULT_HEIGHT = 1200, 720
local MIN_WIDTH, MIN_HEIGHT = 1000, 540
local LEFT_WIDTH = 200
local RIGHT_WIDTH = 280
local TOOLBAR_TOP = -28
local BODY_TOP = -60
local STATUS_HEIGHT = 22
-- Top tabs are 32 px high, but only their lower 24 px are drawn.
local LEFT_TABS_HEIGHT = 26

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

function Editor:Create()
	local frame = CreateFrame("Frame", "ForeverFrameBuilderEditor", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(frame)
	ButtonFrameTemplate_HideButtonBar(frame)
	if frame.Inset then frame.Inset:Hide() end
	ns.SetFrameTitle(frame, ns.title)
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:SetResizable(true)
	frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		Editor:SavePosition()
	end)
	frame:SetScript("OnHide", function()
		if ns.Canvas.preview then
			ns.Canvas:SetPreview(false)
		end
	end)
	table.insert(UISpecialFrames, frame:GetName())
	self.frame = frame

	local grip = CreateFrame("Button", nil, frame)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -4, 4)
	grip:SetFrameLevel(frame:GetFrameLevel() + 20)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetScript("OnMouseDown", function()
		frame:StartSizing("BOTTOMRIGHT")
	end)
	grip:SetScript("OnMouseUp", function()
		frame:StopMovingOrSizing()
		Editor:SavePosition()
	end)

	self:CreateToolbar()
	self:CreateBody()
	self:CreateStatusBar()
	self:SetupKeyboard()
	self:RestorePosition()

	self:UpdateProject()
	self:UpdateHistory()
	self:UpdateZoom()
	self:UpdateStatus()
end

function Editor:SavePosition()
	local frame = self.frame
	local point, _, relPoint, x, y = frame:GetPoint()
	ns.db.settings.window = {
		point = point, relPoint = relPoint, x = x, y = y,
		w = frame:GetWidth(), h = frame:GetHeight(),
	}
end

function Editor:RestorePosition()
	local frame = self.frame
	if not frame then return end
	local saved = ns.db.settings.window
	frame:ClearAllPoints()
	if saved and saved.point then
		frame:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
		frame:SetSize(math.max(MIN_WIDTH, saved.w), math.max(MIN_HEIGHT, saved.h))
	else
		frame:SetPoint("CENTER")
		frame:SetSize(math.max(MIN_WIDTH, math.min(DEFAULT_WIDTH, UIParent:GetWidth() - 40)),
			math.max(MIN_HEIGHT, math.min(DEFAULT_HEIGHT, UIParent:GetHeight() - 80)))
	end
end

function Editor:ResetPosition()
	self:RestorePosition()
end

function Editor:Toggle()
	if not self.frame then
		self:Create()
		self.frame:Show()
		return
	end
	self.frame:SetShown(not self.frame:IsShown())
end

---------------------------------------------------------------------------
-- Toolbar
---------------------------------------------------------------------------

local function ProjectMenu(_, root)
	root:CreateTitle(L["Projects"])
	for _, name in ipairs(Doc:ProjectNames()) do
		root:CreateRadio(name,
			function() return Doc:CurrentName() == name end,
			function() Doc:SwitchProject(name) end)
	end
	root:CreateDivider()
	root:CreateButton(L["New project…"], function()
		ns.Dialogs:Prompt(L["Name of the new project:"], L["My Frame"], function(text)
			Doc:NewProject(text)
		end)
	end)
	root:CreateButton(L["Rename…"], function()
		local current = Doc:CurrentName()
		ns.Dialogs:Prompt(L["New name:"], current, function(text)
			Doc:RenameProject(current, text)
		end)
	end)
	root:CreateButton(L["Duplicate project"], function()
		Doc:DuplicateProject(Doc:CurrentName())
	end)
	root:CreateButton("|cffff4040" .. L["Delete project…"] .. "|r", function()
		local current = Doc:CurrentName()
		ns.Dialogs:Confirm(L["Delete the project \"%s\"?"]:format(current), function()
			Doc:DeleteProject(current)
		end)
	end)
end

local function ExportMenu(_, root)
	root:CreateButton(L["Lua code…"], function() ns.Dialogs:ShowExportLua() end)
	local share = root:CreateButton(L["Share string…"], function() ns.Dialogs:ShowExportString() end)
	local import = root:CreateButton(L["Import string…"], function() ns.Dialogs:ShowImport() end)
	if not ns.Exporter:CanShare() then
		share:SetEnabled(false)
		import:SetEnabled(false)
	end
end

function Editor:CreateToolbar()
	local frame = self.frame
	local settings = ns.db.settings

	local project = W.Dropdown(frame, 170)
	project:SetPoint("TOPLEFT", 12, TOOLBAR_TOP)
	project:SetupMenu(ProjectMenu)
	self.projectDropdown = project

	local undo = W.IconButton(frame, "Interface\\Buttons\\UI-RotationLeft-Button", 28, function()
		Doc:Undo()
	end, L["Undo"] .. " (Ctrl+Z)")
	undo:SetPoint("LEFT", project, "RIGHT", 8, 0)
	local redo = W.IconButton(frame, "Interface\\Buttons\\UI-RotationRight-Button", 28, function()
		Doc:Redo()
	end, L["Redo"] .. " (Ctrl+Y)")
	redo:SetPoint("LEFT", undo, "RIGHT", 2, 0)
	self.undoButton, self.redoButton = undo, redo

	local grid = W.Check(frame, L["Grid"], function(checked)
		settings.showGrid = checked
		ns.Canvas:RebuildGrid()
	end)
	grid:SetPoint("LEFT", redo, "RIGHT", 12, 0)
	grid:SetChecked(settings.showGrid)

	local gridSize = W.EditBox(frame, 30)
	gridSize:SetPoint("LEFT", grid, "LEFT", grid.width + 6, 0)
	gridSize:SetNumeric(true)
	gridSize:SetMaxLetters(3)
	gridSize:SetText(settings.gridSize)
	gridSize:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	gridSize:SetScript("OnEditFocusLost", function(self)
		local value = tonumber(self:GetText())
		if value and value >= 2 and value <= 100 then
			settings.gridSize = value
			ns.Canvas:RebuildGrid()
		end
		self:SetText(settings.gridSize)
	end)
	W.Tooltip(gridSize, L["Grid size"], L["Distance between grid lines in pixels."])

	local snap = W.Check(frame, L["Snap"], function(checked)
		settings.snap = checked
	end, L["Snap positions and sizes to the grid while dragging."])
	snap:SetPoint("LEFT", gridSize, "RIGHT", 10, 0)
	snap:SetChecked(settings.snap)

	local zoomOut = W.Button(frame, "-", 24, function()
		ns.Canvas:SetZoom(ns.Canvas.zoom / 1.25)
	end)
	zoomOut:SetPoint("LEFT", snap, "LEFT", snap.width + 12, 0)
	local zoomLabel = W.Label(frame, "100%", "GameFontHighlightSmall")
	zoomLabel:SetWidth(44)
	zoomLabel:SetPoint("LEFT", zoomOut, "RIGHT", 2, 0)
	self.zoomLabel = zoomLabel
	local zoomIn = W.Button(frame, "+", 24, function()
		ns.Canvas:SetZoom(ns.Canvas.zoom * 1.25)
	end)
	zoomIn:SetPoint("LEFT", zoomLabel, "RIGHT", 2, 0)
	local fit = W.Button(frame, L["Fit"], 50, function()
		ns.Canvas:FitZoom()
	end, L["Fit the whole screen area into the canvas."])
	fit:SetPoint("LEFT", zoomIn, "RIGHT", 2, 0)
	local actual = W.Button(frame, "1:1", 40, function()
		ns.Canvas:SetZoom(1)
	end, L["Show the design at its real size."])
	actual:SetPoint("LEFT", fit, "RIGHT", 2, 0)

	local preview = W.Button(frame, L["Preview"], 100, function()
		ns.Canvas:SetPreview(not ns.Canvas.preview)
	end, L["Try the design: buttons, inputs and scripts become active."])
	preview:SetPoint("TOPRIGHT", -12, TOOLBAR_TOP)
	self.previewButton = preview

	local export = W.Button(frame, L["Export"], 90, nil)
	export:SetPoint("RIGHT", preview, "LEFT", -4, 0)

	local errors = W.Button(frame, "Errors", 90, function()
		ns.Errors:Toggle()
	end, L["Recorded errors with template, properties and all scripts – for faster bug fixing."])
	errors:SetPoint("RIGHT", export, "LEFT", -4, 0)
	self.errorsButton = errors
	self:UpdateErrorCount()
	export:SetScript("OnClick", function(self)
		MenuUtil.CreateContextMenu(self, ExportMenu)
	end)
end

---------------------------------------------------------------------------
-- Body
---------------------------------------------------------------------------

function Editor:CreateBody()
	local frame = self.frame

	-- Left column: elements and layers as two top tabs sharing the full height.
	local left = CreateFrame("Frame", nil, frame)
	left:SetPoint("TOPLEFT", 8, BODY_TOP - LEFT_TABS_HEIGHT)
	left:SetPoint("BOTTOMLEFT", 8, STATUS_HEIGHT + 6)
	left:SetWidth(LEFT_WIDTH)
	self.left = left

	local palette = ns.Panels:CreatePalette(left)
	palette:SetAllPoints()
	local tree = ns.Panels:CreateTree(left)
	tree:SetAllPoints()
	self.leftPanels = { palette, tree }

	left.Tabs = {}
	for i, label in ipairs({ L["Elements"], L["Layers"] }) do
		local tab = CreateFrame("Button", nil, left, "PanelTopTabButtonTemplate")
		left.Tabs[i] = tab
		tab:SetID(i)
		tab:SetText(label)
		if i == 1 then
			tab:SetPoint("BOTTOMLEFT", left, "TOPLEFT", 6, -2)
		else
			tab:SetPoint("BOTTOMLEFT", left.Tabs[i - 1], "BOTTOMRIGHT", 1, 0)
		end
		PanelTemplates_TabResize(tab, 0)
		tab:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			Editor:SelectLeftTab(self:GetID())
		end)
	end
	PanelTemplates_SetNumTabs(left, #left.Tabs)
	self:SelectLeftTab(ns.db.settings.leftTab)

	local inspector = ns.Inspector:Create(frame)
	inspector:SetPoint("TOPRIGHT", -8, BODY_TOP)
	inspector:SetPoint("BOTTOMRIGHT", -8, STATUS_HEIGHT + 6)
	inspector:SetWidth(RIGHT_WIDTH)

	local canvasInset = W.Inset(frame)
	canvasInset:SetPoint("TOPLEFT", 8 + LEFT_WIDTH + 6, BODY_TOP)
	canvasInset:SetPoint("BOTTOMRIGHT", inspector, "BOTTOMLEFT", -6, 0)
	ns.Canvas:Create(canvasInset)
	ns.Canvas.clip:SetPoint("TOPLEFT", 3, -3)
	ns.Canvas.clip:SetPoint("BOTTOMRIGHT", -3, 3)
end

function Editor:SelectLeftTab(index)
	index = (index == 2) and 2 or 1
	ns.db.settings.leftTab = index
	PanelTemplates_SetTab(self.left, index)
	for i, panel in ipairs(self.leftPanels) do
		panel:SetShown(i == index)
	end
end

function Editor:CreateStatusBar()
	local frame = self.frame
	local hint = W.Label(frame, L["STATUS_HINT"], "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", 14, 10)
	hint:SetPoint("RIGHT", -160, 0)
	hint:SetJustifyH("LEFT")
	hint:SetWordWrap(false)
	self.hint = hint

	local count = W.Label(frame, "", "GameFontHighlightSmall")
	count:SetPoint("BOTTOMRIGHT", -26, 10)
	self.countLabel = count
end

---------------------------------------------------------------------------
-- Keyboard
---------------------------------------------------------------------------

function Editor:HandleKey(key)
	if ns.Canvas.preview then return false end
	local ctrl, shift = IsControlKeyDown(), IsShiftKeyDown()
	local selected = Doc:GetSelected()

	if ctrl and key == "Z" then
		if shift then Doc:Redo() else Doc:Undo() end
		return true
	elseif ctrl and key == "Y" then
		Doc:Redo()
		return true
	elseif ctrl and key == "V" then
		Doc:Paste()
		return true
	elseif not selected then
		return false
	end

	if key == "DELETE" then
		Doc:Remove(selected.id)
	elseif key == "ESCAPE" then
		Doc:Select(nil)
	elseif ctrl and key == "D" then
		Doc:Duplicate(selected.id)
	elseif ctrl and key == "C" then
		Doc:Copy(selected.id)
	elseif key == "LEFT" or key == "RIGHT" or key == "UP" or key == "DOWN" then
		local step = shift and ns.db.settings.gridSize or 1
		local dx = (key == "LEFT" and -step) or (key == "RIGHT" and step) or 0
		local dy = (key == "DOWN" and -step) or (key == "UP" and step) or 0
		Doc:SetMany(selected.id, Doc.ShiftAnchors(selected, dx, dy), false, "nudge:" .. selected.id)
	else
		return false
	end
	return true
end

function Editor:SetupKeyboard()
	local frame = self.frame
	-- Keyboard propagation is restricted in combat; only listen while out of combat.
	local function Listen(enabled)
		pcall(frame.EnableKeyboard, frame, enabled)
		if enabled then
			frame:SetPropagateKeyboardInput(true)
		end
	end
	Listen(not InCombatLockdown())
	frame:SetScript("OnKeyDown", function(self, key)
		if InCombatLockdown() then return end
		self:SetPropagateKeyboardInput(not Editor:HandleKey(key))
	end)
	frame:SetScript("OnKeyUp", function(self)
		if not InCombatLockdown() then
			self:SetPropagateKeyboardInput(true)
		end
	end)
	ns.On("COMBAT", function(inCombat)
		Listen(not inCombat)
	end)
end

---------------------------------------------------------------------------
-- State updates
---------------------------------------------------------------------------

function Editor:UpdateProject()
	if self.projectDropdown then
		self.projectDropdown:OverrideText(Doc:CurrentName() or "")
	end
end

function Editor:UpdateHistory()
	if self.undoButton then
		self.undoButton:SetEnabled(Doc:CanUndo() and not ns.Canvas.preview)
		self.redoButton:SetEnabled(Doc:CanRedo() and not ns.Canvas.preview)
	end
end

function Editor:UpdateZoom()
	if self.zoomLabel then
		self.zoomLabel:SetText(("%d%%"):format(ns.Canvas.zoom * 100 + 0.5))
	end
end

function Editor:UpdateStatus()
	if self.countLabel then
		self.countLabel:SetText(L["%d elements"]:format(Doc:Count()))
	end
end

function Editor:UpdatePreview(preview)
	if not self.previewButton then return end
	self.previewButton:SetText(preview and L["Edit mode"] or L["Preview"])
	self.hint:SetText(preview and L["PREVIEW_HINT"] or L["STATUS_HINT"])
	self:UpdateHistory()
end

-- "Errors (3)" in red while something is recorded.
function Editor:UpdateErrorCount()
	if not self.errorsButton then return end
	local count = ns.Errors:Count()
	self.errorsButton:SetText(count > 0 and ("|cffff4040Errors (" .. count .. ")|r") or "Errors")
end

ns.On("ERRORS_CHANGED", function() Editor:UpdateErrorCount() end)
ns.On("PROJECT_CHANGED", function()
	Editor:UpdateProject()
	Editor:UpdateStatus()
end)
ns.On("STRUCTURE_CHANGED", function() Editor:UpdateStatus() end)
ns.On("HISTORY_CHANGED", function() Editor:UpdateHistory() end)
ns.On("ZOOM_CHANGED", function() Editor:UpdateZoom() end)
ns.On("PREVIEW_CHANGED", function(preview) Editor:UpdatePreview(preview) end)
