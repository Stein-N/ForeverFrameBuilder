-- Forever Frame Builder
-- Document: projects, the element tree, selection, clipboard and undo/redo.
--
-- A project is { nodes = { [id] = node }, roots = { id, ... }, nextId = n }.
-- A node is { id, type, name, parent, children, point, relPoint, x, y, w, h, fill,
--             alpha, shown, strata, globalName, props = {}, scripts = {} }.
-- fill = true anchors the element to all edges of its parent instead of point/size.
-- Anchors: point/relTo/relPoint/x/y is the first anchor, node.anchors holds any further ones
-- as { point, target, relPoint, x, y }. relTo/target 0 means the parent, otherwise an element id.
--
-- Events fired through ns.Fire:
--   PROJECT_CHANGED              another project was loaded
--   STRUCTURE_CHANGED            nodes were added, removed, reparented or reordered
--   NODE_CHANGED (id, key)       a single node changed (key is nil for several fields)
--   SELECTION_CHANGED (id)
--   HISTORY_CHANGED              undo/redo availability changed

local _, ns = ...
local L = ns.L

local Doc = {}
ns.Doc = Doc

local MAX_UNDO = 80
local MERGE_WINDOW = 1.0

-- Keys stored directly on the node; everything else lives in node.props.
local NODE_KEYS = {
	name = true, globalName = true, point = true, relPoint = true,
	x = true, y = true, w = true, h = true, alpha = true, shown = true, strata = true, fill = true,
	relTo = true, anchors = true,
}
Doc.NODE_KEYS = NODE_KEYS

function Doc:Init()
	local db = ns.db
	self.undo, self.redo = {}, {}
	if not db.current or not db.projects[db.current] then
		db.current = next(db.projects)
	end
	if not db.current then
		self:NewProject(L["My Frame"])
	else
		self:SwitchProject(db.current)
	end
end

---------------------------------------------------------------------------
-- Projects
---------------------------------------------------------------------------

function Doc:ProjectNames()
	local names = {}
	for name in pairs(ns.db.projects) do
		table.insert(names, name)
	end
	table.sort(names, function(a, b) return a:lower() < b:lower() end)
	return names
end

function Doc:UniqueProjectName(base)
	base = strtrim(base or "")
	if base == "" then base = L["Project"] end
	local name, i = base, 2
	while ns.db.projects[name] do
		name = base .. " " .. i
		i = i + 1
	end
	return name
end

function Doc:CurrentName()
	return ns.db.current
end

function Doc:NewProject(name, data)
	name = self:UniqueProjectName(name)
	ns.db.projects[name] = data or { nodes = {}, roots = {}, nextId = 1 }
	self:SwitchProject(name)
	return name
end

function Doc:SwitchProject(name)
	if not ns.db.projects[name] then return end
	ns.db.current = name
	self.project = ns.db.projects[name]
	self:Normalize()
	self.selected = nil
	wipe(self.undo)
	wipe(self.redo)
	self.mergeKey = nil
	ns.Fire("PROJECT_CHANGED")
	ns.Fire("SELECTION_CHANGED", nil)
	ns.Fire("HISTORY_CHANGED")
end

function Doc:RenameProject(oldName, newName)
	newName = strtrim(newName or "")
	if newName == "" or newName == oldName or not ns.db.projects[oldName] then return end
	newName = self:UniqueProjectName(newName)
	ns.db.projects[newName] = ns.db.projects[oldName]
	ns.db.projects[oldName] = nil
	if ns.db.current == oldName then
		ns.db.current = newName
	end
	ns.Fire("PROJECT_CHANGED")
end

function Doc:DuplicateProject(name)
	local source = ns.db.projects[name]
	if source then
		self:NewProject(name, CopyTable(source))
	end
end

function Doc:DeleteProject(name)
	ns.db.projects[name] = nil
	if ns.db.current == name then
		local nextName = self:ProjectNames()[1]
		if nextName then
			self:SwitchProject(nextName)
		else
			self:NewProject(L["My Frame"])
		end
	else
		ns.Fire("PROJECT_CHANGED")
	end
end

-- Fills in fields that older or imported projects might be missing.
function Doc:Normalize()
	local project = self.project
	project.nodes = project.nodes or {}
	project.roots = project.roots or {}
	project.nextId = project.nextId or 1
	for id, node in pairs(project.nodes) do
		if not ns.Elements[node.type] then
			node.type = "Frame"
		end
		node.id = id
		node.children = node.children or {}
		node.point = node.point or "CENTER"
		node.relPoint = node.relPoint or node.point
		node.x, node.y = node.x or 0, node.y or 0
		node.relTo = tonumber(node.relTo) or 0
		local anchors = {}
		for _, anchor in ipairs(type(node.anchors) == "table" and node.anchors or {}) do
			if type(anchor) == "table" and ns.POINT_FACTORS[anchor.point] then
				table.insert(anchors, {
					point = anchor.point,
					target = tonumber(anchor.target) or 0,
					relPoint = ns.POINT_FACTORS[anchor.relPoint] and anchor.relPoint or anchor.point,
					x = tonumber(anchor.x) or 0,
					y = tonumber(anchor.y) or 0,
				})
			end
		end
		node.anchors = anchors
		local def = ns.Elements[node.type]
		node.w, node.h = node.w or def.width, node.h or def.height
		node.alpha = node.alpha or 1
		node.fill = node.fill and true or false
		if node.shown == nil then node.shown = true end
		node.strata = node.strata or ""
		node.globalName = node.globalName or ""
		node.scripts = node.scripts or {}
		node.props = node.props or {}
		for _, prop in ipairs(def.props) do
			if node.props[prop.key] == nil then
				node.props[prop.key] = type(prop.default) == "table" and CopyTable(prop.default) or prop.default
			end
		end
		if id >= project.nextId then
			project.nextId = id + 1
		end
	end
	-- Names double as Lua identifiers in scripts and the export, so they must be valid and unique.
	for id, node in pairs(project.nodes) do
		node.name = ns.SanitizeName(node.name)
		if node.name == "" or self:FindByName(node.name, id) then
			node.name = self:UniqueName(node.name ~= "" and node.name or node.type, id)
		end
	end
end

---------------------------------------------------------------------------
-- Tree access
---------------------------------------------------------------------------

function Doc:Get(id)
	return id and self.project.nodes[id]
end

function Doc:ChildList(parentId)
	if parentId then
		return self.project.nodes[parentId].children
	end
	return self.project.roots
end

-- Depth-first walk in draw order (parents before children, earlier siblings first).
function Doc:Walk(fn, parentId, depth)
	depth = depth or 0
	for _, id in ipairs(self:ChildList(parentId)) do
		local node = self.project.nodes[id]
		if node then
			fn(node, depth)
			self:Walk(fn, id, depth + 1)
		end
	end
end

function Doc:Count()
	local count = 0
	for _ in pairs(self.project.nodes) do
		count = count + 1
	end
	return count
end

function Doc:IsAncestor(ancestorId, id)
	local node = self:Get(id)
	while node and node.parent do
		if node.parent == ancestorId then
			return true
		end
		node = self:Get(node.parent)
	end
	return false
end

function Doc:FindByName(name, exceptId)
	for id, node in pairs(self.project.nodes) do
		if node.name == name and id ~= exceptId then
			return node
		end
	end
end

function Doc:UniqueName(base, exceptId)
	base = ns.SanitizeName(base)
	if base == "" then base = "Element" end
	base = base:gsub("%d+$", "")
	if base == "" then base = "Element" end
	local i = 1
	local name = base .. i
	while self:FindByName(name, exceptId) do
		i = i + 1
		name = base .. i
	end
	return name
end

---------------------------------------------------------------------------
-- History
---------------------------------------------------------------------------

local function Snapshot(project, selected)
	return {
		nodes = CopyTable(project.nodes),
		roots = CopyTable(project.roots),
		nextId = project.nextId,
		selected = selected,
	}
end

local function Restore(project, snap)
	project.nodes = snap.nodes
	project.roots = snap.roots
	project.nextId = snap.nextId
end

-- Stores the current state before a change. Changes sharing a mergeKey within a short
-- window (mouse wheel ticks, nudging with the arrow keys) collapse into one undo step.
function Doc:Checkpoint(mergeKey)
	local now = GetTime()
	if mergeKey and mergeKey == self.mergeKey and now - self.mergeTime < MERGE_WINDOW then
		self.mergeTime = now
		return
	end
	self.mergeKey, self.mergeTime = mergeKey, now
	table.insert(self.undo, Snapshot(self.project, self.selected))
	if #self.undo > MAX_UNDO then
		table.remove(self.undo, 1)
	end
	wipe(self.redo)
	ns.Fire("HISTORY_CHANGED")
end

function Doc:CanUndo() return #self.undo > 0 end
function Doc:CanRedo() return #self.redo > 0 end

local function StepHistory(self, from, to)
	local snap = table.remove(from)
	if not snap then return end
	table.insert(to, Snapshot(self.project, self.selected))
	Restore(self.project, snap)
	self.mergeKey = nil
	ns.Fire("STRUCTURE_CHANGED")
	self:Select(self:Get(snap.selected) and snap.selected or nil)
	ns.Fire("HISTORY_CHANGED")
end

function Doc:Undo() StepHistory(self, self.undo, self.redo) end
function Doc:Redo() StepHistory(self, self.redo, self.undo) end

---------------------------------------------------------------------------
-- Selection
---------------------------------------------------------------------------

function Doc:Select(id)
	if id and not self:Get(id) then id = nil end
	if self.selected == id then return end
	self.selected = id
	ns.Fire("SELECTION_CHANGED", id)
end

function Doc:GetSelected()
	return self:Get(self.selected)
end

---------------------------------------------------------------------------
-- Editing
---------------------------------------------------------------------------

function Doc:CanHaveChildren(id)
	if not id then return true end
	local node = self:Get(id)
	return node and ns.Elements[node.type].allowChildren
end

-- Inserts a node without history or events. props overrides single default properties.
local function CreateNode(self, elementType, parentId, fields, props, baseName)
	local def = ns.Elements[elementType]
	local project = self.project
	local id = project.nextId
	project.nextId = id + 1
	local node = {
		id = id,
		type = elementType,
		name = self:UniqueName(baseName or elementType),
		parent = parentId,
		children = {},
		point = "CENTER", relPoint = "CENTER", x = 0, y = 0,
		w = def.width, h = def.height, fill = false, relTo = 0, anchors = {},
		alpha = 1, shown = true, strata = "", globalName = "",
		props = ns.DefaultProps(elementType),
		scripts = {},
	}
	for key, value in pairs(fields or {}) do
		node[key] = value
	end
	for key, value in pairs(props or {}) do
		node.props[key] = value
	end
	project.nodes[id] = node
	table.insert(self:ChildList(parentId), id)
	-- Some elements come with children, e.g. one page per tab.
	if def.DefaultChildren then
		for _, child in ipairs(def.DefaultChildren(node.props)) do
			CreateNode(self, child.type, id, child.fields, child.props, child.name)
		end
	end
	return id
end

-- Creates a new element. fields may override position/size.
function Doc:Add(elementType, parentId, fields)
	if not ns.Elements[elementType] then return end
	if not self:CanHaveChildren(parentId) then
		parentId = nil
	end
	self:Checkpoint()
	local id = CreateNode(self, elementType, parentId, fields)
	ns.Fire("STRUCTURE_CHANGED")
	self:Select(id)
	return id
end

local function DeleteRecursive(nodes, id)
	local node = nodes[id]
	if not node then return end
	for _, childId in ipairs(node.children) do
		DeleteRecursive(nodes, childId)
	end
	nodes[id] = nil
end

function Doc:Remove(id)
	local node = self:Get(id)
	if not node then return end
	self:Checkpoint()
	-- Elements anchored to the removed subtree are re-anchored to their parent in place.
	local removed = { [id] = true }
	self:Walk(function(child) removed[child.id] = true end, id)
	if ns.Canvas and ns.Canvas.DetachAnchors then
		ns.Canvas:DetachAnchors(removed)
	end
	tDeleteItem(self:ChildList(node.parent), id)
	DeleteRecursive(self.project.nodes, id)
	if not self:Get(self.selected) then
		self.selected = nil
		ns.Fire("SELECTION_CHANGED", nil)
	end
	ns.Fire("STRUCTURE_CHANGED")
end

-- Copies a subtree into a self-contained table (ids are kept, remapped on paste).
local function CopySubtree(nodes, id, into)
	local node = nodes[id]
	into[id] = CopyTable(node)
	for _, childId in ipairs(node.children) do
		CopySubtree(nodes, childId, into)
	end
	return into
end

-- Inserts a copied subtree under parentId with fresh ids and unique names.
function Doc:InsertSubtree(clip, parentId, offset, afterId)
	local project = self.project
	local idMap = {}
	for oldId in pairs(clip.nodes) do
		idMap[oldId] = project.nextId
		project.nextId = project.nextId + 1
	end
	for oldId, source in pairs(clip.nodes) do
		local node = CopyTable(source)
		node.id = idMap[oldId]
		node.parent = idMap[source.parent]
		for i, childId in ipairs(node.children) do
			node.children[i] = idMap[childId]
		end
		-- Anchors to elements inside the copy follow the copy; others keep their target.
		node.relTo = idMap[node.relTo] or node.relTo
		for _, anchor in ipairs(node.anchors or {}) do
			anchor.target = idMap[anchor.target] or anchor.target
		end
		project.nodes[node.id] = node
	end
	-- Names are made unique afterwards so the copies don't collide with each other.
	for _, newId in pairs(idMap) do
		local node = project.nodes[newId]
		if self:FindByName(node.name, newId) then
			node.name = self:UniqueName(node.name, newId)
		end
		node.globalName = ""
	end
	local rootNode = project.nodes[idMap[clip.root]]
	rootNode.parent = parentId
	if offset then
		for field, value in pairs(Doc.ShiftAnchors(rootNode, offset, -offset)) do
			rootNode[field] = value
		end
	end
	local list = self:ChildList(parentId)
	local index = afterId and tIndexOf(list, afterId)
	table.insert(list, index and index + 1 or #list + 1, rootNode.id)
	return rootNode.id
end

function Doc:Duplicate(id)
	local node = self:Get(id)
	if not node then return end
	self:Checkpoint()
	local clip = { root = id, nodes = CopySubtree(self.project.nodes, id, {}) }
	local newId = self:InsertSubtree(clip, node.parent, ns.db.settings.gridSize * 2, id)
	ns.Fire("STRUCTURE_CHANGED")
	self:Select(newId)
end

function Doc:Copy(id)
	if not self:Get(id) then return end
	self.clipboard = { root = id, nodes = CopySubtree(self.project.nodes, id, {}) }
end

function Doc:HasClipboard()
	return self.clipboard ~= nil
end

-- Pastes into the selected element when it can hold children, otherwise next to it.
function Doc:Paste()
	if not self.clipboard then return end
	local target = self:GetSelected()
	local parentId, afterId
	if target and ns.Elements[target.type].container then
		parentId = target.id
	elseif target then
		parentId, afterId = target.parent, target.id
	end
	self:Checkpoint()
	local newId = self:InsertSubtree(self.clipboard, parentId, ns.db.settings.gridSize * 2, afterId)
	ns.Fire("STRUCTURE_CHANGED")
	self:Select(newId)
end

-- Moves an element up/down among its siblings (later siblings draw on top).
function Doc:Reorder(id, delta)
	local node = self:Get(id)
	if not node then return end
	local list = self:ChildList(node.parent)
	local index = tIndexOf(list, id)
	local target = index and index + delta
	if not target or target < 1 or target > #list then return end
	self:Checkpoint()
	table.remove(list, index)
	table.insert(list, target, id)
	ns.Fire("STRUCTURE_CHANGED")
end

-- Moves an element to a new parent. fields carries the recalculated position.
function Doc:SetParent(id, parentId, fields)
	local node = self:Get(id)
	if not node or node.parent == parentId then return end
	if parentId and (parentId == id or self:IsAncestor(id, parentId) or not self:CanHaveChildren(parentId)) then
		return
	end
	self:Checkpoint()
	tDeleteItem(self:ChildList(node.parent), id)
	node.parent = parentId
	table.insert(self:ChildList(parentId), id)
	if fields then
		for key, value in pairs(fields) do
			node[key] = value
		end
	end
	ns.Fire("STRUCTURE_CHANGED")
end

local function ValuesEqual(a, b)
	if type(a) == "table" and type(b) == "table" then
		return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
	end
	return a == b
end

-- Sets one field. Returns false when the value was rejected (e.g. an invalid name).
function Doc:Set(id, key, value, noCheckpoint, mergeKey)
	local node = self:Get(id)
	if not node then return false end
	if key == "name" then
		value = ns.SanitizeName(value)
		if value == "" or self:FindByName(value, id) then
			return false
		end
	elseif key == "globalName" then
		value = ns.SanitizeName(value)
	end
	local store = NODE_KEYS[key] and node or node.props
	if ValuesEqual(store[key], value) then return true end
	if not noCheckpoint then
		self:Checkpoint(mergeKey)
	end
	store[key] = type(value) == "table" and CopyTable(value) or value
	ns.Fire("NODE_CHANGED", id, key)
	return true
end

-- Sets several node fields at once (used while dragging/resizing).
function Doc:SetMany(id, fields, noCheckpoint, mergeKey)
	local node = self:Get(id)
	if not node then return end
	if not noCheckpoint then
		self:Checkpoint(mergeKey)
	end
	for key, value in pairs(fields) do
		local store = NODE_KEYS[key] and node or node.props
		store[key] = value
	end
	ns.Fire("NODE_CHANGED", id, nil)
end

function Doc:SetScript(id, scriptName, code)
	local node = self:Get(id)
	if not node then return end
	code = code and code:match("^%s*(.-)%s*$") or ""
	if (node.scripts[scriptName] or "") == code then return end
	self:Checkpoint()
	node.scripts[scriptName] = code ~= "" and code or nil
	ns.Fire("NODE_CHANGED", id, "scripts")
end

---------------------------------------------------------------------------
-- Anchors
---------------------------------------------------------------------------

-- All anchors of a node as a fresh list; entry 1 is the primary anchor.
function Doc.GetAnchors(node)
	local list = { { point = node.point, target = node.relTo or 0, relPoint = node.relPoint, x = node.x, y = node.y } }
	for _, anchor in ipairs(node.anchors or {}) do
		table.insert(list, CopyTable(anchor))
	end
	return list
end

-- Node fields for a list produced by GetAnchors (for SetMany / SetParent).
function Doc.AnchorFields(list)
	local primary = list[1]
	local extra = {}
	for i = 2, #list do
		table.insert(extra, CopyTable(list[i]))
	end
	return {
		point = primary.point, relTo = primary.target or 0, relPoint = primary.relPoint,
		x = primary.x, y = primary.y, anchors = extra,
	}
end

-- Moves every anchor by the same offset.
function Doc.ShiftAnchors(node, dx, dy)
	local list = Doc.GetAnchors(node)
	for _, anchor in ipairs(list) do
		anchor.x = anchor.x + dx
		anchor.y = anchor.y + dy
	end
	return Doc.AnchorFields(list)
end

function Doc:SetAnchors(id, list, noCheckpoint, mergeKey)
	self:SetMany(id, Doc.AnchorFields(list), noCheckpoint, mergeKey)
end

-- The element ids an element's position depends on (its anchor targets; 0 = parent).
local function Dependencies(self, node)
	local deps = {}
	if node.fill then
		if node.parent then table.insert(deps, node.parent) end
		return deps
	end
	for _, anchor in ipairs(Doc.GetAnchors(node)) do
		local target = anchor.target ~= 0 and self:Get(anchor.target) and anchor.target or node.parent
		if target then table.insert(deps, target) end
	end
	return deps
end

-- Whether id may be anchored to target without anchoring to itself or creating a loop.
function Doc:CanAnchorTo(id, target)
	if not target or target == 0 then return true end
	if target == id or not self:Get(target) then return false end
	local seen = {}
	local stack = { target }
	while #stack > 0 do
		local current = table.remove(stack)
		if current == id then return false end
		if not seen[current] then
			seen[current] = true
			local node = self:Get(current)
			if node then
				for _, dep in ipairs(Dependencies(self, node)) do
					table.insert(stack, dep)
				end
			end
		end
	end
	return true
end

-- The element an anchor actually uses: its target when valid, otherwise nil for the parent.
function Doc:ResolveAnchorTarget(node, target)
	if target and target ~= 0 and self:Get(target) and self:CanAnchorTo(node.id, target) then
		return target
	end
	return nil
end
