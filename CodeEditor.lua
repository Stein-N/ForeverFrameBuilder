-- Forever Frame Builder
-- CodeEditor: Lua syntax highlighting, live syntax checks, line numbers and indentation for
-- a ScrollingEditBoxTemplate.
--
-- The edit box keeps the plain text (so cursor, selection, copy and GetText stay correct) but
-- draws it invisibly; a font string with the colored copy lies exactly on top of it.

local _, ns = ...
local L = ns.L

local Syntax = {}
ns.LuaSyntax = Syntax

local MAX_HIGHLIGHT_LENGTH = 20000
local INDENT = "    "
local GUTTER_WIDTH = 30

local COLORS = {
	keyword = "ffc586c0",
	constant = "ff569cd6",
	func = "ffdcdcaa",
	string = "ffce9178",
	number = "ffb5cea8",
	comment = "ff6a9955",
	text = "ffd4d4d4",
}

local KEYWORDS = {}
for word in ("and break do else elseif end for function goto if in local not or repeat return then until while"):gmatch("%a+") do
	KEYWORDS[word] = true
end
local CONSTANTS = { ["true"] = true, ["false"] = true, ["nil"] = true, self = true, E = true }

---------------------------------------------------------------------------
-- Highlighting
---------------------------------------------------------------------------

-- Returns text with WoW color codes; "|" is escaped so the code shows literally.
function Syntax.Colorize(text)
	local out, plain = {}, {}
	local function Flush()
		if #plain > 0 then
			table.insert(out, "|c" .. COLORS.text .. table.concat(plain):gsub("|", "||") .. "|r")
			wipe(plain)
		end
	end
	local function Emit(kind, piece)
		Flush()
		table.insert(out, "|c" .. COLORS[kind] .. piece:gsub("|", "||") .. "|r")
	end

	local i, n = 1, #text
	while i <= n do
		local c = text:sub(i, i)
		if c == "-" and text:sub(i + 1, i + 1) == "-" then
			-- Comment: --[[ ]] / --[==[ ]==] or to the end of the line.
			local level = text:match("^%[(=*)%[", i + 2)
			local stop
			if level then
				local _, e = text:find("]" .. level .. "]", i + 2, true)
				stop = e or n
			else
				stop = (text:find("\n", i, true) or (n + 1)) - 1
			end
			Emit("comment", text:sub(i, stop))
			i = stop + 1
		elseif c == "\"" or c == "'" then
			local j = i + 1
			while j <= n do
				local d = text:sub(j, j)
				if d == "\\" then
					j = j + 2
				elseif d == c or d == "\n" then
					break
				else
					j = j + 1
				end
			end
			j = math.min(j, n)
			Emit("string", text:sub(i, j))
			i = j + 1
		elseif c == "[" and text:match("^%[=*%[", i) then
			local level = text:match("^%[(=*)%[", i)
			local _, e = text:find("]" .. level .. "]", i + 2, true)
			local stop = e or n
			Emit("string", text:sub(i, stop))
			i = stop + 1
		elseif c:match("%d") or (c == "." and text:sub(i + 1, i + 1):match("%d")) then
			local number = text:match("^0[xX]%x+", i) or text:match("^%d*%.?%d+[eE][%+%-]?%d+", i)
				or text:match("^%d*%.?%d+", i) or c
			Emit("number", number)
			i = i + #number
		elseif c:match("[%a_]") then
			local word = text:match("^[%a_][%w_]*", i)
			local after = text:match("^%s*(.)", i + #word)
			if KEYWORDS[word] then
				Emit("keyword", word)
			elseif CONSTANTS[word] then
				Emit("constant", word)
			elseif after == "(" or after == "\"" or after == "{" then
				Emit("func", word)
			else
				table.insert(plain, word)
			end
			i = i + #word
		else
			table.insert(plain, c)
			i = i + 1
		end
	end
	Flush()
	return table.concat(out)
end

---------------------------------------------------------------------------
-- Syntax check
---------------------------------------------------------------------------

-- Checks code the way it is compiled later. args wraps it in function(args) ... end like
-- element scripts; nil checks it as a plain chunk. Returns true, or false, line, message
-- with the line counted in the user's code.
function Syntax.Check(code, args)
	local source, offset = code, 0
	if args then
		source, offset = "return function(" .. args .. ")\n" .. code .. "\nend", 1
	end
	local fn, err = loadstring(source, "code")
	if fn then return true end
	local line, message = tostring(err):match(":(%d+): (.*)$")
	line = tonumber(line)
	if line then
		line = math.max(1, line - offset)
		-- Errors reported at the added "end" belong to the last line of the user's code.
		local lines = select(2, code:gsub("\n", "\n")) + 1
		line = math.min(line, lines)
	end
	return false, line, message or tostring(err)
end

---------------------------------------------------------------------------
-- Editor
---------------------------------------------------------------------------

local CodeEditor = {}
ns.CodeEditor = CodeEditor
CodeEditor.__index = CodeEditor

local function LeadingIndent(line)
	return line:match("^[ \t]*") or ""
end

-- Lines that open a block get one more level of indentation after Enter.
local function OpensBlock(line)
	line = line:gsub("%-%-.*$", ""):gsub("%s+$", "")
	return line:match("then$") or line:match("do$") or line:match("else$") or line:match("repeat$")
		or line:match("{$") or line:match("function%s*[%w_.:]*%s*%(.-%)$") ~= nil
end

-- editor: a ScrollingEditBoxTemplate frame, status: a font string for the syntax result.
function CodeEditor.Attach(editor, status)
	local self = setmetatable({ editor = editor, status = status, enabled = false }, CodeEditor)
	local editBox = editor:GetEditBox()
	self.editBox = editBox

	local overlay = editBox:CreateFontString(nil, "OVERLAY")
	overlay:SetJustifyH("LEFT")
	overlay:SetJustifyV("TOP")
	overlay:SetWordWrap(true)
	if overlay.SetNonSpaceWrap then overlay:SetNonSpaceWrap(true) end
	overlay:Hide()
	self.overlay = overlay

	local gutter = editBox:CreateFontString(nil, "OVERLAY")
	gutter:SetJustifyH("RIGHT")
	gutter:SetJustifyV("TOP")
	gutter:SetTextColor(0.45, 0.45, 0.5)
	gutter:Hide()
	self.gutter = gutter

	local marker = editBox:CreateTexture(nil, "BACKGROUND")
	marker:SetColorTexture(1, 0.2, 0.2, 0.25)
	marker:Hide()
	self.marker = marker

	editor:RegisterCallback("OnTextChanged", function(_, box)
		self:OnTextChanged(box)
	end, self)
	return self
end

-- options: enabled (highlighting + checks), args (script arguments for the check, or nil for
-- a plain chunk), check (false disables the syntax check).
function CodeEditor:SetMode(options)
	self.enabled = options.enabled and true or false
	self.args = options.args
	self.checkSyntax = options.check ~= false
	local editBox = self.editBox
	local font = editBox:GetFontObject()
	for _, region in ipairs({ self.overlay, self.gutter }) do
		if font then region:SetFontObject(font) end
	end
	if self.enabled then
		self.editor:SetTextInsets(GUTTER_WIDTH + 6, 4, 2, 2)
	else
		self.editor:SetTextInsets(0, 0, 0, 0)
	end
	local left, right, top = editBox:GetTextInsets()
	self.overlay:ClearAllPoints()
	self.overlay:SetPoint("TOPLEFT", left or 0, -(top or 0))
	self.overlay:SetPoint("TOPRIGHT", -(right or 0), -(top or 0))
	self.gutter:ClearAllPoints()
	self.gutter:SetPoint("TOPRIGHT", editBox, "TOPLEFT", GUTTER_WIDTH, -(top or 0))
	self.gutter:SetWidth(GUTTER_WIDTH)
	self.gutter:SetShown(self.enabled)
	self.status:SetText("")
	self.marker:Hide()
	self.lastLength = nil
	self:Refresh()
end

-- Code editors indent with spaces so the overlay lines up with the edit box.
function CodeEditor:PrepareText(text)
	if self.enabled then
		return (text:gsub("\t", INDENT))
	end
	return text
end

function CodeEditor:OnTab()
	if self.enabled then
		self.editBox:Insert(INDENT)
		return true
	end
end

function CodeEditor:OnTextChanged(box)
	if not self.enabled then return end
	local text = box:GetText() or ""
	-- Enter inserted a newline right before the cursor: carry the indentation over.
	if not self.indenting and self.lastLength and #text == self.lastLength + 1 then
		local cursor = box:GetCursorPosition()
		if text:sub(cursor, cursor) == "\n" then
			local before = text:sub(1, cursor - 1)
			local previous = before:match("([^\n]*)$") or ""
			local indent = LeadingIndent(previous) .. (OpensBlock(previous) and INDENT or "")
			if indent ~= "" then
				self.indenting = true
				box:Insert(indent)
				self.indenting = false
				return
			end
		end
	end
	self.lastLength = #text
	self:Refresh()
end

function CodeEditor:Refresh()
	local box = self.editBox
	local text = box:GetText() or ""
	self.lastLength = #text
	if not self.enabled then
		box:SetTextColor(1, 1, 1, 1)
		self.overlay:Hide()
		self.gutter:Hide()
		self.marker:Hide()
		return
	end

	-- Very long texts stay plain; coloring them on every key press would stutter.
	if #text <= MAX_HIGHLIGHT_LENGTH then
		box:SetTextColor(1, 1, 1, 0)
		self.overlay:SetText(Syntax.Colorize(text))
		self.overlay:Show()
	else
		box:SetTextColor(1, 1, 1, 1)
		self.overlay:Hide()
	end

	local lines = select(2, text:gsub("\n", "\n")) + 1
	local numbers = {}
	for i = 1, lines do
		numbers[i] = i
	end
	self.gutter:SetText(table.concat(numbers, "\n"))
	self.gutter:Show()

	self.marker:Hide()
	if not self.checkSyntax then
		self.status:SetText("")
		return
	end
	local ok, line, message = Syntax.Check(text, self.args)
	if ok then
		self.status:SetText("|cff40ff40" .. L["Syntax OK"] .. "|r")
		return
	end
	self.status:SetText("|cffff4040" .. (line and L["Line %d: %s"]:format(line, message) or message) .. "|r")
	if line then
		-- Marks the line, assuming it isn't wrapped (code lines usually aren't).
		local _, fontHeight = box:GetFont()
		local lineHeight = (fontHeight or 12) + (box.GetSpacing and box:GetSpacing() or 0)
		local _, _, top = box:GetTextInsets()
		self.marker:ClearAllPoints()
		self.marker:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -((top or 0) + (line - 1) * lineHeight))
		self.marker:SetPoint("RIGHT", box, "RIGHT")
		self.marker:SetHeight(lineHeight)
		self.marker:Show()
	end
end
