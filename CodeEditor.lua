-- Forever Frame Builder
-- CodeEditor: Lua highlighting and indentation for the script editor, done the way
-- Watchtower does it - with the embedded "For All Indents And Purposes" (IndentationLib) on a
-- plain multi-line edit box - plus the syntax check used when saving a script.

local _, ns = ...

local Syntax = {}
ns.LuaSyntax = Syntax

local TAB_WIDTH = 3

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

-- Turns highlighting/indentation on or off for an edit box.
function CodeEditor.SetEnabled(editBox, enabled)
	if not IndentationLib then return end
	if enabled then
		IndentationLib.enable(editBox, nil, TAB_WIDTH)
	else
		IndentationLib.disable(editBox)
	end
end
