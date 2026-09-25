-- Forever Frame Builder
-- Canvas: renders the project and handles selecting, moving, resizing, panning and zooming.
--
-- The design area ("content") has the size of UIParent, so top-level elements map 1:1 to the
-- screen. It is scaled for zooming and clipped by the canvas frame. Every element is drawn
-- by a real widget ("holder"); in edit mode a transparent overlay above all elements catches
-- the mouse and hit-tests the holders, so buttons, edit boxes etc. stay inert until Preview.

local _, ns = ...
local L = ns.L
local Doc = ns.Doc
local W = ns.W

local Canvas = {}
ns.Canvas = Canvas

local MIN_SIZE = 4
local ZOOM_MIN, ZOOM_MAX = 0.2, 3
local GRIP_SIZE = 8
local HOVER_INTERVAL = 0.05
local ACCENT = { 0.2, 0.6, 1 }
local DROP = { 0.2, 1, 0.3 }

local GRIPS = {
	TOPLEFT = { left = true, top = true },
	TOP = { top = true },
	TOPRIGHT = { right = true, top = true },
	LEFT = { left = true },
	RIGHT = { right = true },
	BOTTOMLEFT = { left = true, bottom = true },
	BOTTOM = { bottom = true },
	BOTTOMRIGHT = { right = true, bottom = true },
}

Canvas.holders = {}
Canvas.order = {}
Canvas.pools = {}
Canvas.gridLines = {}
Canvas.zoom = 1
Canvas.panX, Canvas.panY = 0, 0
Canvas.preview = false

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

function Canvas:Create(parent)
	local clip = CreateFrame("Frame", nil, parent)
	clip:SetClipsChildren(true)
	self.clip = clip

	local background = clip:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.04, 0.04, 0.05, 1)

	-- The design area represents UIParent.
	local content = CreateFrame("Frame", nil, clip)
	content:SetSize(UIParent:GetSize())
	self.content = content
	local screen = content:CreateTexture(nil, "BACKGROUND")
	screen:SetAllPoints()
	screen:SetColorTexture(0.11, 0.11, 0.13, 1)
	W.Outline(content, ACCENT[1], ACCENT[2], ACCENT[3], 0.6, 1, "BORDER")

	self.gridFrame = CreateFrame("Frame", nil, content)
	self.gridFrame:SetAllPoints()
	self.gridFrame:SetFrameLevel(content:GetFrameLevel() + 1)

	self.poolParent = CreateFrame("Frame", nil, UIParent)
	self.poolParent:Hide()

	self:CreateOverlay()
	self:CreateGhost()

	self.driver = CreateFrame("Frame")

	clip:SetScript("OnSizeChanged", function()
		if not self.initialized then
			self.initialized = true
			self:FitZoom()
		end
		self:UpdateContentPoint()
	end)

	local sizeWatcher = CreateFrame("Frame")
	sizeWatcher:RegisterEvent("UI_SCALE_CHANGED")
	sizeWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
	sizeWatcher:SetScript("OnEvent", function()
		content:SetSize(UIParent:GetSize())
		self:RebuildGrid()
	end)

	self:RebuildGrid()
	self:Rebuild()
end

function Canvas:CreateOverlay()
	local overlay = CreateFrame("Frame", nil, self.clip)
	overlay:SetAllPoints(self.clip)
	overlay:EnableMouse(true)
	overlay:EnableMouseWheel(true)
	self.overlay = overlay

	overlay:SetScript("OnMouseDown", function(_, button)
		self:OnMouseDown(button)
	end)
	overlay:SetScript("OnMouseUp", function(_, button)
		self:EndDrag(button)
	end)
	overlay:SetScript("OnMouseWheel", function(_, delta)
		if IsControlKeyDown() and self:ScrollUnderCursor(delta) then return end
		self:SetZoom(self.zoom * (delta > 0 and 1.1 or 1 / 1.1), true)
	end)
	overlay:SetScript("OnLeave", function()
		self.hover:Hide()
	end)
	local elapsed = 0
	overlay:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + dt
		if elapsed >= HOVER_INTERVAL then
			elapsed = 0
			self:UpdateHover()
		end
	end)

	-- Hover outline
	local hover = CreateFrame("Frame", nil, overlay)
	W.Outline(hover, 1, 1, 1, 0.6, 1)
	hover:Hide()
	self.hover = hover

	-- Selection outline with resize grips and a name label
	local selection = CreateFrame("Frame", nil, overlay)
	W.Outline(selection, ACCENT[1], ACCENT[2], ACCENT[3], 1, 2)
	selection:Hide()
	self.selection = selection

	local label = selection:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("BOTTOMLEFT", selection, "TOPLEFT", 0, 3)
	selection.label = label
	local labelBg = selection:CreateTexture(nil, "ARTWORK")
	labelBg:SetColorTexture(0, 0, 0, 0.7)
	labelBg:SetPoint("TOPLEFT", label, "TOPLEFT", -3, 2)
	labelBg:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 3, -2)

	selection.grips = {}
	for point, edges in pairs(GRIPS) do
		local grip = CreateFrame("Frame", nil, selection)
		table.insert(selection.grips, grip)
		grip:SetSize(GRIP_SIZE, GRIP_SIZE)
		grip:SetPoint("CENTER", selection, point)
		grip:EnableMouse(true)
		local border = grip:CreateTexture(nil, "ARTWORK")
		border:SetAllPoints()
		border:SetColorTexture(0, 0, 0, 1)
		local fill = grip:CreateTexture(nil, "OVERLAY")
		fill:SetPoint("TOPLEFT", 1, -1)
		fill:SetPoint("BOTTOMRIGHT", -1, 1)
		fill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1)
		grip:SetScript("OnEnter", function() fill:SetColorTexture(1, 1, 1, 1) end)
		grip:SetScript("OnLeave", function() fill:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 1) end)
		grip:SetScript("OnMouseDown", function(_, button)
			if button == "LeftButton" and Doc.selected then
				self:BeginResize(Doc.selected, edges)
			end
		end)
		grip:SetScript("OnMouseUp", function(_, button)
			self:EndDrag(button)
		end)
	end
end

-- Preview shown under the cursor while dragging an element from the palette.
function Canvas:CreateGhost()
	local ghost = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	ghost:SetFrameStrata("TOOLTIP")
	ghost:SetBackdrop(ns.BACKDROPS.Solid)
	ghost:SetBackdropColor(ACCENT[1], ACCENT[2], ACCENT[3], 0.25)
	ghost:SetBackdropBorderColor(ACCENT[1], ACCENT[2], ACCENT[3], 1)
	ghost.text = ghost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	ghost.text:SetPoint("CENTER")
	ghost:Hide()
	ghost:SetScript("OnUpdate", function(frame)
		local x, y = GetCursorPosition()
		local scale = UIParent:GetEffectiveScale()
		frame:ClearAllPoints()
		frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
	end)
	self.ghost = ghost
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

-- The frame children of an element are anchored to (a scroll frame's content, or the holder).
function Canvas:ChildParent(id)
	local holder = id and self.holders[id]
	if not holder then
		return self.content
	end
	local def = ns.Elements[holder.mfbType]
	return def.GetChildParent and def.GetChildParent(holder) or holder
end

-- Whether an element currently clips its children (scroll frames, frames with clipping on).
local function Clips(node)
	local clips = ns.Elements[node.type].clips
	if type(clips) == "function" then
		return clips(node.props)
	end
	return clips
end

-- An element counts as under the cursor only where no clipping ancestor hides it.
function Canvas:IsVisibleUnderCursor(id)
	local node = Doc:Get(Doc:Get(id).parent)
	while node do
		if Clips(node) and not self.holders[node.id]:IsMouseOver() then
			return false
		end
		node = Doc:Get(node.parent)
	end
	return true
end

-- Elements whose widget depends on a property (window style, template name, ...) are
-- pooled per variant, because a frame's template can't be changed after creation.
local function PoolKey(node)
	local def = ns.Elements[node.type]
	return def.PoolKey and def.PoolKey(node.props) or node.type
end

function Canvas:Acquire(node)
	local key = PoolKey(node)
	local pool = self.pools[key]
	local holder = pool and table.remove(pool)
	if not holder then
		holder = ns.Elements[node.type].Create(self.poolParent, node.props, node)
		holder.mfbType = node.type
		holder.mfbPoolKey = key
		-- Some templates size themselves in OnLoad (e.g. side tabs); remember it for the picker.
		holder.mfbNaturalWidth, holder.mfbNaturalHeight = holder:GetSize()
	end
	return holder
end

function Canvas:Release(holder)
	holder:Hide()
	holder:ClearAllPoints()
	holder:SetParent(self.poolParent)
	-- Script hooks from Preview can't be removed, so such widgets are never reused.
	if holder.mfbTainted then return end
	self.pools[holder.mfbPoolKey] = self.pools[holder.mfbPoolKey] or {}
	table.insert(self.pools[holder.mfbPoolKey], holder)
end

function Canvas:Rebuild()
	if not self.content then return end
	for _, holder in pairs(self.holders) do
		self:Release(holder)
	end
	wipe(self.holders)
	wipe(self.order)

	-- Explicit, increasing frame levels keep the draw order equal to the tree order,
	-- which is also the order the hit test relies on.
	local level = self.content:GetFrameLevel() + 2
	Doc:Walk(function(node)
		local holder = self:Acquire(node)
		holder:SetParent(self:ChildParent(node.parent))
		holder:SetFrameLevel(level)
		level = level + 2
		holder.mfbId = node.id
		self.holders[node.id] = holder
		table.insert(self.order, node.id)
	end)
	for _, id in ipairs(self.order) do
		self:ApplyNode(id)
	end
	-- Templates may use high fixed frame levels (title bars use 510), so the overlay
	-- sits well above anything an element can bring along.
	self.overlay:SetFrameLevel(math.max(level + 10, 9000))

	if self.preview then
		self:RunScripts()
	else
		self:RunEditorOnLoads()
	end
	self:UpdateSelection()
	self.hover:Hide()
end

function Canvas:ApplyNode(id)
	local node = Doc:Get(id)
	local holder = self.holders[id]
	if not node or not holder then return end
	local def = ns.Elements[node.type]
	local ok, err, stack = ns.Errors.Call(def.Apply, holder, node.props, self.preview)
	if not ok then
		ns.Print(L["Could not apply %s: %s"], node.name, tostring(err))
		ns.Errors:Add({ kind = "apply", message = err, stack = stack, node = node })
	end
	holder:ClearAllPoints()
	if node.fill then
		holder:SetAllPoints(self:ChildParent(node.parent))
	else
		-- With anchors on opposite edges the anchors decide that axis and the size is ignored.
		holder:SetSize(math.max(1, node.w), math.max(1, node.h))
		for _, anchor in ipairs(Doc.GetAnchors(node)) do
			holder:SetPoint(anchor.point, self:AnchorFrame(node, anchor.target), anchor.relPoint, anchor.x, anchor.y)
		end
	end
	if def.Layout then
		ok, err, stack = ns.Errors.Call(def.Layout, holder, node, self.preview)
		if not ok then
			ns.Print(L["Could not apply %s: %s"], node.name, tostring(err))
			ns.Errors:Add({ kind = "apply", message = err, stack = stack, node = node })
		end
	end
	if self.preview then
		holder:SetAlpha(node.alpha)
		holder:SetShown(node.shown)
	else
		-- Hidden elements stay visible (faded) while editing so they can still be selected.
		holder:SetAlpha(node.shown and node.alpha or node.alpha * 0.3)
		holder:Show()
		holder.mfbSelectTab, holder.mfbActiveTab, holder.SelectTab = nil, nil, nil
		holder.mfbCollapsed, holder.SetCollapsed = nil, nil
		for key in pairs(holder) do
			if type(key) == "string" and key:find("^mfbMethod") then
				holder[key] = nil
			end
		end
	end
	if def.ChildShown then
		self:UpdateChildVisibility(id)
	end
	local parent = Doc:Get(node.parent)
	if parent and ns.Elements[parent.type].ChildShown then
		self:UpdateChildVisibility(parent.id)
	end
end

-- Tab containers show only the page of the active tab.
function Canvas:ActiveTab(id)
	local holder = self.holders[id]
	return (self.preview and holder and holder.mfbActiveTab) or Doc:Get(id).props.activeTab
end

-- Collapsible sections hide their content while collapsed.
function Canvas:IsCollapsed(id)
	local holder = self.holders[id]
	if self.preview and holder and holder.mfbCollapsed ~= nil then
		return holder.mfbCollapsed
	end
	return Doc:Get(id).props.collapsed
end

-- Elements with ChildShown (tabs, sections) decide which of their children are visible.
function Canvas:UpdateChildVisibility(id)
	local node = Doc:Get(id)
	local def = ns.Elements[node.type]
	for index, childId in ipairs(node.children) do
		local holder = self.holders[childId]
		local child = Doc:Get(childId)
		if holder and child then
			holder:SetShown(def.ChildShown(self, node, index) and (child.shown or not self.preview))
		end
	end
end

-- A tab button or collapse button under the cursor. Tab buttons lie outside their
-- container, so the normal hit test would miss them. Returns id, kind, index.
function Canvas:HitControl()
	for i = #self.order, 1, -1 do
		local id = self.order[i]
		local holder = self.holders[id]
		if holder:IsVisible() and self:IsVisibleUnderCursor(id) then
			for index, tab in ipairs(holder.mfbTabButtons or {}) do
				if tab:IsShown() and tab:IsMouseOver() then
					return id, "tab", index
				end
			end
			if holder.mfbType == "Section" and holder.CollapseButton:IsMouseOver() then
				return id, "collapse"
			end
		end
	end
end

-- Selecting something on a hidden page or in a collapsed section makes it visible.
function Canvas:RevealSelection()
	local node = Doc:GetSelected()
	while node do
		local parent = Doc:Get(node.parent)
		if parent and parent.type == "Tabs" then
			local index = tIndexOf(parent.children, node.id)
			if index and index ~= parent.props.activeTab then
				Doc:Set(parent.id, "activeTab", index, true)
			end
		elseif parent and parent.type == "Section" and parent.props.collapsed then
			Doc:Set(parent.id, "collapsed", false, true)
		end
		node = parent
	end
end

function Canvas:RebuildGrid()
	for _, line in ipairs(self.gridLines) do
		line:Hide()
	end
	local settings = ns.db.settings
	if not settings.showGrid or settings.gridSize <= 0 then return end

	local width, height = self.content:GetSize()
	local step = settings.gridSize
	while width / step > 160 do
		step = step * 2
	end

	local count = 0
	local function AddLine(vertical, offset, major)
		count = count + 1
		local line = self.gridLines[count]
		if not line then
			line = self.gridFrame:CreateTexture(nil, "BACKGROUND")
			self.gridLines[count] = line
		end
		line:ClearAllPoints()
		line.vertical = vertical
		if vertical then
			line:SetPoint("TOP", self.gridFrame, "TOP", offset, 0)
			line:SetPoint("BOTTOM", self.gridFrame, "BOTTOM", offset, 0)
		else
			line:SetPoint("LEFT", self.gridFrame, "LEFT", 0, offset)
			line:SetPoint("RIGHT", self.gridFrame, "RIGHT", 0, offset)
		end
		line:SetColorTexture(1, 1, 1, major and 0.2 or 0.05)
		line:Show()
	end
	-- Lines start at the center so CENTER-anchored elements line up with the grid.
	for i = 0, math.floor(width / 2 / step) do
		AddLine(true, i * step, i == 0)
		if i > 0 then AddLine(true, -i * step) end
	end
	for i = 0, math.floor(height / 2 / step) do
		AddLine(false, i * step, i == 0)
		if i > 0 then AddLine(false, -i * step) end
	end
	self:UpdateLineThickness()
end

function Canvas:UpdateLineThickness()
	local thickness = 1 / self.zoom
	for _, line in ipairs(self.gridLines) do
		if line:IsShown() then
			if line.vertical then
				line:SetWidth(thickness)
			else
				line:SetHeight(thickness)
			end
		end
	end
	W.SetOutlineThickness(self.content, thickness)
end

---------------------------------------------------------------------------
-- Zoom & pan
---------------------------------------------------------------------------

function Canvas:UpdateContentPoint()
	self.content:ClearAllPoints()
	-- Offsets of a scaled frame are in its own units, the pan is stored in canvas units.
	self.content:SetPoint("CENTER", self.clip, "CENTER", self.panX / self.zoom, self.panY / self.zoom)
end

function Canvas:SetZoom(zoom, aroundCursor)
	zoom = Clamp(zoom, ZOOM_MIN, ZOOM_MAX)
	if aroundCursor then
		local x, y = GetCursorPosition()
		local scale = self.clip:GetEffectiveScale()
		local centerX, centerY = self.clip:GetCenter()
		local mx, my = x / scale - centerX, y / scale - centerY
		-- Keep the design point under the cursor in place.
		local ux, uy = (mx - self.panX) / self.zoom, (my - self.panY) / self.zoom
		self.panX, self.panY = mx - ux * zoom, my - uy * zoom
	end
	self.zoom = zoom
	self.content:SetScale(zoom)
	self:UpdateContentPoint()
	self:UpdateLineThickness()
	ns.Fire("ZOOM_CHANGED", zoom)
end

function Canvas:FitZoom()
	local width, height = self.clip:GetSize()
	local contentWidth, contentHeight = self.content:GetSize()
	if not width or width <= 0 or contentWidth <= 0 then return end
	self.panX, self.panY = 0, 0
	self:SetZoom(math.min((width - 24) / contentWidth, (height - 24) / contentHeight))
end

---------------------------------------------------------------------------
-- Geometry helpers
---------------------------------------------------------------------------

function Canvas:CursorInContent()
	local x, y = GetCursorPosition()
	local scale = self.content:GetEffectiveScale()
	return x / scale, y / scale
end

-- Topmost element under the cursor. containersOnly limits the result to drop targets,
-- excludeId skips an element and its descendants (used while dragging it).
function Canvas:HitTest(containersOnly, excludeId)
	for i = #self.order, 1, -1 do
		local id = self.order[i]
		local holder = self.holders[id]
		if holder:IsVisible() and holder:IsMouseOver()
			and (not containersOnly or ns.Elements[holder.mfbType].container)
			and not (excludeId and (id == excludeId or Doc:IsAncestor(excludeId, id)))
			and self:IsVisibleUnderCursor(id) then
			return id
		end
	end
end

-- Ctrl+wheel scrolls the innermost scroll frame under the cursor while editing.
function Canvas:ScrollUnderCursor(delta)
	local node = Doc:Get(self:HitTest())
	while node and not ns.Elements[node.type].ScrollRange do
		node = Doc:Get(node.parent)
	end
	if not node then return false end
	local range = ns.Elements[node.type].ScrollRange(node)
	local offset = Clamp(node.props.editorScroll - delta * 20, 0, range)
	Doc:Set(node.id, "editorScroll", offset, true)
	return true
end

-- The frame an anchor is relative to: another element, or the parent (a scroll frame's content).
function Canvas:AnchorFrame(node, target, parentId)
	local resolved = Doc:ResolveAnchorTarget(node, target)
	if resolved and self.holders[resolved] then
		return self.holders[resolved]
	end
	if parentId == nil then parentId = node.parent end
	return self:ChildParent(parentId)
end

-- Offsets that keep an element where it currently is on screen for the given anchor
-- points and relative frame. Returns nil when the layout isn't resolved yet.
function Canvas:OffsetsToFrame(id, point, relPoint, frame)
	local holder = self.holders[id]
	if not holder or not frame then return end
	local left, bottom, width, height = holder:GetRect()
	local frameLeft, frameBottom, frameWidth, frameHeight = frame:GetRect()
	if not left or not frameLeft then return end
	local f, pf = ns.POINT_FACTORS[point], ns.POINT_FACTORS[relPoint]
	local x = left + f[1] * width - (frameLeft + pf[1] * frameWidth)
	local y = bottom + f[2] * height - (frameBottom + pf[2] * frameHeight)
	return ns.Round(x, 1), ns.Round(y, 1)
end

function Canvas:OffsetsFor(id, point, relPoint, parentId)
	return self:OffsetsToFrame(id, point, relPoint, self:ChildParent(parentId))
end

-- Moves an element to a new parent; anchors relative to the parent follow it without
-- moving the element, anchors to other elements are kept.
function Canvas:Reparent(id, parentId)
	local node = Doc:Get(id)
	if not node then return end
	local list = Doc.GetAnchors(node)
	for _, anchor in ipairs(list) do
		if anchor.target == 0 or anchor.target == parentId or not Doc:ResolveAnchorTarget(node, anchor.target) then
			anchor.target = 0
			local x, y = self:OffsetsFor(id, anchor.point, anchor.relPoint, parentId)
			anchor.x, anchor.y = x or anchor.x, y or anchor.y
		end
	end
	Doc:SetParent(id, parentId, Doc.AnchorFields(list))
end

-- Changes one field (point, target, relPoint) of anchor index without moving the element.
function Canvas:SetAnchorField(id, index, field, value)
	local node = Doc:Get(id)
	if not node then return end
	local list = Doc.GetAnchors(node)
	local anchor = list[index]
	if not anchor then return end
	anchor[field] = value
	local x, y = self:OffsetsToFrame(id, anchor.point, anchor.relPoint, self:AnchorFrame(node, anchor.target))
	anchor.x, anchor.y = x or anchor.x, y or anchor.y
	Doc:SetAnchors(id, list)
end

-- Kept for callers that only change the primary anchor points.
function Canvas:SetAnchor(id, point, relPoint)
	local node = Doc:Get(id)
	if not node then return end
	local list = Doc.GetAnchors(node)
	list[1].point, list[1].relPoint = point, relPoint
	local x, y = self:OffsetsToFrame(id, point, relPoint, self:AnchorFrame(node, list[1].target))
	list[1].x, list[1].y = x or list[1].x, y or list[1].y
	Doc:SetAnchors(id, list)
end

local OPPOSITE_POINTS = {
	TOPLEFT = "BOTTOMRIGHT", TOP = "BOTTOM", TOPRIGHT = "BOTTOMLEFT", LEFT = "RIGHT",
	RIGHT = "LEFT", BOTTOMLEFT = "TOPRIGHT", BOTTOM = "TOP", BOTTOMRIGHT = "TOPLEFT",
}

-- Adds an anchor that keeps the current position: the point opposite the first anchor if
-- free, otherwise the next unused point, relative to the same frame and point.
function Canvas:AddAnchor(id)
	local node = Doc:Get(id)
	if not node then return end
	local list = Doc.GetAnchors(node)
	local used = {}
	for _, anchor in ipairs(list) do
		used[anchor.point] = true
	end
	local point = OPPOSITE_POINTS[list[1].point]
	if not point or used[point] then
		point = nil
		for _, candidate in ipairs(ns.POINTS) do
			if not used[candidate] then
				point = candidate
				break
			end
		end
	end
	if not point then return end
	local target = list[1].target
	local x, y = self:OffsetsToFrame(id, point, point, self:AnchorFrame(node, target))
	table.insert(list, { point = point, target = target, relPoint = point, x = x or 0, y = y or 0 })
	Doc:SetAnchors(id, list)
end

function Canvas:RemoveAnchor(id, index)
	local node = Doc:Get(id)
	if not node or index < 2 then return end
	local list = Doc.GetAnchors(node)
	table.remove(list, index)
	Doc:SetAnchors(id, list)
end

-- Called before elements are deleted: anchors pointing into the removed set are turned
-- into anchors to the parent at the current position (part of the same undo step).
function Canvas:DetachAnchors(removed)
	for id, node in pairs(Doc.project.nodes) do
		if not removed[id] then
			local list = Doc.GetAnchors(node)
			local changed = false
			for _, anchor in ipairs(list) do
				if anchor.target ~= 0 and removed[anchor.target] then
					local x, y = self:OffsetsFor(id, anchor.point, anchor.relPoint, node.parent)
					anchor.target, anchor.x, anchor.y = 0, x or anchor.x, y or anchor.y
					changed = true
				end
			end
			if changed then
				for field, value in pairs(Doc.AnchorFields(list)) do
					node[field] = value
				end
			end
		end
	end
end

---------------------------------------------------------------------------
-- Mouse interaction
---------------------------------------------------------------------------

function Canvas:OnMouseDown(button)
	if button == "MiddleButton" or (button == "LeftButton" and IsAltKeyDown()) then
		self:BeginPan(button)
	elseif button == "LeftButton" then
		local controlId, kind, tabIndex = self:HitControl()
		if controlId then
			Doc:Select(controlId)
			if kind == "tab" then
				Doc:Set(controlId, "activeTab", tabIndex, true)
			else
				Doc:Set(controlId, "collapsed", not Doc:Get(controlId).props.collapsed)
			end
			self:BeginMove(controlId)
			return
		end
		local id = self:HitTest()
		-- Shift drags the current selection even when other elements cover it.
		local selectedHolder = Doc.selected and self.holders[Doc.selected]
		if IsShiftKeyDown() and selectedHolder and selectedHolder:IsMouseOver() then
			id = Doc.selected
		end
		Doc:Select(id)
		if id then
			self:BeginMove(id)
		end
	elseif button == "RightButton" then
		local id = self:HitTest()
		Doc:Select(id)
		if id then
			self:ShowContextMenu(self.overlay, id)
		end
	end
end

local function StartDriver(self, mode, button, fields)
	fields.mode = mode
	fields.button = button or "LeftButton"
	self.drag = fields
	self.driver:SetScript("OnUpdate", function()
		self:UpdateDrag()
	end)
end

function Canvas:BeginMove(id)
	local node = Doc:Get(id)
	-- Elements that fill their parent can't move on their own; drag the parent instead.
	while node and node.fill do
		node = Doc:Get(node.parent)
	end
	if not node then return end
	id = node.id
	local cx, cy = self:CursorInContent()
	StartDriver(self, "move", "LeftButton", { id = id, cx = cx, cy = cy, x = node.x, y = node.y, anchors = Doc.GetAnchors(node) })
end

function Canvas:BeginResize(id, edges)
	local node = Doc:Get(id)
	if node.fill then return end
	local cx, cy = self:CursorInContent()
	-- Start from the real size: anchors on opposite edges may override node.w/h.
	local holder = self.holders[id]
	local w, h = holder and holder:GetSize()
	StartDriver(self, "resize", "LeftButton", {
		id = id, cx = cx, cy = cy, w = (w and w > 0) and w or node.w, h = (h and h > 0) and h or node.h,
		anchors = Doc.GetAnchors(node), edges = edges,
	})
end

function Canvas:BeginPan(button)
	local x, y = GetCursorPosition()
	local scale = self.clip:GetEffectiveScale()
	StartDriver(self, "pan", button, { cx = x / scale, cy = y / scale, x = self.panX, y = self.panY })
end

function Canvas:UpdateDrag()
	local drag = self.drag
	if not drag then
		self.driver:SetScript("OnUpdate", nil)
		return
	end
	if not IsMouseButtonDown(drag.button) then
		self:EndDrag(drag.button)
		return
	end

	if drag.mode == "pan" then
		local x, y = GetCursorPosition()
		local scale = self.clip:GetEffectiveScale()
		self.panX = drag.x + (x / scale - drag.cx)
		self.panY = drag.y + (y / scale - drag.cy)
		self:UpdateContentPoint()
		return
	end

	local cx, cy = self:CursorInContent()
	local dx, dy = cx - drag.cx, cy - drag.cy
	if not drag.moved then
		local threshold = 3 / self.zoom
		if math.abs(dx) < threshold and math.abs(dy) < threshold then return end
		drag.moved = true
		Doc:Checkpoint()
	end

	if drag.mode == "move" then
		-- The first anchor snaps; every other anchor moves by the same amount.
		local first = drag.anchors[1]
		local moveX, moveY = ns.Snap(first.x + dx) - first.x, ns.Snap(first.y + dy) - first.y
		local list = CopyTable(drag.anchors)
		for _, anchor in ipairs(list) do
			anchor.x, anchor.y = anchor.x + moveX, anchor.y + moveY
		end
		Doc:SetAnchors(drag.id, list, true)
		return
	end

	-- Resize: the edge opposite to the dragged one stays in place. Every anchor moves by
	-- the part of the size change that corresponds to its position on the element.
	local edges = drag.edges
	local w, h = drag.w, drag.h
	local growLeft, growRight, growTop, growBottom = 0, 0, 0, 0
	if edges.right then
		w = math.max(MIN_SIZE, ns.Snap(drag.w + dx))
		growRight = w - drag.w
	elseif edges.left then
		w = math.max(MIN_SIZE, ns.Snap(drag.w - dx))
		growLeft = w - drag.w
	end
	if edges.top then
		h = math.max(MIN_SIZE, ns.Snap(drag.h + dy))
		growTop = h - drag.h
	elseif edges.bottom then
		h = math.max(MIN_SIZE, ns.Snap(drag.h - dy))
		growBottom = h - drag.h
	end
	local list = CopyTable(drag.anchors)
	for _, anchor in ipairs(list) do
		local fx, fy = unpack(ns.POINT_FACTORS[anchor.point])
		anchor.x = anchor.x + fx * growRight - (1 - fx) * growLeft
		anchor.y = anchor.y + fy * growTop - (1 - fy) * growBottom
	end
	local fields = Doc.AnchorFields(list)
	fields.w, fields.h = w, h
	Doc:SetMany(drag.id, fields, true)
end

function Canvas:EndDrag(button)
	local drag = self.drag
	if not drag or (button and button ~= drag.button) then return end
	self.drag = nil
	self.driver:SetScript("OnUpdate", nil)
	-- Ctrl on release drops the moved element into the container under the cursor.
	if drag.mode == "move" and drag.moved and IsControlKeyDown() then
		local node = Doc:Get(drag.id)
		local target = self:HitTest(true, drag.id)
		if node and target ~= node.parent then
			self:Reparent(drag.id, target)
		end
	end
	self:UpdateHover()
end

function Canvas:UpdateHover()
	local hover = self.hover
	if self.preview or not self.overlay:IsMouseOver() then
		hover:Hide()
		return
	end
	local id, dropMode
	if self.drag and self.drag.mode == "move" and IsControlKeyDown() then
		id, dropMode = self:HitTest(true, self.drag.id), true
	elseif not self.drag then
		id = self:HitTest()
	end
	if not id or (id == Doc.selected and not dropMode) then
		hover:Hide()
		return
	end
	local color = dropMode and DROP or { 1, 1, 1 }
	for _, line in ipairs(hover.outline) do
		line:SetColorTexture(color[1], color[2], color[3], dropMode and 1 or 0.6)
	end
	W.SetOutlineThickness(hover, dropMode and 2 or 1)
	hover:ClearAllPoints()
	hover:SetAllPoints(self.holders[id])
	hover:Show()
end

function Canvas:UpdateSelection()
	local selection = self.selection
	if not selection then return end
	local node = Doc:GetSelected()
	local holder = node and self.holders[node.id]
	if not holder or self.preview then
		selection:Hide()
		return
	end
	selection:ClearAllPoints()
	selection:SetAllPoints(holder)
	-- The real size: fill and anchors on opposite edges override node.w/h.
	local width, height = holder:GetSize()
	selection.label:SetText(("%s  |cffaaaaaa%s x %s|r"):format(node.name,
		ns.LuaNum(ns.Round(width or 0, 1)), ns.LuaNum(ns.Round(height or 0, 1))))
	for _, grip in ipairs(selection.grips) do
		grip:SetShown(not node.fill)
	end
	selection:Show()
end

---------------------------------------------------------------------------
-- Adding elements
---------------------------------------------------------------------------

function Canvas:BeginPaletteDrag(elementType)
	local def = ns.Elements[elementType]
	local scale = self.content:GetEffectiveScale() / UIParent:GetEffectiveScale()
	self.paletteType = elementType
	self.ghost:SetSize(math.max(24, def.width * scale), math.max(16, def.height * scale))
	self.ghost.text:SetText(def.label)
	self.ghost:Show()
end

function Canvas:EndPaletteDrag()
	local elementType = self.paletteType
	self.paletteType = nil
	self.ghost:Hide()
	if elementType and not self.preview and self.clip:IsMouseOver() then
		self:DropNew(elementType)
	end
end

-- Adds an element centered on the cursor inside the container under it.
function Canvas:DropNew(elementType)
	local def = ns.Elements[elementType]
	local parentId = self:HitTest(true)
	local parent = self:ChildParent(parentId)
	local cx, cy = self:CursorInContent()
	local left, top = parent:GetLeft(), parent:GetTop()
	if not left then return end
	Doc:Add(elementType, parentId, {
		point = "TOPLEFT", relPoint = "TOPLEFT",
		x = ns.Snap(cx - left - def.width / 2),
		y = ns.Snap(cy - top + def.height / 2),
	})
end

-- Palette click: adds into the selected container (or next to the selection).
function Canvas:AddDefault(elementType)
	local selected = Doc:GetSelected()
	local parentId
	if selected and ns.Elements[selected.type].container then
		parentId = selected.id
	elseif selected then
		parentId = selected.parent
	end
	local offset = (#Doc:ChildList(parentId) % 10) * ns.db.settings.gridSize
	if parentId then
		Doc:Add(elementType, parentId, { point = "TOPLEFT", relPoint = "TOPLEFT", x = 16 + offset, y = -16 - offset })
	else
		Doc:Add(elementType, nil, { point = "CENTER", relPoint = "CENTER", x = offset, y = -offset })
	end
end

---------------------------------------------------------------------------
-- Context menu
---------------------------------------------------------------------------

function Canvas:ShowContextMenu(owner, id)
	local node = Doc:Get(id)
	if not node then return end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(node.name)
		root:CreateButton(L["Duplicate"], function() Doc:Duplicate(id) end)
		root:CreateButton(L["Copy"], function() Doc:Copy(id) end)
		local paste = root:CreateButton(L["Paste"], function() Doc:Paste() end)
		paste:SetEnabled(Doc:HasClipboard())
		if #node.children > 0 then
			root:CreateDivider()
			root:CreateButton(L["Expand all"], function() ns.Panels:SetSubtreeCollapsed(id, false) end)
			root:CreateButton(L["Collapse all"], function() ns.Panels:SetSubtreeCollapsed(id, true) end)
		end
		root:CreateDivider()
		root:CreateButton(L["Bring forward"], function() Doc:Reorder(id, 1) end)
		root:CreateButton(L["Send backward"], function() Doc:Reorder(id, -1) end)

		local move = root:CreateButton(L["Move into"])
		move:CreateRadio(L["(Screen)"], function() return node.parent == nil end, function() self:Reparent(id, nil) end)
		Doc:Walk(function(other, depth)
			if other.id ~= id and not Doc:IsAncestor(id, other.id) and ns.Elements[other.type].allowChildren then
				move:CreateRadio(("%s%s"):format(("  "):rep(depth), other.name),
					function() return node.parent == other.id end,
					function() self:Reparent(id, other.id) end)
			end
		end)
		root:CreateDivider()
		root:CreateButton("|cffff4040" .. L["Delete"] .. "|r", function() Doc:Remove(id) end)
	end)
end

---------------------------------------------------------------------------
-- Preview
---------------------------------------------------------------------------

function Canvas:SetPreview(enabled)
	if self.drag then
		self:EndDrag()
	end
	self.preview = enabled and true or false
	self.overlay:SetShown(not self.preview)
	self:Rebuild()
	ns.Fire("PREVIEW_CHANGED", self.preview)
end

local function ReportError(node, script, err, stack, kind)
	ns.Print(L["Script error in %s.%s: %s"], node.name, script.name, tostring(err))
	ns.Errors:Add({ kind = kind or "script", message = err, stack = stack or "", node = node, script = script.name })
end

function Canvas:CompileScript(node, script, code, E)
	local source = "local E = ...\nreturn function(" .. script.args .. ")\n" .. code .. "\nend"
	local chunk, err = loadstring(source, node.name .. "." .. script.name)
	if not chunk then
		ReportError(node, script, err)
		return
	end
	local ok, fn, stack = ns.Errors.Call(chunk, E)
	if not ok then
		ReportError(node, script, fn, stack)
		return
	end
	return fn
end

-- The E table scripts use to reach other elements, exactly like in the exported code.
function Canvas:BuildScriptEnv()
	local E = {}
	for id, holder in pairs(self.holders) do
		E[Doc:Get(id).name] = holder.region or holder
	end
	return E
end

-- Templates often need their OnLoad (Init, SetupSlider, ...) to look right, so Template
-- elements can opt in to running it while editing. Such widgets are not reused afterwards.
function Canvas:RunEditorOnLoads()
	local E
	for _, id in ipairs(self.order) do
		local node = Doc:Get(id)
		local code = node.scripts.OnLoad
		if node.type == "Template" and node.props.editorOnLoad and code and code ~= "" then
			E = E or self:BuildScriptEnv()
			local script = ns.Elements.Template.scripts[1]
			local fn = self:CompileScript(node, script, code, E)
			local holder = self.holders[id]
			holder.mfbTainted = true
			if fn then
				local ok, err, stack = ns.Errors.Call(fn, holder)
				if not ok then
					ReportError(node, script, err, stack, "editorOnLoad")
				end
			end
		end
	end
end

-- Compiles and attaches the scripts of all elements. Scripts see the other elements
-- through E.<Name>, exactly like in the exported code.
function Canvas:RunScripts()
	local E = self:BuildScriptEnv()
	local onLoad = {}
	for _, id in ipairs(self.order) do
		local node = Doc:Get(id)
		local holder = self.holders[id]
		for key in pairs(holder) do
			if type(key) == "string" and key:find("^mfbMethod") then
				holder[key] = nil
			end
		end
		-- Scripts use the same helpers as the exported code: E.Tabs1:SelectTab(2), E.Section1:SetCollapsed(true)
		if node.type == "Tabs" then
			holder.mfbActiveTab = node.props.activeTab
			holder.mfbSelectTab = function(index)
				holder.mfbActiveTab = index
				ns.Elements.Tabs.SelectVisual(holder, node.props, index)
				self:UpdateChildVisibility(id)
				if holder.mfbMethodOnTabSelected then
					holder.mfbMethodOnTabSelected(holder, index)
				end
			end
			holder.SelectTab = function(_, index) holder.mfbSelectTab(index) end
			self:UpdateChildVisibility(id)
		elseif node.type == "Section" then
			holder.mfbCollapsed = node.props.collapsed
			holder.SetCollapsed = function(_, collapsed)
				holder.mfbCollapsed = collapsed
				holder.CollapseButton:UpdateCollapsedState(collapsed)
				self:UpdateChildVisibility(id)
				if holder.mfbMethodOnToggle then
					holder.mfbMethodOnToggle(holder, collapsed)
				end
			end
			holder:HookScript("OnClick", function()
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				holder:SetCollapsed(not holder.mfbCollapsed)
			end)
			holder.mfbTainted = true
		end
		for _, script in ipairs(ns.Elements[node.type].scripts) do
			local code = node.scripts[script.name]
			local fn = code and code ~= "" and self:CompileScript(node, script, code, E)
			if fn then
				local function Run(...)
					local ok, err, stack = ns.Errors.Call(fn, ...)
					if not ok then
						ReportError(node, script, err, stack)
					end
				end
				if script.name == "OnLoad" then
					table.insert(onLoad, { Run, holder.region or holder })
				elseif script.method then
					holder["mfbMethod" .. script.name] = Run
				else
					holder:HookScript(script.name, function(...) Run(...) end)
					holder.mfbTainted = true
				end
			end
		end
	end
	for _, entry in ipairs(onLoad) do
		entry[1](entry[2])
	end
end

---------------------------------------------------------------------------
-- Document events
---------------------------------------------------------------------------

ns.On("PROJECT_CHANGED", function() Canvas:Rebuild() end)
ns.On("STRUCTURE_CHANGED", function() Canvas:Rebuild() end)
ns.On("SELECTION_CHANGED", function()
	if not Canvas.content then return end
	Canvas:RevealSelection()
	Canvas:UpdateSelection()
end)
ns.On("NODE_CHANGED", function(id, key)
	if not Canvas.content then return end
	local node, holder = Doc:Get(id), Canvas.holders[id]
	-- A different template needs a different widget.
	if node and holder and holder.mfbPoolKey ~= PoolKey(node) then
		Canvas:Rebuild()
		return
	end
	-- Editor OnLoads have to run again on a fresh widget.
	if node and node.type == "Template" and (key == "editorOnLoad" or (key == "scripts" and node.props.editorOnLoad)) then
		Canvas:Rebuild()
		return
	end
	if key ~= "name" and key ~= "scripts" then
		Canvas:ApplyNode(id)
	end
	Canvas:UpdateSelection()
end)
