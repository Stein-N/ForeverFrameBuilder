-- Forever Frame Builder
-- Panels: the element palette and the layer tree, shown as tabs on the left side of the editor.

local _, ns = ...
local L = ns.L
local Doc = ns.Doc
local W = ns.W

local Panels = {}
ns.Panels = Panels

local PALETTE_COLUMNS = 2
local PALETTE_BUTTON_WIDTH = 88
local PALETTE_ROW_HEIGHT = 24
local TREE_ROW_HEIGHT = 18
local TREE_INDENT = 12

---------------------------------------------------------------------------
-- Palette
---------------------------------------------------------------------------

function Panels:CreatePalette(parent)
	local frame = W.Inset(parent)

	self.paletteButtons = {}
	for i, elementType in ipairs(ns.ElementOrder) do
		local def = ns.Elements[elementType]
		local button = W.Button(frame, def.label, PALETTE_BUTTON_WIDTH)
		local column = (i - 1) % PALETTE_COLUMNS
		local row = math.floor((i - 1) / PALETTE_COLUMNS)
		button:SetPoint("TOPLEFT", 7 + column * (PALETTE_BUTTON_WIDTH + 4), -8 - row * PALETTE_ROW_HEIGHT)
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
		table.insert(self.paletteButtons, button)
	end

	self.palette = frame
	return frame
end

---------------------------------------------------------------------------
-- Layer tree
---------------------------------------------------------------------------

function Panels:CreateTree(parent)
	local frame = W.Inset(parent)

	local host = CreateFrame("Frame", nil, frame)
	host:SetPoint("TOPLEFT", 0, -4)
	host:SetPoint("BOTTOMRIGHT", 0, 30)
	local _, content = W.ScrollArea(host)
	self.treeContent = content
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

	row:SetScript("OnClick", function(self, button)
		Doc:Select(self.id)
		if button == "RightButton" then
			ns.Canvas:ShowContextMenu(self, self.id)
		end
	end)
	return row
end

function Panels:RefreshTree()
	if not self.treeContent then return end
	local entries = {}
	Doc:Walk(function(node, depth)
		table.insert(entries, { node = node, depth = depth })
	end)

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
		row.text:SetPoint("LEFT", 4 + entry.depth * TREE_INDENT, 0)
		row.text:SetText(("%s |cff888888%s|r"):format(node.name, ns.Elements[node.type].label))
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
end

local function RefreshTree()
	Panels:RefreshTree()
end

ns.On("PROJECT_CHANGED", RefreshTree)
ns.On("STRUCTURE_CHANGED", RefreshTree)
ns.On("SELECTION_CHANGED", RefreshTree)
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
