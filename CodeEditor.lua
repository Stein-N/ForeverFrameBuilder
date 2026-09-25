-- Forever Frame Builder
-- CodeEditor: turns a ScrollingEditBoxTemplate into a Lua editor.
--
-- Highlighting and indentation come from the embedded "For All Indents And Purposes"
-- (IndentationLib, Libs\ForAllIndentsAndPurposes). This module adds line numbers, a live
-- syntax check with the line of the user's code, and a plain view for copying.

local _, ns = ...
local L = ns.L

local Syntax = {}
ns.LuaSyntax = Syntax

local TAB_WIDTH = 4
local GUTTER_WIDTH = 30

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

local CodeEditor = {}
ns.CodeEditor = CodeEditor
CodeEditor.__index = CodeEditor

-- editor: a ScrollingEditBoxTemplate frame, status: a font string for the syntax result.
function CodeEditor.Attach(editor, status)
	local self = setmetatable({ editor = editor, status = status, enabled = false, generation = 0 }, CodeEditor)
	local editBox = editor:GetEditBox()
	self.editBox = editBox

	local gutter = editBox:CreateFontString(nil, "OVERLAY")
	gutter:SetJustifyH("RIGHT")
	gutter:SetJustifyV("TOP")
	gutter:SetTextColor(0.45, 0.45, 0.5)
	gutter:Hide()
	self.gutter = gutter

	-- Error marker: a bar in the line number column only, so nothing covers the text.
	local marker = editBox:CreateTexture(nil, "BACKGROUND")
	marker:SetColorTexture(1, 0.2, 0.2, 0.35)
	marker:Hide()
	self.marker = marker
	return self
end

-- IndentationLib replaces the edit box scripts with SetScript, which drops hooks, so ours
-- is added again after every change of the library state. Older hooks see a newer
-- generation and do nothing.
function CodeEditor:Hook()
	self.generation = self.generation + 1
	local generation = self.generation
	self.editBox:HookScript("OnTextChanged", function()
		if self.generation == generation then
			self:OnTextChanged()
		end
	end)
end

function CodeEditor:EnableLibrary()
	if not self.libraryEnabled and IndentationLib then
		IndentationLib.enable(self.editBox, nil, TAB_WIDTH)
		self.libraryEnabled = true
	end
	self:Hook()
end

function CodeEditor:DisableLibrary()
	if self.libraryEnabled and IndentationLib then
		IndentationLib.disable(self.editBox)
		self.libraryEnabled = false
	end
	self:Hook()
end

-- options: enabled (highlighting, indentation, checks), args (script arguments for the
-- check, or nil for a plain chunk), check (false disables the syntax check).
function CodeEditor:SetMode(options)
	self.enabled = options.enabled and true or false
	self.args = options.args
	self.checkSyntax = options.check ~= false
	self.plainView = false
	local editBox = self.editBox
	local font = editBox:GetFontObject()
	if font then self.gutter:SetFontObject(font) end
	if self.enabled then
		self.editor:SetTextInsets(GUTTER_WIDTH + 6, 4, 2, 2)
		self:EnableLibrary()
	else
		self.editor:SetTextInsets(0, 0, 0, 0)
		self:DisableLibrary()
	end
	local _, _, top = editBox:GetTextInsets()
	self.gutter:ClearAllPoints()
	self.gutter:SetPoint("TOPRIGHT", editBox, "TOPLEFT", GUTTER_WIDTH, -(top or 0))
	self.gutter:SetWidth(GUTTER_WIDTH)
	self.status:SetText("")
	self.marker:Hide()
	self.gutter:SetShown(self.enabled)
end

-- In code mode Tab is handled by IndentationLib (it re-indents the code).
function CodeEditor:OnTab()
	return self.enabled
end

-- Shows the uncolored code so "select all + Ctrl+C" copies exactly the code (the colored
-- text would copy its color codes). Typing turns the colors back on.
function CodeEditor:ShowPlain()
	if not self.enabled or self.plainView then return end
	self.plainView = true
	self.restoring = true
	self:DisableLibrary()
	self.restoring = false
end

function CodeEditor:OnTextChanged()
	if not self.enabled then return end
	if self.plainView and not self.restoring then
		-- The user typed in the plain view: color it again.
		self.plainView = false
		self.restoring = true
		self:EnableLibrary()
		self.restoring = false
	end
	self:Refresh()
end

-- Line numbers and the syntax status for the current code.
function CodeEditor:Refresh()
	if not self.enabled then
		self.gutter:Hide()
		self.marker:Hide()
		return
	end
	local box = self.editBox
	local code = box:GetText() or ""
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
