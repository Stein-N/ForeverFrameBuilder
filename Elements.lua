-- Forever Frame Builder
-- Elements: registry of every element type the builder can place.
--
-- Each definition describes how to create the widget on the canvas, how to apply its
-- properties, which properties/scripts the inspector shows and how to export it as Lua.
-- Region types (Texture, FontString) live inside a plain holder frame on the canvas so
-- they can be selected and dragged like frames; the export creates the bare region.

local _, ns = ...
local L = ns.L

ns.Elements = {}
ns.ElementOrder = {}

ns.POINTS = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }

-- Horizontal/vertical position of an anchor point inside a rect (0 = left/bottom, 1 = right/top).
ns.POINT_FACTORS = {
	TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
	LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
	BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}

ns.STRATAS = {
	{ value = "", label = L["(inherit)"] },
	"BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP",
}

local LAYERS = { "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY" }

local FONTS = {
	"GameFontNormal", "GameFontHighlight", "GameFontDisable",
	"GameFontNormalSmall", "GameFontHighlightSmall",
	"GameFontNormalLarge", "GameFontHighlightLarge",
	"GameFontNormalHuge", "GameFontHighlightHuge",
	"NumberFontNormal", "NumberFontNormalLarge",
	"SystemFont_Shadow_Med1", "SystemFont_Shadow_Large",
}

local OUTLINES = {
	{ value = "", label = L["(font default)"] },
	"NONE", "OUTLINE", "THICKOUTLINE", "MONOCHROME",
}

local BAR_TEXTURES = {
	{ value = "Interface\\TargetingFrame\\UI-StatusBar", label = "Blizzard" },
	{ value = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill", label = L["Raid"] },
	{ value = "Interface\\Buttons\\WHITE8X8", label = L["Flat"] },
	{ value = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar", label = L["Skill bar"] },
}

ns.BACKDROPS = {
	Solid = {
		bgFile = "Interface\\Buttons\\WHITE8X8",
		edgeFile = "Interface\\Buttons\\WHITE8X8",
		edgeSize = 1,
	},
	Tooltip = {
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	},
	Dialog = {
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	},
}

local BACKDROP_OPTIONS = {
	{ value = "None", label = L["None"] },
	{ value = "Solid", label = L["Solid"] },
	{ value = "Tooltip", label = L["Tooltip"] },
	{ value = "Dialog", label = L["Dialog"] },
}

-- Lua literal helpers shared with the exporter.
function ns.LuaNum(value)
	value = tonumber(value) or 0
	if value == math.floor(value) then
		return ("%d"):format(value)
	end
	return (("%.3f"):format(value):gsub("0+$", ""):gsub("%.$", ""))
end

function ns.LuaStr(value)
	return ("%q"):format(tostring(value or ""))
end

function ns.LuaColor(c)
	return ("%s, %s, %s, %s"):format(ns.LuaNum(c.r), ns.LuaNum(c.g), ns.LuaNum(c.b), ns.LuaNum(c.a or 1))
end

local function RGBA(c)
	return c.r, c.g, c.b, c.a or 1
end

local function Color(r, g, b, a)
	return { r = r, g = g, b = b, a = a or 1 }
end

local function Register(def)
	def.label = def.label or def.type
	def.props = def.props or {}
	def.scripts = def.scripts or {}
	table.insert(def.scripts, 1, { name = "OnLoad", args = "self" })
	def.allowChildren = not def.region
	ns.Elements[def.type] = def
	table.insert(ns.ElementOrder, def.type)
end

-- Preview helper: lets a frame be dragged around like the exported code would.
local function MakeMovable(frame)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:HookScript("OnDragStart", frame.StartMoving)
	frame:HookScript("OnDragStop", frame.StopMovingOrSizing)
	frame.mfbTainted = true
end

local function ExportMovable(out, v)
	out(v .. ":SetMovable(true)")
	out(v .. ":EnableMouse(true)")
	out(v .. ":RegisterForDrag(\"LeftButton\")")
	out(v .. ":SetScript(\"OnDragStart\", " .. v .. ".StartMoving)")
	out(v .. ":SetScript(\"OnDragStop\", " .. v .. ".StopMovingOrSizing)")
end

local function BackdropCode(name)
	local b = ns.BACKDROPS[name]
	local parts = {
		("bgFile = %s"):format(ns.LuaStr(b.bgFile)),
		("edgeFile = %s"):format(ns.LuaStr(b.edgeFile)),
	}
	if b.tile then
		table.insert(parts, "tile = true")
		table.insert(parts, "tileSize = " .. b.tileSize)
	end
	table.insert(parts, "edgeSize = " .. b.edgeSize)
	if b.insets then
		table.insert(parts, ("insets = { left = %d, right = %d, top = %d, bottom = %d }"):format(
			b.insets.left, b.insets.right, b.insets.top, b.insets.bottom))
	end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

-- Backdrop properties followed by the element's own ones.
local function WithBackdrop(default, props)
	local list = {
		{ key = "backdrop", label = L["Backdrop"], kind = "select", default = default, options = BACKDROP_OPTIONS },
		{ key = "bgColor", label = L["Background"], kind = "color", default = Color(0, 0, 0, 0.8) },
		{ key = "borderColor", label = L["Border"], kind = "color", default = Color(1, 1, 1, 1) },
	}
	for _, prop in ipairs(props) do
		table.insert(list, prop)
	end
	return list
end

local function ApplyBackdrop(f, p)
	if p.backdrop == "None" or not ns.BACKDROPS[p.backdrop] then
		f:ClearBackdrop()
	else
		f:SetBackdrop(ns.BACKDROPS[p.backdrop])
		f:SetBackdropColor(RGBA(p.bgColor))
		f:SetBackdropBorderColor(RGBA(p.borderColor))
	end
end

local function ExportBackdrop(out, v, p)
	if p.backdrop ~= "None" and ns.BACKDROPS[p.backdrop] then
		out(v .. ":SetBackdrop(" .. BackdropCode(p.backdrop) .. ")")
		out(v .. ":SetBackdropColor(" .. ns.LuaColor(p.bgColor) .. ")")
		out(v .. ":SetBackdropBorderColor(" .. ns.LuaColor(p.borderColor) .. ")")
	end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

Register({
	type = "Frame",
	label = L["Frame"],
	frameType = "Frame",
	template = "BackdropTemplate",
	width = 200, height = 150,
	container = true,
	props = WithBackdrop("Tooltip", {
		{ key = "movable", label = L["Movable"], kind = "bool", default = false },
		{ key = "enableMouse", label = L["Mouse enabled"], kind = "bool", default = false },
		{ key = "clipChildren", label = L["Clip children"], kind = "bool", default = false },
	}),
	clips = function(p) return p.clipChildren end,
	scripts = {
		{ name = "OnShow", args = "self" },
		{ name = "OnHide", args = "self" },
		{ name = "OnMouseDown", args = "self, button" },
		{ name = "OnUpdate", args = "self, elapsed" },
	},
	Create = function(parent)
		return CreateFrame("Frame", nil, parent, "BackdropTemplate")
	end,
	Apply = function(f, p, preview)
		ApplyBackdrop(f, p)
		f:SetClipsChildren(p.clipChildren)
		f:EnableMouse(preview and (p.enableMouse or p.movable) or false)
		if preview and p.movable then
			MakeMovable(f)
		end
	end,
	Export = function(out, v, p)
		ExportBackdrop(out, v, p)
		if p.clipChildren then
			out(v .. ":SetClipsChildren(true)")
		end
		if p.movable then
			ExportMovable(out, v)
		elseif p.enableMouse then
			out(v .. ":EnableMouse(true)")
		end
	end,
})

---------------------------------------------------------------------------
-- ScrollFrame
---------------------------------------------------------------------------

-- Children are anchored to the scroll child ("Content"), not to the scroll frame itself.
-- The scroll bar of ScrollFrameTemplate sits outside, to the right of the frame.
Register({
	type = "ScrollFrame",
	label = L["Scroll frame"],
	frameType = "ScrollFrame",
	template = "ScrollFrameTemplate",
	width = 200, height = 150,
	container = true,
	clips = true,
	childKey = "Content",
	props = {
		{ key = "contentWidth", label = L["Content width"], kind = "number", default = 0, min = 0, step = 1 },
		{ key = "contentHeight", label = L["Content height"], kind = "number", default = 400, min = 1, step = 10 },
		{ key = "scrollBar", label = L["Scroll bar"], kind = "bool", default = true },
		{ key = "editorScroll", label = L["Scroll position (editor)"], kind = "number", default = 0, min = 0, step = 10 },
	},
	scripts = {
		{ name = "OnVerticalScroll", args = "self, offset" },
	},
	Create = function(parent)
		local f = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate")
		f.Content = CreateFrame("Frame", nil, f)
		f.Content:SetSize(1, 1)
		f:SetScrollChild(f.Content)
		return f
	end,
	GetChildParent = function(f)
		return f.Content
	end,
	Apply = function(f, p)
		if f.ScrollBar then
			f.ScrollBar:SetAlpha(p.scrollBar and 1 or 0)
		end
	end,
	-- Runs after the size is set: the content width follows the frame unless it is fixed.
	Layout = function(f, node, preview)
		local p = node.props
		local width = node.fill and f:GetWidth() or node.w
		f.Content:SetSize(p.contentWidth > 0 and p.contentWidth or math.max(1, width), math.max(1, p.contentHeight))
		local range = math.max(0, p.contentHeight - node.h)
		f:SetVerticalScroll(preview and 0 or math.min(p.editorScroll, range))
	end,
	ScrollRange = function(node)
		return math.max(0, node.props.contentHeight - node.h)
	end,
	ExportTemplate = function(p)
		return p.scrollBar and "ScrollFrameTemplate" or nil
	end,
	Export = function(out, v, p, node)
		local width = p.contentWidth > 0 and p.contentWidth or node.w
		out(v .. ".Content = CreateFrame(\"Frame\", nil, " .. v .. ")")
		out(v .. ".Content:SetSize(" .. ns.LuaNum(width) .. ", " .. ns.LuaNum(p.contentHeight) .. ")")
		out(v .. ":SetScrollChild(" .. v .. ".Content)")
		if not p.scrollBar then
			out(v .. ":EnableMouseWheel(true)")
			out(v .. ":SetScript(\"OnMouseWheel\", function(self, delta)")
			out("\tlocal offset = self:GetVerticalScroll() - delta * 30")
			out("\tself:SetVerticalScroll(math.min(math.max(offset, 0), self:GetVerticalScrollRange()))")
			out("end)")
		end
	end,
})

---------------------------------------------------------------------------
-- Button
---------------------------------------------------------------------------

Register({
	type = "Button",
	label = L["Button"],
	frameType = "Button",
	template = "UIPanelButtonTemplate",
	width = 120, height = 22,
	props = {
		{ key = "text", label = L["Text"], kind = "string", default = "Button" },
		{ key = "enabled", label = L["Enabled"], kind = "bool", default = true },
	},
	scripts = {
		{ name = "OnClick", args = "self, button, down" },
		{ name = "OnEnter", args = "self" },
		{ name = "OnLeave", args = "self" },
	},
	Create = function(parent)
		return CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	end,
	Apply = function(f, p)
		f:SetText(p.text)
		f:SetEnabled(p.enabled)
	end,
	Export = function(out, v, p)
		out(v .. ":SetText(" .. ns.LuaStr(p.text) .. ")")
		if not p.enabled then
			out(v .. ":Disable()")
		end
	end,
})

---------------------------------------------------------------------------
-- CheckButton
---------------------------------------------------------------------------

Register({
	type = "CheckButton",
	label = L["Checkbox"],
	frameType = "CheckButton",
	template = "UICheckButtonTemplate",
	width = 24, height = 24,
	props = {
		{ key = "text", label = L["Text"], kind = "string", default = "Checkbox" },
		{ key = "checked", label = L["Checked"], kind = "bool", default = false },
	},
	scripts = {
		{ name = "OnClick", args = "self, button, down" },
	},
	Create = function(parent)
		return CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	end,
	Apply = function(f, p)
		local label = f.Text or f.text
		if label then
			label:SetText(p.text)
		end
		f:SetChecked(p.checked)
	end,
	Export = function(out, v, p)
		out(v .. ".Text:SetText(" .. ns.LuaStr(p.text) .. ")")
		if p.checked then
			out(v .. ":SetChecked(true)")
		end
	end,
})

---------------------------------------------------------------------------
-- EditBox
---------------------------------------------------------------------------

Register({
	type = "EditBox",
	label = L["Input box"],
	frameType = "EditBox",
	template = "InputBoxTemplate",
	width = 150, height = 20,
	props = {
		{ key = "text", label = L["Text"], kind = "string", default = "" },
		{ key = "maxLetters", label = L["Max letters"], kind = "number", default = 0, min = 0, step = 1 },
		{ key = "numeric", label = L["Numbers only"], kind = "bool", default = false },
	},
	scripts = {
		{ name = "OnEnterPressed", args = "self" },
		{ name = "OnEscapePressed", args = "self" },
		{ name = "OnTextChanged", args = "self, userInput" },
	},
	Create = function(parent)
		local f = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
		f:SetAutoFocus(false)
		return f
	end,
	Apply = function(f, p, preview)
		f:SetAutoFocus(false)
		f:ClearFocus()
		f:SetMaxLetters(p.maxLetters)
		f:SetNumeric(p.numeric)
		f:SetText(p.text)
		f:SetCursorPosition(0)
		f:EnableMouse(preview and true or false)
	end,
	Export = function(out, v, p)
		out(v .. ":SetAutoFocus(false)")
		if p.maxLetters > 0 then
			out(v .. ":SetMaxLetters(" .. ns.LuaNum(p.maxLetters) .. ")")
		end
		if p.numeric then
			out(v .. ":SetNumeric(true)")
		end
		if p.text ~= "" then
			out(v .. ":SetText(" .. ns.LuaStr(p.text) .. ")")
		end
	end,
})

---------------------------------------------------------------------------
-- Slider
---------------------------------------------------------------------------

Register({
	type = "Slider",
	label = L["Slider"],
	frameType = "Slider",
	template = "UISliderTemplate",
	width = 150, height = 17,
	props = {
		{ key = "minValue", label = L["Minimum"], kind = "number", default = 0 },
		{ key = "maxValue", label = L["Maximum"], kind = "number", default = 100 },
		{ key = "step", label = L["Step"], kind = "number", default = 1, min = 0 },
		{ key = "value", label = L["Value"], kind = "number", default = 50 },
	},
	scripts = {
		{ name = "OnValueChanged", args = "self, value, userInput" },
	},
	Create = function(parent)
		return CreateFrame("Slider", nil, parent, "UISliderTemplate")
	end,
	Apply = function(f, p)
		f:SetMinMaxValues(p.minValue, math.max(p.minValue, p.maxValue))
		f:SetValueStep(p.step > 0 and p.step or 1)
		f:SetObeyStepOnDrag(p.step > 0)
		f:SetValue(p.value)
	end,
	Export = function(out, v, p)
		out(v .. ":SetMinMaxValues(" .. ns.LuaNum(p.minValue) .. ", " .. ns.LuaNum(p.maxValue) .. ")")
		if p.step > 0 then
			out(v .. ":SetValueStep(" .. ns.LuaNum(p.step) .. ")")
			out(v .. ":SetObeyStepOnDrag(true)")
		end
		out(v .. ":SetValue(" .. ns.LuaNum(p.value) .. ")")
	end,
})

---------------------------------------------------------------------------
-- StatusBar
---------------------------------------------------------------------------

Register({
	type = "StatusBar",
	label = L["Status bar"],
	frameType = "StatusBar",
	width = 200, height = 20,
	container = true,
	props = {
		{ key = "texture", label = L["Texture"], kind = "select", default = BAR_TEXTURES[1].value, options = BAR_TEXTURES },
		{ key = "color", label = L["Bar color"], kind = "color", default = Color(0.1, 0.8, 0.1, 1) },
		{ key = "bgColor", label = L["Background"], kind = "color", default = Color(0, 0, 0, 0.5) },
		{ key = "minValue", label = L["Minimum"], kind = "number", default = 0 },
		{ key = "maxValue", label = L["Maximum"], kind = "number", default = 100 },
		{ key = "value", label = L["Value"], kind = "number", default = 60 },
		{ key = "orientation", label = L["Orientation"], kind = "select", default = "HORIZONTAL", options = { "HORIZONTAL", "VERTICAL" } },
		{ key = "reverseFill", label = L["Reverse fill"], kind = "bool", default = false },
	},
	scripts = {
		{ name = "OnValueChanged", args = "self, value" },
	},
	Create = function(parent)
		local f = CreateFrame("StatusBar", nil, parent)
		f.Background = f:CreateTexture(nil, "BACKGROUND")
		f.Background:SetAllPoints()
		return f
	end,
	Apply = function(f, p)
		f:SetStatusBarTexture(p.texture)
		f:SetStatusBarColor(RGBA(p.color))
		f.Background:SetColorTexture(RGBA(p.bgColor))
		f:SetOrientation(p.orientation)
		f:SetReverseFill(p.reverseFill)
		f:SetMinMaxValues(p.minValue, math.max(p.minValue, p.maxValue))
		f:SetValue(p.value)
	end,
	Export = function(out, v, p)
		out(v .. ":SetStatusBarTexture(" .. ns.LuaStr(p.texture) .. ")")
		out(v .. ":SetStatusBarColor(" .. ns.LuaColor(p.color) .. ")")
		out(v .. ".Background = " .. v .. ":CreateTexture(nil, \"BACKGROUND\")")
		out(v .. ".Background:SetAllPoints()")
		out(v .. ".Background:SetColorTexture(" .. ns.LuaColor(p.bgColor) .. ")")
		if p.orientation ~= "HORIZONTAL" then
			out(v .. ":SetOrientation(" .. ns.LuaStr(p.orientation) .. ")")
		end
		if p.reverseFill then
			out(v .. ":SetReverseFill(true)")
		end
		out(v .. ":SetMinMaxValues(" .. ns.LuaNum(p.minValue) .. ", " .. ns.LuaNum(p.maxValue) .. ")")
		out(v .. ":SetValue(" .. ns.LuaNum(p.value) .. ")")
	end,
})

---------------------------------------------------------------------------
-- Texture (region)
---------------------------------------------------------------------------

Register({
	type = "Texture",
	label = L["Texture"],
	region = true,
	width = 40, height = 40,
	props = {
		{ key = "file", label = L["File / ID"], kind = "string", default = "Interface\\Icons\\INV_Misc_QuestionMark" },
		{ key = "atlas", label = L["Atlas"], kind = "string", default = "" },
		{ key = "color", label = L["Color"], kind = "color", default = Color(1, 1, 1, 1) },
		{ key = "layer", label = L["Layer"], kind = "select", default = "ARTWORK", options = LAYERS },
		{ key = "cropIcon", label = L["Crop icon border"], kind = "bool", default = false },
		{ key = "desaturated", label = L["Desaturated"], kind = "bool", default = false },
	},
	Create = function(parent)
		local f = CreateFrame("Frame", nil, parent)
		f.region = f:CreateTexture(nil, "ARTWORK")
		f.region:SetAllPoints()
		return f
	end,
	Apply = function(f, p)
		local t = f.region
		t:SetDrawLayer(p.layer)
		if p.atlas ~= "" then
			t:SetAtlas(p.atlas)
		elseif p.file ~= "" then
			t:SetTexture(tonumber(p.file) or p.file)
		else
			t:SetColorTexture(1, 1, 1, 1)
		end
		if p.cropIcon then
			t:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		else
			t:SetTexCoord(0, 1, 0, 1)
		end
		t:SetVertexColor(RGBA(p.color))
		t:SetDesaturated(p.desaturated)
	end,
	ExportCreate = function(v, parentVar, p)
		return v .. " = " .. parentVar .. ":CreateTexture(nil, " .. ns.LuaStr(p.layer) .. ")"
	end,
	Export = function(out, v, p)
		if p.atlas ~= "" then
			out(v .. ":SetAtlas(" .. ns.LuaStr(p.atlas) .. ")")
		elseif p.file ~= "" then
			local id = tonumber(p.file)
			out(v .. ":SetTexture(" .. (id and ns.LuaNum(id) or ns.LuaStr(p.file)) .. ")")
		else
			out(v .. ":SetColorTexture(1, 1, 1, 1)")
		end
		if p.cropIcon then
			out(v .. ":SetTexCoord(0.07, 0.93, 0.07, 0.93)")
		end
		local c = p.color
		if c.r ~= 1 or c.g ~= 1 or c.b ~= 1 or (c.a or 1) ~= 1 then
			out(v .. ":SetVertexColor(" .. ns.LuaColor(c) .. ")")
		end
		if p.desaturated then
			out(v .. ":SetDesaturated(true)")
		end
	end,
})

---------------------------------------------------------------------------
-- FontString (region)
---------------------------------------------------------------------------

local function ResolveFont(name)
	local font = _G[name]
	if type(font) == "table" and font.GetFont then
		return font
	end
	return GameFontNormal
end

Register({
	type = "FontString",
	label = L["Text"],
	region = true,
	width = 120, height = 20,
	props = {
		{ key = "text", label = L["Text"], kind = "string", default = "Text" },
		{ key = "font", label = L["Font"], kind = "select", default = "GameFontNormal", options = FONTS },
		{ key = "fontSize", label = L["Font size"], kind = "number", default = 0, min = 0, step = 1 },
		{ key = "outline", label = L["Outline"], kind = "select", default = "", options = OUTLINES },
		{ key = "useColor", label = L["Custom color"], kind = "bool", default = false },
		{ key = "color", label = L["Color"], kind = "color", default = Color(1, 1, 1, 1) },
		{ key = "justifyH", label = L["Horizontal align"], kind = "select", default = "CENTER", options = { "LEFT", "CENTER", "RIGHT" } },
		{ key = "justifyV", label = L["Vertical align"], kind = "select", default = "MIDDLE", options = { "TOP", "MIDDLE", "BOTTOM" } },
		{ key = "wordWrap", label = L["Word wrap"], kind = "bool", default = true },
		{ key = "layer", label = L["Layer"], kind = "select", default = "OVERLAY", options = LAYERS },
	},
	Create = function(parent)
		local f = CreateFrame("Frame", nil, parent)
		f.region = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		f.region:SetAllPoints()
		return f
	end,
	Apply = function(f, p)
		local fs = f.region
		local fontObject = ResolveFont(p.font)
		fs:SetFontObject(fontObject)
		if p.fontSize > 0 or p.outline ~= "" then
			local path, size, flags = fontObject:GetFont()
			local outline = p.outline ~= "" and p.outline or flags
			if outline == "NONE" then outline = "" end
			fs:SetFont(path, p.fontSize > 0 and p.fontSize or size, outline)
		end
		if p.useColor then
			fs:SetTextColor(RGBA(p.color))
		else
			fs:SetTextColor(fontObject:GetTextColor())
		end
		fs:SetDrawLayer(p.layer)
		fs:SetJustifyH(p.justifyH)
		fs:SetJustifyV(p.justifyV)
		fs:SetWordWrap(p.wordWrap)
		fs:SetText(p.text)
	end,
	ExportCreate = function(v, parentVar, p)
		return v .. " = " .. parentVar .. ":CreateFontString(nil, " .. ns.LuaStr(p.layer) .. ", " .. ns.LuaStr(p.font) .. ")"
	end,
	Export = function(out, v, p)
		if p.fontSize > 0 or p.outline ~= "" then
			out("do")
			out("\tlocal path, size, flags = " .. p.font .. ":GetFont()")
			local size = p.fontSize > 0 and ns.LuaNum(p.fontSize) or "size"
			local outline = p.outline == "" and "flags" or (p.outline == "NONE" and "\"\"" or ns.LuaStr(p.outline))
			out("\t" .. v .. ":SetFont(path, " .. size .. ", " .. outline .. ")")
			out("end")
		end
		if p.useColor then
			out(v .. ":SetTextColor(" .. ns.LuaColor(p.color) .. ")")
		end
		if p.justifyH ~= "CENTER" then
			out(v .. ":SetJustifyH(" .. ns.LuaStr(p.justifyH) .. ")")
		end
		if p.justifyV ~= "MIDDLE" then
			out(v .. ":SetJustifyV(" .. ns.LuaStr(p.justifyV) .. ")")
		end
		if not p.wordWrap then
			out(v .. ":SetWordWrap(false)")
		end
		out(v .. ":SetText(" .. ns.LuaStr(p.text) .. ")")
	end,
})

---------------------------------------------------------------------------
-- Model
---------------------------------------------------------------------------

Register({
	type = "Model",
	label = L["3D model"],
	frameType = "PlayerModel",
	width = 150, height = 200,
	props = {
		{ key = "unit", label = L["Unit"], kind = "string", default = "player" },
		{ key = "displayId", label = L["Display ID"], kind = "number", default = 0, min = 0, step = 1 },
		{ key = "facing", label = L["Facing (°)"], kind = "number", default = 0, step = 15 },
	},
	Create = function(parent)
		return CreateFrame("PlayerModel", nil, parent)
	end,
	Apply = function(f, p)
		if p.displayId > 0 then
			f:SetDisplayInfo(p.displayId)
		else
			f:SetUnit(p.unit ~= "" and p.unit or "player")
		end
		f:SetFacing(math.rad(p.facing))
	end,
	Export = function(out, v, p)
		if p.displayId > 0 then
			out(v .. ":SetDisplayInfo(" .. ns.LuaNum(p.displayId) .. ")")
		else
			out(v .. ":SetUnit(" .. ns.LuaStr(p.unit ~= "" and p.unit or "player") .. ")")
		end
		if p.facing ~= 0 then
			out(v .. ":SetFacing(math.rad(" .. ns.LuaNum(p.facing) .. "))")
		end
	end,
})

---------------------------------------------------------------------------
-- Window (Blizzard frame templates)
---------------------------------------------------------------------------

-- What each window template offers: how the title is set, the close button key,
-- whether it has a portrait and a button bar (ButtonFrameTemplate only).
local WINDOW_STYLES = {
	ButtonFrameTemplate = { title = "SetTitle", close = "CloseButton", portrait = true, buttonBar = true },
	PortraitFrameTemplate = { title = "SetTitle", close = "CloseButton", portrait = true },
	BasicFrameTemplateWithInset = { title = "TitleText", close = "CloseButton" },
	BasicFrameTemplate = { title = "TitleText", close = "CloseButton" },
	DefaultPanelTemplate = { title = "SetTitle" },
	DefaultPanelFlatTemplate = { title = "SetTitle" },
	UIPanelDialogTemplate = { title = "Title" },
	SimplePanelTemplate = {},
	InsetFrameTemplate = {},
	DialogBorderTemplate = {},
	DialogBorderDarkTemplate = {},
}

local WINDOW_OPTIONS = {
	{ value = "ButtonFrameTemplate", label = L["Panel (ButtonFrame)"] },
	{ value = "PortraitFrameTemplate", label = L["Portrait frame"] },
	{ value = "BasicFrameTemplateWithInset", label = L["Basic frame with inset"] },
	{ value = "BasicFrameTemplate", label = L["Basic frame"] },
	{ value = "DefaultPanelTemplate", label = L["Default panel"] },
	{ value = "DefaultPanelFlatTemplate", label = L["Flat panel"] },
	{ value = "UIPanelDialogTemplate", label = L["Dialog (gear manager)"] },
	{ value = "SimplePanelTemplate", label = L["Simple panel"] },
	{ value = "InsetFrameTemplate", label = L["Inset"] },
	{ value = "DialogBorderTemplate", label = L["Dialog border"] },
	{ value = "DialogBorderDarkTemplate", label = L["Dialog border (dark)"] },
}

Register({
	type = "Window",
	label = L["Window"],
	frameType = "Frame",
	width = 360, height = 300,
	container = true,
	props = {
		{ key = "style", label = L["Style"], kind = "select", default = "ButtonFrameTemplate", options = WINDOW_OPTIONS },
		{ key = "title", label = L["Title"], kind = "string", default = "My Window" },
		{ key = "closeButton", label = L["Close button"], kind = "bool", default = true },
		{ key = "portrait", label = L["Portrait"], kind = "bool", default = false },
		{ key = "portraitIcon", label = L["Portrait icon"], kind = "string", default = "Interface\\Icons\\INV_Misc_Book_09" },
		{ key = "buttonBar", label = L["Button bar"], kind = "bool", default = false },
		{ key = "movable", label = L["Movable"], kind = "bool", default = true },
	},
	scripts = {
		{ name = "OnShow", args = "self" },
		{ name = "OnHide", args = "self" },
	},
	PoolKey = function(p)
		return "Window:" .. p.style
	end,
	ExportTemplate = function(p)
		return p.style
	end,
	Create = function(parent, p)
		return CreateFrame("Frame", nil, parent, p.style)
	end,
	Apply = function(f, p, preview)
		local style = WINDOW_STYLES[p.style] or {}
		if style.title == "SetTitle" and f.SetTitle then
			f:SetTitle(p.title)
		elseif style.title and f[style.title] then
			f[style.title]:SetText(p.title)
		end
		if style.close and f[style.close] then
			f[style.close]:SetShown(p.closeButton)
		end
		if style.portrait then
			if p.portrait then
				ButtonFrameTemplate_ShowPortrait(f)
				f:SetPortraitToAsset(tonumber(p.portraitIcon) or p.portraitIcon)
			else
				ButtonFrameTemplate_HidePortrait(f)
			end
		end
		if style.buttonBar then
			if p.buttonBar then
				ButtonFrameTemplate_ShowButtonBar(f)
			else
				ButtonFrameTemplate_HideButtonBar(f)
			end
		end
		f:EnableMouse(preview and p.movable or false)
		if preview and p.movable then
			MakeMovable(f)
		end
	end,
	Export = function(out, v, p)
		local style = WINDOW_STYLES[p.style] or {}
		if style.title == "SetTitle" then
			out(v .. ":SetTitle(" .. ns.LuaStr(p.title) .. ")")
		elseif style.title then
			out(v .. "." .. style.title .. ":SetText(" .. ns.LuaStr(p.title) .. ")")
		end
		if style.close and not p.closeButton then
			out(v .. "." .. style.close .. ":Hide()")
		end
		if style.portrait then
			if p.portrait then
				local icon = tonumber(p.portraitIcon)
				out("ButtonFrameTemplate_ShowPortrait(" .. v .. ")")
				out(v .. ":SetPortraitToAsset(" .. (icon and ns.LuaNum(icon) or ns.LuaStr(p.portraitIcon)) .. ")")
			else
				out("ButtonFrameTemplate_HidePortrait(" .. v .. ")")
			end
		end
		if style.buttonBar and not p.buttonBar then
			out("ButtonFrameTemplate_HideButtonBar(" .. v .. ")")
		end
		if p.movable then
			ExportMovable(out, v)
		end
	end,
})

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------

-- A tab container: the tab buttons sit outside its top or bottom edge and each direct
-- child is one page (child 1 = tab 1, ...). Only the page of the active tab is shown.
local TAB_STYLES = {
	BOTTOM = {
		template = "PanelTabButtonTemplate",
		first = { "TOPLEFT", "BOTTOMLEFT", 12, 2 },
		next = { "TOPLEFT", "TOPRIGHT", 1, 0 },
	},
	TOP = {
		template = "PanelTopTabButtonTemplate",
		first = { "BOTTOMLEFT", "TOPLEFT", 12, -2 },
		next = { "BOTTOMLEFT", "BOTTOMRIGHT", 1, 0 },
	},
	-- Icon tabs stacked along the right edge, as in the Forever collections journal.
	-- The tab height already excludes the art's transparent padding, so they stack without gaps.
	SIDE = {
		template = "LargeSideTabButtonTemplate",
		widget = "Frame",
		side = true,
		first = { "TOPLEFT", "TOPRIGHT", 0, -36 },
		next = { "TOPLEFT", "BOTTOMLEFT", 0, 0 },
	},
}

-- Marks the active tab button (panel tabs through PanelTemplates, side tabs are checked).
local function SelectTabVisual(f, p, index)
	local style = TAB_STYLES[p.style] or TAB_STYLES.BOTTOM
	if style.side then
		for i, tab in ipairs(f.mfbTabButtons) do
			tab:SetChecked(i == index)
		end
	elseif (f.numTabs or 0) > 0 then
		PanelTemplates_SetTab(f, index)
	end
end

function ns.SplitTabs(text)
	local list = {}
	for part in tostring(text or ""):gmatch("[^;]+") do
		part = strtrim(part)
		if part ~= "" then
			table.insert(list, part)
		end
	end
	return list
end

Register({
	type = "Tabs",
	label = L["Tabs"],
	frameType = "Frame",
	template = "BackdropTemplate",
	width = 360, height = 260,
	container = true,
	props = WithBackdrop("Tooltip", {
		{ key = "tabs", label = L["Tabs (a;b;c)"], kind = "string", default = "Tab 1;Tab 2" },
		{ key = "style", label = L["Tab position"], kind = "select", default = "BOTTOM",
			options = {
				{ value = "BOTTOM", label = L["Bottom"] },
				{ value = "TOP", label = L["Top"] },
				{ value = "SIDE", label = L["Side (icons)"] },
			} },
		{ key = "icons", label = L["Icons (a;b;c)"], kind = "string",
			default = "Interface\\Icons\\INV_Misc_Book_09;Interface\\Icons\\INV_Misc_Gear_01" },
		{ key = "activeTab", label = L["Active tab"], kind = "number", default = 1, min = 1, step = 1 },
	}),
	scripts = {
		{ name = "OnTabSelected", args = "self, index", method = true },
	},
	-- New tab containers start with one empty page per tab.
	DefaultChildren = function(props)
		local children = {}
		for _ in ipairs(ns.SplitTabs(props.tabs)) do
			table.insert(children, { type = "Frame", name = "Page", fields = { fill = true }, props = { backdrop = "None" } })
		end
		return children
	end,
	PoolKey = function(p)
		return "Tabs:" .. p.style
	end,
	Create = function(parent)
		local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
		f.mfbTabButtons = {}
		return f
	end,
	Apply = function(f, p)
		ApplyBackdrop(f, p)
		local style = TAB_STYLES[p.style] or TAB_STYLES.BOTTOM
		local labels = ns.SplitTabs(p.tabs)
		local icons = ns.SplitTabs(p.icons)
		for i, label in ipairs(labels) do
			local tab = f.mfbTabButtons[i]
			if not tab then
				tab = CreateFrame(style.widget or "Button", nil, f, style.template)
				if style.side then
					-- Side tabs are frames: the mixin plays the sound and reports clicks here.
					tab:SetCustomOnMouseUpHandler(function(self, button, upInside)
						local owner = self:GetParent()
						if button == "LeftButton" and upInside and owner.mfbSelectTab then
							owner.mfbSelectTab(self:GetID())
						end
					end)
				else
					tab:SetScript("OnClick", function(self)
						local owner = self:GetParent()
						if owner.mfbSelectTab then
							PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
							owner.mfbSelectTab(self:GetID())
						end
					end)
				end
				f.mfbTabButtons[i] = tab
			end
			tab:SetID(i)
			if style.side then
				local icon = icons[i] or "Interface\\Icons\\INV_Misc_QuestionMark"
				tab.Icon:SetTexture(tonumber(icon) or icon)
				tab:SetFillToInterior(true)
				tab.tooltipText = label
			else
				tab:SetText(label)
			end
			tab:ClearAllPoints()
			local anchor = i == 1 and style.first or style.next
			tab:SetPoint(anchor[1], i == 1 and f or f.mfbTabButtons[i - 1], anchor[2], anchor[3], anchor[4])
			tab:Show()
			if not style.side then
				PanelTemplates_TabResize(tab, 0)
			end
		end
		for i = #labels + 1, #f.mfbTabButtons do
			f.mfbTabButtons[i]:Hide()
		end
		-- PanelTemplates looks the buttons up in f.Tabs.
		f.Tabs = f.mfbTabButtons
		f.numTabs = nil
		if not style.side then
			PanelTemplates_SetNumTabs(f, #labels)
		end
		if #labels > 0 then
			SelectTabVisual(f, p, Clamp(p.activeTab, 1, #labels))
		end
	end,
	SelectVisual = SelectTabVisual,
	ChildShown = function(canvas, node, index)
		return index == canvas:ActiveTab(node.id)
	end,
	Export = function(out, v, p, node)
		local style = TAB_STYLES[p.style] or TAB_STYLES.BOTTOM
		local labels = ns.SplitTabs(p.tabs)
		local quoted = {}
		for i, label in ipairs(labels) do
			quoted[i] = ns.LuaStr(label)
		end
		ExportBackdrop(out, v, p)
		if style.side then
			local icons = ns.SplitTabs(p.icons)
			local quotedIcons = {}
			for i = 1, #labels do
				local icon = icons[i] or "Interface\\Icons\\INV_Misc_QuestionMark"
				quotedIcons[i] = tonumber(icon) and ns.LuaNum(icon) or ns.LuaStr(icon)
			end
			out("local " .. node.name .. "Icons = { " .. table.concat(quotedIcons, ", ") .. " }")
		end
		out(v .. ".Tabs = {}")
		out("for i, text in ipairs({ " .. table.concat(quoted, ", ") .. " }) do")
		out("\tlocal tab = CreateFrame(" .. ns.LuaStr(style.widget or "Button") .. ", nil, " .. v .. ", " .. ns.LuaStr(style.template) .. ")")
		out("\t" .. v .. ".Tabs[i] = tab")
		out("\ttab:SetID(i)")
		if style.side then
			out("\ttab.Icon:SetTexture(" .. node.name .. "Icons[i])")
			out("\ttab:SetFillToInterior(true)")
			out("\ttab.tooltipText = text")
		else
			out("\ttab:SetText(text)")
		end
		out("\tif i == 1 then")
		out(("\t\ttab:SetPoint(%s, %s, %s, %s, %s)"):format(ns.LuaStr(style.first[1]), v, ns.LuaStr(style.first[2]),
			ns.LuaNum(style.first[3]), ns.LuaNum(style.first[4])))
		out("\telse")
		out(("\t\ttab:SetPoint(%s, %s.Tabs[i - 1], %s, %s, %s)"):format(ns.LuaStr(style.next[1]), v, ns.LuaStr(style.next[2]),
			ns.LuaNum(style.next[3]), ns.LuaNum(style.next[4])))
		out("\tend")
		if style.side then
			out("\ttab:SetCustomOnMouseUpHandler(function(self, button, upInside)")
			out("\t\tif button == \"LeftButton\" and upInside then")
			out("\t\t\t" .. v .. ":SelectTab(self:GetID())")
			out("\t\tend")
			out("\tend)")
		else
			out("\tPanelTemplates_TabResize(tab, 0)")
			out("\ttab:SetScript(\"OnClick\", function(self)")
			out("\t\tPlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)")
			out("\t\t" .. v .. ":SelectTab(self:GetID())")
			out("\tend)")
		end
		out("end")
		if not style.side then
			out("PanelTemplates_SetNumTabs(" .. v .. ", " .. #labels .. ")")
		end
		out("-- Shows the page of the given tab; calls self:OnTabSelected(index) when defined.")
		out("function " .. v .. ":SelectTab(index)")
		if style.side then
			out("\tfor i, tab in ipairs(self.Tabs) do")
			out("\t\ttab:SetChecked(i == index)")
			out("\tend")
		else
			out("\tPanelTemplates_SetTab(self, index)")
		end
		out("\tfor i, page in ipairs(self.Pages or {}) do")
		out("\t\tpage:SetShown(i == index)")
		out("\tend")
		out("\tif self.OnTabSelected then")
		out("\t\tself:OnTabSelected(index)")
		out("\tend")
		out("end")
	end,
	-- Runs once every element exists: registers the pages and selects the start tab.
	ExportAfterChildren = function(out, v, p, node, childVars)
		out(v .. ".Pages = { " .. table.concat(childVars, ", ") .. " }")
		local count = #ns.SplitTabs(p.tabs)
		if count > 0 then
			out(v .. ":SelectTab(" .. ns.LuaNum(Clamp(p.activeTab, 1, count)) .. ")")
		end
	end,
})

---------------------------------------------------------------------------
-- Collapsible section (ListHeaderVisualTemplate)
---------------------------------------------------------------------------

-- A list header with a +/- button; its children are the section content and are
-- hidden while it is collapsed. Elements below it do not move up automatically.
Register({
	type = "Section",
	label = L["Collapsible section"],
	frameType = "Button",
	template = "ListHeaderVisualTemplate",
	width = 260, height = 30,
	container = true,
	props = {
		{ key = "text", label = L["Text"], kind = "string", default = "Section" },
		{ key = "collapsed", label = L["Collapsed"], kind = "bool", default = false },
	},
	scripts = {
		{ name = "OnToggle", args = "self, collapsed", method = true },
	},
	DefaultChildren = function()
		return {
			{ type = "Frame", name = "SectionContent", props = { backdrop = "None" },
				fields = { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = 0, y = -2, w = 260, h = 120 } },
		}
	end,
	ChildShown = function(canvas, node)
		return not canvas:IsCollapsed(node.id)
	end,
	Create = function(parent)
		return CreateFrame("Button", nil, parent, "ListHeaderVisualTemplate")
	end,
	Apply = function(f, p)
		f:SetHeaderText(p.text)
		f.CollapseButton:UpdateCollapsedState(p.collapsed)
	end,
	Export = function(out, v, p)
		out(v .. ":SetHeaderText(" .. ns.LuaStr(p.text) .. ")")
		out("-- Shows or hides the section content; calls self:OnToggle(collapsed) when defined.")
		out("function " .. v .. ":SetCollapsed(collapsed)")
		out("\tself.collapsed = collapsed")
		out("\tself.CollapseButton:UpdateCollapsedState(collapsed)")
		out("\tfor _, child in ipairs(self.Sections or {}) do")
		out("\t\tchild:SetShown(not collapsed)")
		out("\tend")
		out("\tif self.OnToggle then")
		out("\t\tself:OnToggle(collapsed)")
		out("\tend")
		out("end")
		out(v .. ":SetScript(\"OnClick\", function(self)")
		out("\tPlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)")
		out("\tself:SetCollapsed(not self.collapsed)")
		out("end)")
	end,
	ExportAfterChildren = function(out, v, p, node, childVars)
		out(v .. ".Sections = { " .. table.concat(childVars, ", ") .. " }")
		out(v .. ":SetCollapsed(" .. tostring(p.collapsed and true or false) .. ")")
	end,
})

---------------------------------------------------------------------------
-- Dropdown (Blizzard_Menu dropdown buttons)
---------------------------------------------------------------------------

-- The dropdown templates that work on their own. selectionText: shows the chosen entry,
-- fixedText: always shows its own text (filter button), steppers: can get < > buttons.
local DROPDOWN_STYLES = {
	WowStyle1DropdownTemplate = { width = 150, height = 25, selectionText = true, steppers = true },
	WowStyle2DropdownTemplate = { width = 150, height = 25, selectionText = true, steppers = true },
	WowStyle1FilterDropdownTemplate = { width = 135, height = 22, fixedText = true },
	WowStyle1ArrowDropdownTemplate = { width = 25, height = 25 },
	UIPanelIconDropdownButtonTemplate = { width = 15, height = 16 },
	UIPanelArrowDropdownButtonTemplate = { width = 15, height = 16 },
}

local DROPDOWN_OPTIONS = {
	{ value = "WowStyle1DropdownTemplate", label = L["Standard"] },
	{ value = "WowStyle2DropdownTemplate", label = L["Settings style"] },
	{ value = "WowStyle1FilterDropdownTemplate", label = L["Filter button"] },
	{ value = "WowStyle1ArrowDropdownTemplate", label = L["Arrow button"] },
	{ value = "UIPanelIconDropdownButtonTemplate", label = L["Gear icon"] },
	{ value = "UIPanelArrowDropdownButtonTemplate", label = L["Small arrow"] },
}

-- "A;B;-;#Group;C": "-" is a divider, "#Text" a title, everything else an option.
function ns.ParseMenuItems(text)
	local items, option = {}, 0
	for _, token in ipairs(ns.SplitTabs(text)) do
		if token == "-" then
			table.insert(items, { kind = "divider" })
		elseif token:sub(1, 1) == "#" then
			table.insert(items, { kind = "title", text = token:sub(2) })
		else
			option = option + 1
			table.insert(items, { kind = "option", text = token, index = option })
		end
	end
	return items
end

local function ParseSelection(text, single)
	local selected = {}
	for _, token in ipairs(ns.SplitTabs(text)) do
		local index = tonumber(token)
		if index then
			selected[index] = true
			if single then break end
		end
	end
	return selected
end

Register({
	type = "Dropdown",
	label = L["Dropdown"],
	frameType = "DropdownButton",
	width = 150, height = 25,
	props = {
		{ key = "style", label = L["Style"], kind = "select", default = "WowStyle1DropdownTemplate", options = DROPDOWN_OPTIONS },
		{ key = "mode", label = L["Mode"], kind = "select", default = "radio", options = {
			{ value = "radio", label = L["Single choice"] },
			{ value = "checkbox", label = L["Multiple choice"] },
			{ value = "button", label = L["Actions"] },
		} },
		{ key = "items", label = L["Entries (a;-;#b)"], kind = "string", default = "Option 1;Option 2;Option 3" },
		{ key = "selected", label = L["Selected (1;3)"], kind = "string", default = "1" },
		{ key = "text", label = L["Text"], kind = "string", default = "" },
		{ key = "steppers", label = L["Arrow steppers"], kind = "bool", default = false },
		{ key = "enabled", label = L["Enabled"], kind = "bool", default = true },
	},
	scripts = {
		{ name = "OnSelect", args = "self, index, text, checked", method = true },
	},
	PoolKey = function(p)
		return "Dropdown:" .. p.style
	end,
	ExportTemplate = function(p)
		return p.style
	end,
	Create = function(parent, p)
		local f = CreateFrame("DropdownButton", nil, parent, p.style)
		f.mfbSelected = {}
		return f
	end,
	Apply = function(f, p)
		local style = DROPDOWN_STYLES[p.style] or {}
		local items = ns.ParseMenuItems(p.items)
		f.mfbSelected = ParseSelection(p.selected, p.mode == "radio")
		local function Notify(item, checked)
			if f.mfbMethodOnSelect then
				f.mfbMethodOnSelect(f, item.index, item.text, checked)
			end
		end
		f:SetupMenu(function(_, root)
			for _, item in ipairs(items) do
				if item.kind == "divider" then
					root:CreateDivider()
				elseif item.kind == "title" then
					root:CreateTitle(item.text)
				elseif p.mode == "radio" then
					root:CreateRadio(item.text, function() return f.mfbSelected[item.index] end, function()
						wipe(f.mfbSelected)
						f.mfbSelected[item.index] = true
						Notify(item, true)
					end)
				elseif p.mode == "checkbox" then
					root:CreateCheckbox(item.text, function() return f.mfbSelected[item.index] end, function()
						f.mfbSelected[item.index] = not f.mfbSelected[item.index] or nil
						Notify(item, f.mfbSelected[item.index] == true)
					end)
				else
					root:CreateButton(item.text, function() Notify(item) end)
				end
			end
		end)
		if style.selectionText then
			f:SetDefaultText(p.text)
		elseif style.fixedText and p.text ~= "" then
			f:SetText(p.text)
		end
		local showSteppers = style.steppers and p.steppers and p.mode == "radio"
		if showSteppers and not f.mfbDecrement then
			f.mfbDecrement = CreateFrame("Button", nil, f, "SteppersDecrementButtonTemplate")
			f.mfbDecrement:SetPoint("RIGHT", f, "LEFT", -5, 0)
			f.mfbDecrement:SetScript("OnClick", function()
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				f:Decrement()
			end)
			f.mfbIncrement = CreateFrame("Button", nil, f, "SteppersIncrementButtonTemplate")
			f.mfbIncrement:SetPoint("LEFT", f, "RIGHT", 4, 0)
			f.mfbIncrement:SetScript("OnClick", function()
				PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
				f:Increment()
			end)
		end
		if f.mfbDecrement then
			f.mfbDecrement:SetShown(showSteppers)
			f.mfbIncrement:SetShown(showSteppers)
		end
		f:SetEnabled(p.enabled)
	end,
	Export = function(out, v, p)
		local style = DROPDOWN_STYLES[p.style] or {}
		local tokens = {}
		for i, token in ipairs(ns.SplitTabs(p.items)) do
			tokens[i] = ns.LuaStr(token)
		end
		local selected = {}
		for index in pairs(ParseSelection(p.selected, p.mode == "radio")) do
			table.insert(selected, ("[%d] = true"):format(index))
		end
		table.sort(selected)
		out(v .. ".Selected = { " .. table.concat(selected, ", ") .. " }")
		if style.selectionText and p.text ~= "" then
			out(v .. ":SetDefaultText(" .. ns.LuaStr(p.text) .. ")")
		elseif style.fixedText and p.text ~= "" then
			out(v .. ":SetText(" .. ns.LuaStr(p.text) .. ")")
		end
		out("-- Entries: \"-\" is a divider, \"#Text\" a title. " .. v .. ":OnSelect(index, text, checked) is called when defined.")
		out(v .. ":SetupMenu(function(dropdown, root)")
		out("\tlocal option = 0")
		out("\tfor _, text in ipairs({ " .. table.concat(tokens, ", ") .. " }) do")
		out("\t\tif text == \"-\" then")
		out("\t\t\troot:CreateDivider()")
		out("\t\telseif text:sub(1, 1) == \"#\" then")
		out("\t\t\troot:CreateTitle(text:sub(2))")
		out("\t\telse")
		out("\t\t\toption = option + 1")
		out("\t\t\tlocal index = option")
		if p.mode == "radio" then
			out("\t\t\troot:CreateRadio(text, function() return " .. v .. ".Selected[index] end, function()")
			out("\t\t\t\twipe(" .. v .. ".Selected)")
			out("\t\t\t\t" .. v .. ".Selected[index] = true")
			out("\t\t\t\tif " .. v .. ".OnSelect then " .. v .. ":OnSelect(index, text, true) end")
			out("\t\t\tend)")
		elseif p.mode == "checkbox" then
			out("\t\t\troot:CreateCheckbox(text, function() return " .. v .. ".Selected[index] end, function()")
			out("\t\t\t\t" .. v .. ".Selected[index] = not " .. v .. ".Selected[index] or nil")
			out("\t\t\t\tif " .. v .. ".OnSelect then " .. v .. ":OnSelect(index, text, " .. v .. ".Selected[index] == true) end")
			out("\t\t\tend)")
		else
			out("\t\t\troot:CreateButton(text, function()")
			out("\t\t\t\tif " .. v .. ".OnSelect then " .. v .. ":OnSelect(index, text) end")
			out("\t\t\tend)")
		end
		out("\t\tend")
		out("\tend")
		out("end)")
		if style.steppers and p.steppers and p.mode == "radio" then
			out(v .. ".DecrementButton = CreateFrame(\"Button\", nil, " .. v .. ", \"SteppersDecrementButtonTemplate\")")
			out(v .. ".DecrementButton:SetPoint(\"RIGHT\", " .. v .. ", \"LEFT\", -5, 0)")
			out(v .. ".DecrementButton:SetScript(\"OnClick\", function()")
			out("\tPlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)")
			out("\t" .. v .. ":Decrement()")
			out("end)")
			out(v .. ".IncrementButton = CreateFrame(\"Button\", nil, " .. v .. ", \"SteppersIncrementButtonTemplate\")")
			out(v .. ".IncrementButton:SetPoint(\"LEFT\", " .. v .. ", \"RIGHT\", 4, 0)")
			out(v .. ".IncrementButton:SetScript(\"OnClick\", function()")
			out("\tPlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)")
			out("\t" .. v .. ":Increment()")
			out("end)")
		end
		if not p.enabled then
			out(v .. ":Disable()")
		end
	end,
})

---------------------------------------------------------------------------
-- Template (any Blizzard template)
---------------------------------------------------------------------------

local templateCounter = 0
local probeFrame

-- A shown but invisible frame, used to trigger a new widget's OnShow once.
local function ProbeFrame()
	if not probeFrame then
		probeFrame = CreateFrame("Frame", nil, UIParent)
		probeFrame:SetSize(1, 1)
		probeFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMRIGHT", 100, -100)
		probeFrame:SetAlpha(0)
	end
	return probeFrame
end

local WIDGET_TYPES = {
	"Frame", "Button", "CheckButton", "EditBox", "Slider", "StatusBar", "ScrollFrame",
	"EventFrame", "EventButton", "DropdownButton", "Cooldown", "PlayerModel", "ModelScene",
	"SimpleHTML", "MessageFrame", "ScrollingMessageFrame", "ColorSelect",
}

-- Lookup of the generated template list: name -> { name, widget, addon, width, height }.
function ns.GetTemplateInfo(name)
	if not ns.TemplateIndex then
		ns.TemplateIndex = {}
		for _, entry in ipairs(ns.TemplateList or {}) do
			ns.TemplateIndex[entry[1]] = entry
		end
	end
	return ns.TemplateIndex[name]
end

Register({
	type = "Template",
	label = L["Template"],
	width = 120, height = 32,
	container = true,
	props = {
		{ key = "template", label = L["Template"], kind = "template", default = "UIPanelButtonTemplate" },
		{ key = "widget", label = L["Widget type"], kind = "select", default = "Button", options = WIDGET_TYPES },
		{ key = "text", label = L["Text / title"], kind = "string", default = "" },
		{ key = "editorOnLoad", label = L["Run OnLoad in editor"], kind = "bool", default = false },
	},
	PoolKey = function(p)
		return "Template:" .. p.widget .. ":" .. p.template
	end,
	ExportFrameType = function(p)
		return p.widget
	end,
	ExportTemplate = function(p)
		return p.template ~= "" and p.template or nil
	end,
	-- Templates that build names from self:GetName() need a global name in the export too.
	ExportGlobalName = function(node)
		local info = ns.GetTemplateInfo(node.props.template)
		if info and info[8] then
			return ns.SanitizeName(ns.Doc:CurrentName()) .. "_" .. node.name
		end
	end,
	-- Unknown or broken templates fall back to a red placeholder instead of breaking the canvas.
	Create = function(parent, p, node)
		local function Placeholder(message, stack)
			ns.Print(L["Template %s can't be used: %s"], p.template, message)
			if ns.Errors and node then
				ns.Errors:Add({ kind = "template", message = message, stack = stack or "", node = node })
			end
			local f = CreateFrame("Frame", nil, parent)
			local bg = f:CreateTexture(nil, "BACKGROUND")
			bg:SetAllPoints()
			bg:SetColorTexture(0.6, 0.1, 0.1, 0.5)
			local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			text:SetAllPoints()
			text:SetText(L["Template not available"])
			f.mfbError = message
			return f
		end

		-- Base templates whose OnLoad expects keys from a derived template would only raise errors.
		local info = ns.GetTemplateInfo(p.template)
		if info and info[7] then
			return Placeholder(L["it only works through a derived template that provides: %s"]:format(info[7]))
		end

		-- Errors inside the template's OnLoad go to the error handler instead of failing
		-- CreateFrame, so they are captured there for the duration of the call. The widget is
		-- also shown once on an invisible frame so errors in OnShow are caught here too, not
		-- later on the canvas. Every template gets a unique global name: many (older) ones
		-- build child names from self:GetName() and fail without one.
		templateCounter = templateCounter + 1
		local globalName = "ForeverFrameBuilderTemplate" .. templateCounter
		local captured, capturedStack
		local previousHandler = geterrorhandler()
		seterrorhandler(function(message)
			if not captured then
				captured = tostring(message)
				capturedStack = ns.Errors and ns.Errors.Stack(3) or ""
			end
		end)
		local ok, f = pcall(CreateFrame, p.widget, globalName, parent, p.template ~= "" and p.template or nil)
		if ok and type(f) == "table" and not captured then
			pcall(function()
				f:SetParent(ProbeFrame())
				f:Show()
				f:SetParent(parent)
			end)
		end
		seterrorhandler(previousHandler)
		if not ok then
			captured = captured or tostring(f)
		end
		if captured or type(f) ~= "table" then
			if ok and type(f) == "table" then
				f:Hide()
			end
			return Placeholder(captured or "?", capturedStack)
		end
		if f.SetAutoFocus then
			f:SetAutoFocus(false)
		end
		return f
	end,
	Apply = function(f, p)
		if f.mfbError then return end
		-- List headers only show their +/- icon once a state is set.
		if f.CollapseButton and f.CollapseButton.UpdateCollapsedState then
			f.CollapseButton:UpdateCollapsedState(false)
		end
		if p.text == "" then return end
		if f.SetHeaderText then
			f:SetHeaderText(p.text)
		elseif f.SetTitle then
			f:SetTitle(p.text)
		elseif f.SetText then
			f:SetText(p.text)
		end
	end,
	Export = function(out, v, p)
		if p.widget == "EditBox" then
			out(v .. ":SetAutoFocus(false)")
		end
		out("if " .. v .. ".CollapseButton and " .. v .. ".CollapseButton.UpdateCollapsedState then")
		out("\t" .. v .. ".CollapseButton:UpdateCollapsedState(false)")
		out("end")
		if p.text ~= "" then
			out("if " .. v .. ".SetHeaderText then")
			out("\t" .. v .. ":SetHeaderText(" .. ns.LuaStr(p.text) .. ")")
			out("elseif " .. v .. ".SetTitle then")
			out("\t" .. v .. ":SetTitle(" .. ns.LuaStr(p.text) .. ")")
			out("elseif " .. v .. ".SetText then")
			out("\t" .. v .. ":SetText(" .. ns.LuaStr(p.text) .. ")")
			out("end")
		end
	end,
})

-- Palette order (registration order is only the fallback).
ns.ElementOrder = {
	"Frame", "Window", "Tabs", "Section", "ScrollFrame", "Button", "CheckButton", "EditBox", "Dropdown",
	"Slider", "StatusBar", "Texture", "FontString", "Model", "Template",
}

-- Default property values for a freshly created element.
function ns.DefaultProps(elementType)
	local props = {}
	for _, prop in ipairs(ns.Elements[elementType].props) do
		props[prop.key] = type(prop.default) == "table" and CopyTable(prop.default) or prop.default
	end
	return props
end

-- Normalizes an options list to { value, label } pairs.
function ns.OptionList(options)
	local list = {}
	for _, option in ipairs(options) do
		if type(option) == "table" then
			table.insert(list, option)
		else
			table.insert(list, { value = option, label = option })
		end
	end
	return list
end
