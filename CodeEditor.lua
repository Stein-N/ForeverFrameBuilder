-- Forever Frame Builder
-- CodeEditor: Lua syntax highlighting, live syntax checks, line numbers and indentation for
-- a ScrollingEditBoxTemplate.
--
-- Like "For All Indents And Purposes" (used e.g. by Watchtower), the color codes are written
-- into the edit box text itself - WoW edit boxes render them. GetText/SetText of the edit box
-- are wrapped so everyone else only ever sees and sets the plain code, and the cursor is
-- translated between the colored text and the plain code on every change.

local _, ns = ...
local L = ns.L

local Syntax = {}
ns.LuaSyntax = Syntax

local MAX_HIGHLIGHT_LENGTH = 20000
-- Coloring waits until typing pauses, like FAIAP does.
local RECOLOR_DELAY = 0.2
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
-- Colored text <-> plain code
---------------------------------------------------------------------------

-- Plain code of a colored text, plus the plain position of a cursor in the colored text.
-- Cursor positions count the characters before the cursor.
function Syntax.Decode(raw, rawCursor)
	local out, count, plainCursor = {}, 0, nil
	local i, n = 1, #raw
	while i <= n do
		if rawCursor and not plainCursor and i > rawCursor then
			plainCursor = count
		end
		local c = raw:sub(i, i)
		if c == "|" then
			local nextChar = raw:sub(i + 1, i + 1)
			if nextChar == "c" and raw:match("^%x%x%x%x%x%x%x%x", i + 2) then
				i = i + 10
			elseif nextChar == "r" then
				i = i + 2
			elseif nextChar == "|" then
				out[#out + 1] = "|"
				count = count + 1
				i = i + 2
			else
				out[#out + 1] = "|"
				count = count + 1
				i = i + 1
			end
		else
			out[#out + 1] = c
			count = count + 1
			i = i + 1
		end
	end
	if rawCursor and not plainCursor then
		plainCursor = count
	end
	return table.concat(out), plainCursor
end

-- Cursor position in a colored text for a position in its plain code.
function Syntax.RawCursor(raw, plainCursor)
	local count, i, n = 0, 1, #raw
	while i <= n and count < plainCursor do
		local c = raw:sub(i, i)
		if c == "|" then
			local nextChar = raw:sub(i + 1, i + 1)
			if nextChar == "c" and raw:match("^%x%x%x%x%x%x%x%x", i + 2) then
				i = i + 10
			elseif nextChar == "r" then
				i = i + 2
			elseif nextChar == "|" then
				count = count + 1
				i = i + 2
			else
				count = count + 1
				i = i + 1
			end
		else
			count = count + 1
			i = i + 1
		end
	end
	return i - 1
end

-- The colored text for plain code; very long code is only escaped.
function Syntax.Encode(code)
	if #code > MAX_HIGHLIGHT_LENGTH then
		return (code:gsub("|", "||"))
	end
	return Syntax.Colorize(code)
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

	-- Everyone (the template, the dialog, our callers) gets plain code from GetText and may
	-- pass plain code to SetText; only the edit box itself holds the colored text.
	local rawGetText, rawSetText = editBox.GetText, editBox.SetText
	self.rawGetText, self.rawSetText = rawGetText, rawSetText
	editBox.GetText = function(box)
		local raw = rawGetText(box) or ""
		if self.enabled and not self.plainView then
			return (Syntax.Decode(raw))
		end
		return raw
	end
	editBox.SetText = function(box, text)
		text = tostring(text or "")
		self.plainView = false
		if self.enabled then
			local encoded = Syntax.Encode(text)
			self.updating = true
			rawSetText(box, encoded)
			self.updating = false
			self.lastLength = #text
			self:Update(text)
			return
		end
		return rawSetText(box, text)
	end
	editBox:HookScript("OnTextChanged", function(box)
		self:OnTextChanged(box)
	end)
	editBox:HookScript("OnUpdate", function(box)
		if self.dirty and GetTime() - self.dirty >= RECOLOR_DELAY
			and not (box.IsInIMECompositionMode and box:IsInIMECompositionMode()) then
			self.dirty = nil
			self:Recolor(box)
		end
	end)

	local gutter = editBox:CreateFontString(nil, "OVERLAY")
	gutter:SetJustifyH("RIGHT")
	gutter:SetJustifyV("TOP")
	gutter:SetTextColor(0.45, 0.45, 0.5)
	gutter:Hide()
	self.gutter = gutter

	-- Error marker: a bar in the line number column only, so nothing covers the text or cursor.
	local marker = editBox:CreateTexture(nil, "BACKGROUND")
	marker:SetColorTexture(1, 0.2, 0.2, 0.35)
	marker:Hide()
	self.marker = marker
	return self
end

-- options: enabled (highlighting + checks), args (script arguments for the check, or nil for
-- a plain chunk), check (false disables the syntax check).
function CodeEditor:SetMode(options)
	local text = self.editBox:GetText()
	self.enabled = options.enabled and true or false
	self.args = options.args
	self.checkSyntax = options.check ~= false
	local editBox = self.editBox
	local font = editBox:GetFontObject()
	if font then self.gutter:SetFontObject(font) end
	if self.enabled then
		self.editor:SetTextInsets(GUTTER_WIDTH + 6, 4, 2, 2)
	else
		self.editor:SetTextInsets(0, 0, 0, 0)
	end
	local _, _, top = editBox:GetTextInsets()
	self.gutter:ClearAllPoints()
	self.gutter:SetPoint("TOPRIGHT", editBox, "TOPLEFT", GUTTER_WIDTH, -(top or 0))
	self.gutter:SetWidth(GUTTER_WIDTH)
	self.status:SetText("")
	self.marker:Hide()
	self.gutter:SetShown(self.enabled)
	-- Re-apply the current text in the new mode.
	editBox:SetText(text)
end

-- Code editors indent with spaces (like the rest of the editor's output).
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

-- Shows the uncolored code so "select all + Ctrl+C" copies exactly the code (the colored
-- text would copy its color codes). Typing colors it again.
function CodeEditor:ShowPlain()
	if not self.enabled or self.plainView then return end
	local code = self.editBox:GetText()
	self.updating = true
	self.rawSetText(self.editBox, code)
	self.updating = false
	self.plainView = true
	self.dirty = nil
end

-- Places the cursor at a position of the colored text. SetCursorPosition right after
-- SetText doesn't reliably show the cursor in colored text, so - like FAIAP - a helper
-- character is inserted there, selected and replaced: the edit box then moves the cursor
-- itself, the way typing does.
function CodeEditor:SetCaret(box, position)
	local raw = self.rawGetText(box) or ""
	if raw == "" then return end
	self.rawSetText(box, raw:sub(1, position) .. "a" .. raw:sub(position + 1))
	box:HighlightText(position, position + 1)
	box:Insert("\0")
end

-- After every change: indent new lines right away, update line numbers and the syntax
-- status, and schedule recoloring for when typing pauses.
function CodeEditor:OnTextChanged(box)
	if not self.enabled or self.updating then return end
	local raw = self.rawGetText(box) or ""
	local code, cursor
	if self.plainView then
		code, cursor = raw, box:GetCursorPosition()
	else
		code, cursor = Syntax.Decode(raw, box:GetCursorPosition())
	end
	-- Enter inserted a newline right before the cursor: carry the indentation over. Insert
	-- works at the edit box's own cursor, so it stays visible and in place.
	if self.lastLength and #code == self.lastLength + 1 and code:sub(cursor, cursor) == "\n" then
		local previous = code:sub(1, cursor - 1):match("([^\n]*)$") or ""
		local indent = LeadingIndent(previous) .. (OpensBlock(previous) and INDENT or "")
		if indent ~= "" then
			self.lastLength = #code
			box:Insert(indent)
			return
		end
	end
	self.lastLength = #code
	self.dirty = GetTime()
	self:Update(code)
end

-- Rewrites the edit box text with fresh colors and puts the cursor back on the same code
-- position.
function CodeEditor:Recolor(box)
	if not self.enabled then return end
	local raw = self.rawGetText(box) or ""
	local code, cursor
	if self.plainView then
		code, cursor = raw, box:GetCursorPosition()
		self.plainView = false
	else
		code, cursor = Syntax.Decode(raw, box:GetCursorPosition())
	end
	local encoded = Syntax.Encode(code)
	if encoded == raw then return end
	self.updating = true
	self.rawSetText(box, encoded)
	self:SetCaret(box, Syntax.RawCursor(encoded, cursor))
	self.updating = false
end

function CodeEditor:Refresh()
	self:Update(self.editBox:GetText() or "")
end

-- Line numbers and the syntax status for the plain code.
function CodeEditor:Update(code)
	if not self.enabled then
		self.gutter:Hide()
		self.marker:Hide()
		return
	end
	local box = self.editBox
	local lines = select(2, code:gsub("\n", "\n")) + 1
	local ok, errorLine, message = true, nil, nil
	if self.checkSyntax then
		ok, errorLine, message = Syntax.Check(code, self.args)
	end

	local numbers = {}
	for i = 1, lines do
		numbers[i] = (i == errorLine) and ("|cffff4040" .. i .. "|r") or i
	end
	self.gutter:SetText(table.concat(numbers, "\n"))
	self.gutter:Show()

	self.marker:Hide()
	if not self.checkSyntax then
		self.status:SetText("")
		return
	end
	if ok then
		self.status:SetText("|cff40ff40" .. L["Syntax OK"] .. "|r")
		return
	end
	self.status:SetText("|cffff4040" .. (errorLine and L["Line %d: %s"]:format(errorLine, message) or message) .. "|r")
	if errorLine then
		-- Assumes the line isn't wrapped (code lines usually aren't).
		local _, fontHeight = box:GetFont()
		local lineHeight = (fontHeight or 12) + (box.GetSpacing and box:GetSpacing() or 0)
		local _, _, top = box:GetTextInsets()
		self.marker:ClearAllPoints()
		self.marker:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -((top or 0) + (errorLine - 1) * lineHeight))
		self.marker:SetSize(GUTTER_WIDTH + 2, lineHeight)
		self.marker:Show()
	end
end
