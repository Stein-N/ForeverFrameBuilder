-- Forever Frame Builder
-- Dialogs: multi-line text window (script editor, export, import) and simple prompts.

local _, ns = ...
local L = ns.L
local Doc = ns.Doc
local W = ns.W

local Dialogs = {}
ns.Dialogs = Dialogs

function ns.SetFrameTitle(frame, text)
	if frame.SetTitle then
		frame:SetTitle(text)
	elseif frame.TitleContainer and frame.TitleContainer.TitleText then
		frame.TitleContainer.TitleText:SetText(text)
	end
end

---------------------------------------------------------------------------
-- Text dialog
---------------------------------------------------------------------------

function Dialogs:GetTextDialog()
	if self.textDialog then return self.textDialog end

	local dialog = CreateFrame("Frame", "ForeverFrameBuilderTextDialog", UIParent, "ButtonFrameTemplate")
	dialog:SetSize(640, 480)
	dialog:SetPoint("CENTER")
	dialog:SetFrameStrata("DIALOG")
	dialog:SetToplevel(true)
	dialog:SetMovable(true)
	dialog:SetClampedToScreen(true)
	dialog:EnableMouse(true)
	dialog:RegisterForDrag("LeftButton")
	dialog:SetScript("OnDragStart", dialog.StartMoving)
	dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
	ButtonFrameTemplate_HidePortrait(dialog)
	ButtonFrameTemplate_HideButtonBar(dialog)
	table.insert(UISpecialFrames, dialog:GetName())

	dialog.hint = W.Label(dialog, "", "GameFontHighlightSmall")
	dialog.hint:SetPoint("TOPLEFT", 14, -30)
	dialog.hint:SetPoint("RIGHT", -14, 0)
	dialog.hint:SetJustifyH("LEFT")

	local inset = dialog.Inset or W.Inset(dialog)
	inset:ClearAllPoints()
	inset:SetPoint("TOPLEFT", 10, -48)
	inset:SetPoint("BOTTOMRIGHT", -10, 36)
	inset:Show()

	local editor = CreateFrame("Frame", nil, inset, "ScrollingEditBoxTemplate")
	editor:SetPoint("TOPLEFT", 8, -6)
	editor:SetPoint("BOTTOMRIGHT", -26, 6)
	local scrollBar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", editor, "TOPRIGHT", 8, 0)
	scrollBar:SetPoint("BOTTOMLEFT", editor, "BOTTOMRIGHT", 8, 0)
	ScrollUtil.RegisterScrollBoxWithScrollBar(editor:GetScrollBox(), scrollBar)
	dialog.editor = editor

	local editBox = editor:GetEditBox()
	editBox:SetScript("OnTabPressed", function(self)
		self:Insert("\t")
	end)

	dialog.accept = W.Button(dialog, L["Save"], 100, function()
		local text = editor:GetInputText()
		if dialog.onAccept and dialog.onAccept(text) == false then
			return
		end
		dialog:Hide()
	end)
	dialog.accept:SetPoint("BOTTOMRIGHT", -10, 8)

	dialog.cancel = W.Button(dialog, CANCEL, 100, function()
		dialog:Hide()
	end)
	dialog.cancel:SetPoint("RIGHT", dialog.accept, "LEFT", -4, 0)

	dialog.selectAll = W.Button(dialog, L["Select all"], 100, function()
		editBox:SetFocus()
		editBox:HighlightText()
	end)
	dialog.selectAll:SetPoint("BOTTOMLEFT", 10, 8)

	dialog:Hide()
	self.textDialog = dialog
	return dialog
end

-- options: title, hint, text, acceptText (nil = read-only), onAccept(text) -> false keeps it open
function Dialogs:ShowText(options)
	local dialog = self:GetTextDialog()
	ns.SetFrameTitle(dialog, options.title or ns.title)
	dialog.hint:SetText(options.hint or "")
	dialog.onAccept = options.onAccept
	dialog.accept:SetShown(options.acceptText ~= nil)
	dialog.accept:SetText(options.acceptText or "")
	dialog.cancel:SetText(options.acceptText and CANCEL or CLOSE)
	dialog.editor:SetText(options.text or "")
	dialog:Show()
	dialog:Raise()
	local editBox = dialog.editor:GetEditBox()
	editBox:SetFocus()
	if options.selectAll then
		editBox:HighlightText()
	else
		editBox:SetCursorPosition(0)
	end
end

function Dialogs:SetHint(text)
	if self.textDialog then
		self.textDialog.hint:SetText(text)
	end
end

function Dialogs:EditScript(id, script)
	local node = Doc:Get(id)
	if not node then return end
	local signature = ("|cff80c0ffscript|r %s |cff888888function(%s)|r   %s"):format(
		script.name, script.args, L["Other elements: E.<Name>"])
	self:ShowText({
		title = node.name .. " – " .. script.name,
		hint = signature,
		text = node.scripts[script.name] or "",
		acceptText = L["Save"],
		onAccept = function(text)
			local _, err = loadstring("return function(" .. script.args .. ")\n" .. text .. "\nend", script.name)
			if err then
				self:SetHint("|cffff4040" .. err .. "|r")
				return false
			end
			Doc:SetScript(id, script.name, text)
		end,
	})
end

function Dialogs:ShowExportLua()
	self:ShowText({
		title = L["Export as Lua"],
		hint = L["Copy with Ctrl+C and paste it into your addon."],
		text = ns.Exporter:ToLua(),
		selectAll = true,
	})
end

function Dialogs:ShowExportString()
	local text, err = ns.Exporter:ToString()
	if not text then
		ns.Print(L["Export failed: %s"], err or "?")
		return
	end
	self:ShowText({
		title = L["Share project"],
		hint = L["Copy this string to import the project somewhere else."],
		text = text,
		selectAll = true,
	})
end

function Dialogs:ShowImport()
	self:ShowText({
		title = L["Import project"],
		hint = L["Paste a Frame Builder string and click Import."],
		text = "",
		acceptText = L["Import"],
		onAccept = function(text)
			local name, projectOrError = ns.Exporter:FromString(text)
			if not name then
				self:SetHint("|cffff4040" .. projectOrError .. "|r")
				return false
			end
			local newName = Doc:NewProject(name, projectOrError)
			ns.Print(L["Imported project \"%s\"."], newName)
			local scripts = ns.Exporter:CountScripts(projectOrError)
			if scripts > 0 then
				ns.Print(L["It contains %d script(s). Review them before using Preview."], scripts)
			end
		end,
	})
end

---------------------------------------------------------------------------
-- Template picker
---------------------------------------------------------------------------

local PICKER_ROW_HEIGHT = 18
local PICKER_MAX_ROWS = 300

function Dialogs:GetTemplatePicker()
	if self.picker then return self.picker end

	local picker = CreateFrame("Frame", "ForeverFrameBuilderTemplatePicker", UIParent, "ButtonFrameTemplate")
	picker:SetSize(460, 540)
	picker:SetPoint("CENTER")
	picker:SetFrameStrata("DIALOG")
	picker:SetToplevel(true)
	picker:SetMovable(true)
	picker:SetClampedToScreen(true)
	picker:EnableMouse(true)
	picker:RegisterForDrag("LeftButton")
	picker:SetScript("OnDragStart", picker.StartMoving)
	picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
	ButtonFrameTemplate_HidePortrait(picker)
	ButtonFrameTemplate_HideButtonBar(picker)
	ns.SetFrameTitle(picker, L["Blizzard templates"])
	table.insert(UISpecialFrames, picker:GetName())

	-- Recommended: the curated catalog; Shared: general-purpose addons; All: everything loaded.
	picker.view = "recommended"
	local viewFilter = W.Dropdown(picker, 120)
	viewFilter:SetPoint("TOPLEFT", 12, -28)
	viewFilter:SetupMenu(function(_, root)
		for _, view in ipairs({
			{ "recommended", L["Recommended"] }, { "shared", L["General"] }, { "all", L["All"] },
		}) do
			root:CreateRadio(view[2], function() return picker.view == view[1] end, function()
				picker.view = view[1]
				Dialogs:RefreshTemplatePicker()
			end)
		end
	end)
	picker.viewFilter = viewFilter

	local search = CreateFrame("EditBox", nil, picker, "SearchBoxTemplate")
	search:SetSize(160, 20)
	search:SetPoint("LEFT", viewFilter, "RIGHT", 10, 0)
	search:SetAutoFocus(false)
	search:HookScript("OnTextChanged", function()
		Dialogs:RefreshTemplatePicker()
	end)
	picker.search = search

	local typeFilter = W.Dropdown(picker, 120)
	typeFilter:SetPoint("LEFT", search, "RIGHT", 8, 0)
	typeFilter:SetupMenu(function(_, root)
		local types, seen = {}, {}
		for _, entry in ipairs(ns.TemplateList or {}) do
			if not seen[entry[2]] then
				seen[entry[2]] = true
				table.insert(types, entry[2])
			end
		end
		table.sort(types)
		root:CreateRadio(L["All types"], function() return picker.widget == nil end, function()
			picker.widget = nil
			Dialogs:RefreshTemplatePicker()
		end)
		for _, widget in ipairs(types) do
			root:CreateRadio(widget, function() return picker.widget == widget end, function()
				picker.widget = widget
				Dialogs:RefreshTemplatePicker()
			end)
		end
	end)
	picker.typeFilter = typeFilter

	local inset = picker.Inset or W.Inset(picker)
	inset:ClearAllPoints()
	inset:SetPoint("TOPLEFT", 10, -58)
	inset:SetPoint("BOTTOMRIGHT", -10, 28)
	inset:Show()
	local _, content = W.ScrollArea(inset)
	picker.content = content
	picker.rows = {}

	picker.count = W.Label(picker, "", "GameFontDisableSmall")
	picker.count:SetPoint("BOTTOMLEFT", 16, 10)

	picker:Hide()
	self.picker = picker
	return picker
end

local function CreatePickerRow(picker)
	local row = CreateFrame("Button", nil, picker.content)
	row:SetHeight(PICKER_ROW_HEIGHT)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.name:SetPoint("LEFT", 6, 0)
	row.name:SetPoint("RIGHT", -110, 0)
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
	row.widget = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	row.widget:SetPoint("RIGHT", -6, 0)
	row:SetScript("OnClick", function(self)
		if not self.entry then return end
		picker:Hide()
		if picker.onPick then
			picker.onPick(self.entry, self.catalog)
		end
	end)
	row:SetScript("OnEnter", function(self)
		local entry, catalog = self.entry, self.catalog
		if not entry then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(entry[1], 1, 1, 1)
		if catalog then
			GameTooltip:AddLine(ns.CatalogNote(catalog), 1, 0.82, 0, true)
		end
		GameTooltip:AddLine(entry[2] .. "  •  " .. entry[3], 0.7, 0.7, 0.7)
		if entry[4] > 0 or entry[5] > 0 then
			GameTooltip:AddLine(L["Default size: %d x %d"]:format(entry[4], entry[5]), 0.7, 0.7, 0.7)
		end
		if entry[7] then
			GameTooltip:AddLine(L["Not usable on its own: its OnLoad/OnShow expects %s from a derived template or a specific parent frame."]:format(entry[7]), 1, 0.3, 0.3, true)
		elseif entry[8] then
			GameTooltip:AddLine(L["Uses self:GetName(): it gets a global name automatically (also in the export)."], 1, 0.82, 0, true)
		end
		if catalog and catalog[6] then
			GameTooltip:AddLine(L["Tip: the element \"%s\" covers this template with more options."]:format(
				ns.Elements[catalog[6]].label), 0.4, 1, 0.4, true)
		end
		if catalog and catalog[5] then
			GameTooltip:AddLine(" ")
			GameTooltip:AddLine(L["Adds this OnLoad code:"], 0.7, 0.7, 0.7)
			GameTooltip:AddLine(catalog[5], 0.6, 0.8, 1, true)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

-- Entries of the current view as { entry, catalog } or { header = text }.
local function PickerEntries(picker, query)
	local list = {}
	local function Matches(entry, catalog)
		if picker.widget and entry[2] ~= picker.widget then return false end
		if query == "" then return true end
		return entry[1]:lower():find(query, 1, true) or entry[3]:lower():find(query, 1, true)
			or (catalog and ns.CatalogNote(catalog):lower():find(query, 1, true))
	end
	if picker.view == "recommended" then
		for _, category in ipairs(ns.CatalogCategories) do
			local header = { header = ns.CatalogCategoryName(category.key) }
			local added = false
			for _, catalog in ipairs(ns.Catalog) do
				local entry = catalog[2] == category.key and ns.GetTemplateInfo(catalog[1])
				if entry and Matches(entry, catalog) then
					if not added then
						table.insert(list, header)
						added = true
					end
					table.insert(list, { entry = entry, catalog = catalog })
				end
			end
		end
	else
		for _, entry in ipairs(ns.TemplateList or {}) do
			if (picker.view == "all" or entry[6]) and Matches(entry, ns.GetCatalogEntry(entry[1])) then
				table.insert(list, { entry = entry, catalog = ns.GetCatalogEntry(entry[1]) })
			end
		end
	end
	return list
end

function Dialogs:RefreshTemplatePicker()
	local picker = self.picker
	if not picker then return end
	local query = strtrim(picker.search:GetText() or ""):lower()
	local shown, total = 0, 0
	for _, item in ipairs(PickerEntries(picker, query)) do
		if not item.header then
			total = total + 1
		end
		if shown < PICKER_MAX_ROWS then
			shown = shown + 1
			local row = picker.rows[shown]
			if not row then
				row = CreatePickerRow(picker)
				row:SetPoint("TOPLEFT", picker.content, "TOPLEFT", 0, -(shown - 1) * PICKER_ROW_HEIGHT)
				row:SetPoint("RIGHT", picker.content, "RIGHT")
				picker.rows[shown] = row
			end
			row.entry, row.catalog = item.entry, item.catalog
			if item.header then
				row.name:SetFontObject(GameFontNormal)
				row.name:SetText(item.header)
				row.widget:SetText("")
				row:EnableMouse(false)
			else
				row.name:SetFontObject(GameFontHighlightSmall)
				-- Gear icon: comes with setup code; gold asterisk: recommended (outside the recommended view).
				local mark = ""
				if item.catalog and item.catalog[5] then
					mark = " |A:questlog-icon-setting:12:12|a"
				elseif item.catalog and picker.view ~= "recommended" then
					mark = " |cffffd100*|r"
				end
				if item.entry[7] then
					mark = " |cffff4040(!)|r"
				end
				row.name:SetText((picker.view == "recommended" and "   " or "") .. item.entry[1] .. mark)
				row.widget:SetText(item.catalog and item.catalog[6] and ("» " .. ns.Elements[item.catalog[6]].label) or item.entry[2])
				row:EnableMouse(true)
			end
			row:Show()
		end
	end
	for i = shown + 1, #picker.rows do
		picker.rows[i]:Hide()
	end
	picker.content:SetHeight(math.max(1, shown * PICKER_ROW_HEIGHT))
	picker.typeFilter:OverrideText(picker.widget or L["All types"])
	local viewNames = { recommended = L["Recommended"], shared = L["General"], all = L["All"] }
	picker.viewFilter:OverrideText(viewNames[picker.view])
	if total > shown then
		picker.count:SetText(L["%d of %d shown – refine the search"]:format(shown, total))
	else
		picker.count:SetText(L["%d templates"]:format(total))
	end
end

-- onPick(entry) receives { name, widget, addon, width, height } from Data\Templates.lua.
function Dialogs:PickTemplate(onPick)
	local picker = self:GetTemplatePicker()
	picker.onPick = onPick
	picker:Show()
	picker:Raise()
	self:RefreshTemplatePicker()
	picker.search:SetFocus()
end

---------------------------------------------------------------------------
-- Prompts
---------------------------------------------------------------------------

local function PopupEditBox(dialog)
	return dialog.GetEditBox and dialog:GetEditBox() or dialog.editBox
end

StaticPopupDialogs["FOREVERFRAMEBUILDER_PROMPT"] = {
	text = "%s",
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = 60,
	OnShow = function(dialog, data)
		local editBox = PopupEditBox(dialog)
		editBox:SetText(data.default or "")
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	OnAccept = function(dialog, data)
		data.callback(PopupEditBox(dialog):GetText())
	end,
	EditBoxOnEnterPressed = function(editBox, data)
		data.callback(editBox:GetText())
		editBox:GetParent():Hide()
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

StaticPopupDialogs["FOREVERFRAMEBUILDER_CONFIRM"] = {
	text = "%s",
	button1 = YES,
	button2 = NO,
	OnAccept = function(_, data)
		data.callback()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	showAlert = true,
	preferredIndex = 3,
}

function Dialogs:Prompt(text, default, callback)
	StaticPopup_Show("FOREVERFRAMEBUILDER_PROMPT", text, nil, { default = default, callback = callback })
end

function Dialogs:Confirm(text, callback)
	StaticPopup_Show("FOREVERFRAMEBUILDER_CONFIRM", text, nil, { callback = callback })
end
