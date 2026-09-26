-- Forever Frame Builder
-- Panels: the element palette and the layer tree, shown as tabs on the left side of the editor.

local _, ns = ...
local L = ns.L
local Doc = ns.Doc
local W = ns.W

local Panels = {}
ns.Panels = Panels

local PALETTE_ROW_HEIGHT = 24
local PALETTE_BUTTON_INDENT = 18
local TREE_ROW_HEIGHT = 18
local TREE_INDENT = 12
local TREE_TOGGLE_WIDTH = 16

---------------------------------------------------------------------------
-- Palette
---------------------------------------------------------------------------

-- Palette groups by kind of element; element types missing here land in the last group.
local PALETTE_GROUPS = {
	{ key = "containers", label = L["Containers"], types = { "Frame", "Window", "Tabs", "Section", "ScrollFrame" } },
	{ key = "controls", label = L["Controls"], types = { "Button", "CheckButton", "EditBox", "Dropdown", "Slider", "ItemButton" } },
	{ key = "display", label = L["Display"], types = { "StatusBar", "Texture", "FontString", "Model" } },
	{ key = "templates", label = L["Blizzard templates"], types = { "Template" } },
}

local function CreatePaletteButton(parent, elementType)
	local def = ns.Elements[elementType]
	local button = W.Button(parent, def.label, 100)
	button:RegisterForDrag("LeftButton")
	button:SetScript("OnClick", function()
		if not button.dragging then
			ns.Canvas:AddDefault(elementType)
		end
	end)
	button:SetScript("OnDragStart", function()
		button.dragging = true
		ns.Canvas:BeginPaletteDrag(elementType)
	end)
	button:SetScript("OnDragStop", function()
		ns.Canvas:EndPaletteDrag()
		-- The release may also count as a click; ignore it for this frame.
		C_Timer.After(0, function() button.dragging = false end)
	end)
	W.Tooltip(button, def.label, L["Click to add it to the selected frame, or drag it onto the canvas."])
	return button
end

function Panels:CreatePalette(parent)
	local frame = W.Inset(parent)
	local _, content = W.ScrollArea(frame)
	self.paletteContent = content

	local grouped = {}
	for _, group in ipairs(PALETTE_GROUPS) do
		for _, elementType in ipairs(group.types) do
			grouped[elementType] = true
		end
	end
	local last = PALETTE_GROUPS[#PALETTE_GROUPS]
	for _, elementType in ipairs(ns.ElementOrder) do
		if not grouped[elementType] then
			table.insert(last.types, elementType)
		end
	end

	self.paletteButtons = {}
	self.paletteGroups = {}
	for _, group in ipairs(PALETTE_GROUPS) do
		local section = "palette." .. group.key
		local entry = { key = section, buttons = {} }
		entry.header = W.CategoryHeader(content, function()
			local sections = ns.db.settings.collapsedSections
			sections[section] = not sections[section] or nil
			self:LayoutPalette()
		end)
		entry.header:SetTitle(group.label)
		for _, elementType in ipairs(group.types) do
			if ns.Elements[elementType] then
				local button = CreatePaletteButton(content, elementType)
				table.insert(entry.buttons, button)
				table.insert(self.paletteButtons, button)
			end
		end
		table.insert(self.paletteGroups, entry)
	end

	self.palette = frame
	self:LayoutPalette()
	return frame
end

-- Stacks the category headers and, for expanded categories, their full-width buttons.
function Panels:LayoutPalette()
	local content = self.paletteContent
	local offset = 2
	for _, group in ipairs(self.paletteGroups) do
		local collapsed = ns.db.settings.collapsedSections[group.key]
		group.header:ClearAllPoints()
		group.header:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -offset)
		group.header:SetPoint("RIGHT", content, "RIGHT")
		group.header:SetCollapsed(collapsed)
		offset = offset + group.header:GetHeight() + 2
		for _, button in ipairs(group.buttons) do
			button:SetShown(not collapsed)
			if not collapsed then
				button:ClearAllPoints()
				button:SetPoint("TOPLEFT", content, "TOPLEFT", PALETTE_BUTTON_INDENT, -offset)
				button:SetPoint("RIGHT", content, "RIGHT", -4, 0)
				offset = offset + PALETTE_ROW_HEIGHT
			end
		end
		offset = offset + 4
	end
	content:SetHeight(math.max(1, offset))
end

---------------------------------------------------------------------------
-- Layer tree
---------------------------------------------------------------------------

function Panels:CreateTree(parent)
	local frame = W.Inset(parent)

	local host = CreateFrame("Frame", nil, frame)
	host:SetPoint("TOPLEFT", 0, -4)
	host:SetPoint("BOTTOMRIGHT", 0, 30)
	local scroll, content = W.ScrollArea(host)
	self.treeScroll, self.treeContent = scroll, content
	self.treeRows = {}

	self.treeEmpty = W.Label(host, L["No elements yet.\nDrag one from the palette onto the canvas."], "GameFontDisableSmall")
	self.treeEmpty:SetPoint("TOPLEFT", 10, -10)
	self.treeEmpty:SetPoint("RIGHT", -10, 0)
	self.treeEmpty:SetJustifyH("LEFT")

	local up = W.IconButton(frame, "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton", 24, function()
		Doc:Reorder(Doc.selected, -1)
	end, L["Move up (draw below)"], true)
	up:SetPoint("BOTTOMLEFT", 6, 4)
	local down = W.IconButton(frame, "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton", 24, function()
		Doc:Reorder(Doc.selected, 1)
	end, L["Move down (draw on top)"], true)
	down:SetPoint("LEFT", up, "RIGHT", 2, 0)
	local delete = W.Button(frame, L["Delete"], 60, function()
		Doc:Remove(Doc.selected)
	end)
	delete:SetPoint("BOTTOMRIGHT", -6, 5)
	local duplicate = W.Button(frame, L["Duplicate"], 70, function()
		Doc:Duplicate(Doc.selected)
	end)
	duplicate:SetPoint("RIGHT", delete, "LEFT", -2, 0)
	self.treeButtons = { up, down, delete, duplicate }

	self.tree = frame
	self:RefreshTree()
	return frame
end

function Panels:CreateTreeRow()
	local row = CreateFrame("Button", nil, self.treeContent)
	row:SetHeight(TREE_ROW_HEIGHT)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	row.selected = row:CreateTexture(nil, "BACKGROUND")
	row.selected:SetAllPoints()
	row.selected:SetColorTexture(0.2, 0.6, 1, 0.35)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetJustifyH("LEFT")
	row.text:SetPoint("RIGHT", -4, 0)
	row.text:SetWordWrap(false)

	-- +/- for elements with children. Its clicks must not also select the row.
	local toggle = CreateFrame("Button", nil, row, "CollapseButtonTemplate")
	toggle:SetSize(TREE_TOGGLE_WIDTH, TREE_ROW_HEIGHT)
	if toggle.SetPropagateMouseClicks then
		toggle:SetPropagateMouseClicks(false)
	end
	toggle:SetScript("OnClick", function()
		PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
		Panels:ToggleTreeNode(row.id)
	end)
	row.toggle = toggle

	row:SetScript("OnClick", function(self, button)
		Doc:Select(self.id)
		if button == "RightButton" then
			ns.Canvas:ShowContextMenu(self, self.id)
		end
	end)
	return row
end

local function CountDescendants(node)
	local count = 0
	for _, childId in ipairs(node.children) do
		local child = Doc:Get(childId)
		if child then
			count = count + 1 + CountDescendants(child)
		end
	end
	return count
end

-- Visible tree rows: children of folded elements are skipped.
local function CollectEntries(list, parentId, depth)
	for _, id in ipairs(Doc:ChildList(parentId)) do
		local node = Doc:Get(id)
		if node then
			table.insert(list, { node = node, depth = depth })
			if not node.treeCollapsed then
				CollectEntries(list, id, depth + 1)
			end
		end
	end
	return list
end

-- A selection inside a part that gets folded moves to the folded element, so folding
-- isn't undone right away by revealing the selection again.
local function KeepSelectionVisible(id)
	if Doc.selected and Doc:IsAncestor(id, Doc.selected) then
		Doc:Select(id)
	end
end

function Panels:ToggleTreeNode(id)
	local node = Doc:Get(id)
	if not node then return end
	node.treeCollapsed = not node.treeCollapsed or nil
	if node.treeCollapsed then
		KeepSelectionVisible(id)
	end
	self:RefreshTree()
end

-- Folds or unfolds an element and every element below it.
function Panels:SetSubtreeCollapsed(id, collapsed)
	local node = Doc:Get(id)
	if not node then return end
	local function Apply(current)
		if #current.children > 0 then
			current.treeCollapsed = collapsed or nil
		end
		for _, childId in ipairs(current.children) do
			local child = Doc:Get(childId)
			if child then Apply(child) end
		end
	end
	Apply(node)
	if collapsed then
		KeepSelectionVisible(id)
	end
	self:RefreshTree()
end

-- Unfolds the ancestors of the selected element so its row is shown.
function Panels:RevealSelection()
	local node = Doc:GetSelected()
	local parent = node and Doc:Get(node.parent)
	while parent do
		parent.treeCollapsed = nil
		parent = Doc:Get(parent.parent)
	end
end

function Panels:RefreshTree()
	if not self.treeContent then return end
	local entries = CollectEntries({}, nil, 0)

	for i, entry in ipairs(entries) do
		local row = self.treeRows[i]
		if not row then
			row = self:CreateTreeRow()
			self.treeRows[i] = row
		end
		local node = entry.node
		row.id = node.id
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", self.treeContent, "TOPLEFT", 0, -(i - 1) * TREE_ROW_HEIGHT)
		row:SetPoint("RIGHT", self.treeContent, "RIGHT")
		local indent = 2 + entry.depth * TREE_INDENT
		local hasChildren = #node.children > 0
		row.toggle:ClearAllPoints()
		row.toggle:SetPoint("LEFT", indent, 0)
		row.toggle:SetShown(hasChildren)
		if hasChildren then
			row.toggle:UpdateCollapsedState(node.treeCollapsed and true or false)
		end
		row.text:SetPoint("LEFT", indent + TREE_TOGGLE_WIDTH + 2, 0)
		local hidden = node.treeCollapsed and CountDescendants(node) or 0
		row.text:SetText(("%s |cff888888%s%s|r"):format(node.name, ns.Elements[node.type].label,
			hidden > 0 and (" (" .. hidden .. ")") or ""))
		row.text:SetAlpha(node.shown and 1 or 0.45)
		row.selected:SetShown(node.id == Doc.selected)
		row:Show()
	end
	for i = #entries + 1, #self.treeRows do
		self.treeRows[i]:Hide()
	end
	self.treeContent:SetHeight(math.max(1, #entries * TREE_ROW_HEIGHT))
	self.treeEmpty:SetShown(#entries == 0)

	local hasSelection = Doc.selected ~= nil
	for _, button in ipairs(self.treeButtons) do
		button:SetEnabled(hasSelection)
	end
	self:ScrollToSelection(entries)
end

-- Scrolls the layer list so the selected row is inside the visible area.
function Panels:ScrollToSelection(entries)
	local scroll = self.treeScroll
	if not scroll or not Doc.selected then return end
	for i, entry in ipairs(entries) do
		if entry.node.id == Doc.selected then
			local top, bottom = (i - 1) * TREE_ROW_HEIGHT, i * TREE_ROW_HEIGHT
			local current, height = scroll:GetVerticalScroll() or 0, scroll:GetHeight() or 0
			if height > 0 and top < current then
				scroll:SetVerticalScroll(top)
			elseif height > 0 and bottom > current + height then
				scroll:SetVerticalScroll(bottom - height)
			end
			return
		end
	end
end

local function RefreshTree()
	Panels:RefreshTree()
end

ns.On("PROJECT_CHANGED", RefreshTree)
ns.On("STRUCTURE_CHANGED", RefreshTree)
ns.On("SELECTION_CHANGED", function()
	-- Selecting a hidden element (e.g. on the canvas or a new child) unfolds its parents.
	Panels:RevealSelection()
	RefreshTree()
end)
ns.On("NODE_CHANGED", function(_, key)
	if key == "name" or key == "shown" then
		RefreshTree()
	end
end)
ns.On("PREVIEW_CHANGED", function(preview)
	for _, button in ipairs(Panels.paletteButtons or {}) do
		button:SetEnabled(not preview)
	end
end)
