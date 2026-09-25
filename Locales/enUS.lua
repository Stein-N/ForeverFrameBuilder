-- Forever Frame Builder
-- Base locale: keys are the English strings, missing translations fall back to the key.

local _, ns = ...

ns.L = setmetatable({}, {
	__index = function(_, key)
		return key
	end,
})

local L = ns.L

L["INSPECTOR_HELP"] = "Nothing selected.\n\n"
	.. "|cffffd100Add|r  click an element in the palette or drag it onto the canvas.\n"
	.. "|cffffd100Select|r  click it on the canvas or in the layer list.\n"
	.. "|cffffd100Move|r  drag it. Hold Shift to drag the selection even if it is covered.\n"
	.. "|cffffd100Nest|r  hold Ctrl when releasing to drop it into the frame under the cursor.\n"
	.. "|cffffd100Resize|r  drag the blue handles.\n"
	.. "|cffffd100Pan / zoom|r  middle mouse or Alt+drag, mouse wheel.\n"
	.. "|cffffd100Scroll frames|r  Ctrl+wheel scrolls their content while editing.\n"
	.. "|cffffd100Keys|r  arrows nudge (Shift: one grid step), Del, Ctrl+Z/Y/C/V/D."
L["STATUS_HINT"] = "Drag: move  •  Shift+drag: move selection  •  Ctrl on release: nest  •  Alt/middle drag: pan  •  Wheel: zoom (Ctrl: scroll)  •  Right click: menu"
L["PREVIEW_HINT"] = "Preview: elements and scripts are live. Click \"Edit mode\" to continue editing."
