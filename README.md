# Forever Frame Builder

*[Deutsche Version](README.de.md)*

A drag & drop editor for in-game frames in **World of Warcraft: Forever**, similar to a website builder. Design windows,
tabs, buttons, dropdowns and more directly in the game, try them out in a live preview and export them as plain Lua
code for your own addon.

## Installation

Copy the `ForeverFrameBuilder` folder into `World of Warcraft/_classic_beta_/Interface/AddOns/` and enable the addon.

Open the editor with `/ffb` (or `/framebuilder`, or through the addon compartment on the minimap).
`/ffb reset` resets the window position.

## The editor window

| Area | Purpose |
|---|---|
| Toolbar | Projects, undo/redo, grid/snap, zoom, errors, export, preview |
| Elements (tab, left) | Palette in foldable groups (containers, controls, display, Blizzard templates): click adds to the selected frame, drag places it at the cursor |
| Layers (tab, left) | Tree of all elements; order = draw order (lower = in front). Elements with children fold with +/- (hidden count shown); "Expand all"/"Collapse all" in the right-click menu |
| Canvas | Represents `UIParent` (the blue outline is your screen) |
| Properties | Name, parent, anchors, size, appearance and scripts of the selected element, in collapsible sections (remembered) |

## Controls

- **Move:** drag. Shift+drag moves the current selection even if it is covered by other elements.
- **Nest:** hold Ctrl when releasing to drop the element into the frame under the cursor (highlighted in green).
  Alternatively use "Move into" in the right-click menu or "Parent" in the properties.
- **Resize:** drag the blue handles. The opposite edge stays in place, whatever anchor is set.
- **Change anchors:** the element stays where it is; the offsets are recalculated.
- **View:** middle mouse button or Alt+drag pans, the mouse wheel zooms towards the cursor.
- **Keys:** arrows nudge (Shift: one grid step), Del, Ctrl+Z/Y, Ctrl+C/V, Ctrl+D, Esc clears the selection.
- **Number fields:** the mouse wheel changes the value (Shift: ×10).

## Elements

Frame (with backdrop), Window, Tabs, Collapsible section, Scroll frame, Button, Checkbox, Input box, Dropdown, Slider,
Status bar, Texture, Text (FontString), 3D model and **Template** (any Blizzard template).

**Fill parent** (under Layout) anchors an element to all edges of its parent (`SetAllPoints`). Such elements are not
moved on their own: dragging them moves the parent.

### Anchor points

The Layout section is split into foldable categories like the AddOn list: **General** (fill parent, width, height,
alpha, shown, strata) followed by one category per anchor point, whose title summarizes it (e.g. `TOPLEFT » Frame1`).

Every element starts with one anchor point. Under Layout, **Add anchor point** adds more (e.g. `TOPLEFT` and
`BOTTOMRIGHT`, so the element stretches with whatever it is anchored to); **Remove** deletes an additional one. Each
anchor has its own point, relative point, offsets and **Relative to** target: the parent or any other element, such as
a sibling button. Targets that would create an anchor loop are not offered.

Changing a point, relative point or target keeps the element where it is and recalculates the offsets. Moving,
resizing and the arrow keys move all anchors together; with anchors on opposite edges the anchors, not the width/height
fields, decide the size on that axis. Deleting an element re-anchors everything attached to it to its parent in place.
In the export, anchors to elements that are created further down are set in a separate block once all elements exist.

### Window

Blizzard window templates with title, close button, portrait and button bar (depending on the style):
`ButtonFrameTemplate`, `PortraitFrameTemplate`, `BasicFrameTemplate(WithInset)`, `DefaultPanel(Flat)Template`,
`UIPanelDialogTemplate`, `SimplePanelTemplate`, `InsetFrameTemplate`, `DialogBorder(Dark)Template`.

### Tabs

A tab container using `PanelTabButtonTemplate` (bottom), `PanelTopTabButtonTemplate` (top) or
`LargeSideTabButtonTemplate` (side: icon tabs along the right edge, as in the Forever collections journal; there the
tab names become tooltips and the icons go into the "Icons" field, also separated by `;`).

Tab names are entered in one field, separated by `;`. Every direct child is a page (child 1 = tab 1, …); a new
container gets one empty page per tab that fills its parent. In the editor, clicking a tab switches the page, and
selecting an element on a hidden page activates its tab. The export contains `E.<Name>:SelectTab(index)` and
`E.<Name>.Pages`; the script `OnTabSelected(self, index)` is called on every change.

### Collapsible section

A list header (`ListHeaderVisualTemplate`) with a +/- button. Its children are the section content and are hidden
while it is collapsed; a new section gets an empty content frame below the header. In the editor a click on +/-
toggles it, in the preview a click on the whole header. Export: `E.<Name>:SetCollapsed(true/false)`, script
`OnToggle(self, collapsed)`. Elements below the section do **not** move up automatically when it collapses.

### Dropdown

Covers every dropdown of the modern menu system that works on its own: `WowStyle1DropdownTemplate` (standard),
`WowStyle2DropdownTemplate` (settings style), `WowStyle1FilterDropdownTemplate` (filter button),
`WowStyle1ArrowDropdownTemplate`, `UIPanelIconDropdownButtonTemplate` (gear) and `UIPanelArrowDropdownButtonTemplate`.

Entries are entered in one field, separated by `;` (`-` = divider, `#Text` = title). Modes: single choice (radio),
multiple choice (checkboxes) or actions (buttons). Single choice can get arrow steppers on both sides. Script
`OnSelect(self, index, text, checked)`; `index` counts real entries only. Export: `SetupMenu` with `E.<Name>.Selected`.

### Template

Creates a widget from any Blizzard template. The "…" button opens a searchable list of every template the client
loads at login; widget type and default size are taken over, including sizes a template only sets in its `OnLoad`.
List headers get their text through `SetHeaderText`.

- **Recommended** shows the curated catalog (see [TEMPLATES.md](TEMPLATES.md), German) by category, with a
  description and, where needed, setup code that is entered as `OnLoad`. "Run OnLoad in editor" also runs this code on
  the canvas, so that e.g. sliders already look initialized.
- **General** shows all templates of the shared Blizzard addons, **All** every loaded template.
- Templates marked with a red **(!)** only work through a derived template or under a specific parent (their
  `OnLoad`/`OnShow` expects keys such as `fontName`, child frames such as `.Dropdown` or methods of their parent).
  They, and templates whose `OnLoad` or `OnShow` fails, are created as a red placeholder instead of raising Lua errors
  (every new template is shown once on an invisible frame to catch `OnShow` errors).
- Every template widget gets a unique global name in the editor, since many older templates build child names from
  `self:GetName()`. In the export, templates that need one get `<Project>_<Name>` unless you set a global name.

The list (`Data/Templates.lua`) is generated from the Blizzard UI source with
`python3 Tools/build_templates.py [/path/to/wow-ui-source]`. The script evaluates the TOC files the way the Forever
client does (game type `camelot`, `[Family]` = Mainline, `[Game]` = Camelot, per-line conditions, XML `<Include>`s,
without load-on-demand and login screen addons).

### Scroll frame

A `ScrollFrame` with a content frame (`E.<Name>.Content`) as scroll child. Elements you drag into it end up in the
content and are anchored to it. The content height is set in the properties; the content width follows the frame
width as long as it is 0.

In the editor, **Ctrl+mouse wheel** over the frame scrolls its content (or use "Scroll position (editor)"), so you can
reach elements further down. Elements outside the visible area cannot be clicked on the canvas, but they can be
selected in the layer list. With "Scroll bar" the export uses `ScrollFrameTemplate` with its bar to the right of the
frame; without it, a plain scroll frame with mouse wheel scrolling.

## Scripts and preview

Every element has script slots (`OnLoad`, `OnClick`, `OnValueChanged`, …). Inside a script `self` is the element;
other elements are reachable through `E.<Name>`, e.g. `E.MainFrame:Hide()`. **Preview** makes everything live:
buttons can be clicked, scripts run and movable frames can be dragged. "Edit mode" restores the design.

The script editor is a code editor: Lua syntax highlighting (keywords, strings, comments, numbers, function calls,
`self`/`E`/`true`/`false`/`nil`), line numbers, a live syntax check that shows "Syntax OK" or the error with its line
(the line number is marked red), Tab inserts four spaces and Enter keeps the indentation (one level more after `then`, `do`,
`function`, `repeat`, `{`). Scripts with syntax errors can't be saved. Like *For All Indents And Purposes*, the colors
are written into the edit box text once typing pauses (0.2 s); "Select all" switches to the uncolored code so Ctrl+C copies exactly the code
(typing colors it again). The Lua export view stays uncolored for copying.

## Export

- **Lua code:** standalone code (`CreateFrame` …) you can paste straight into an addon. All elements are stored in
  the table `E`.
- **Share string / import:** the whole project as a string (uses `C_EncodingUtil`). Review imported scripts before
  using the preview!

Projects are saved in `ForeverFrameBuilderDB` (SavedVariables).

## Errors

The **Errors** button opens a log of errors that happened in the editor: templates that could not be created,
failing `OnLoad`/`OnShow`, properties that could not be applied, script errors in the preview or editor, and Lua
errors from the addon or during the preview (those are still passed on to the default error handler / BugSack).
The button shows the number of entries in red. Each entry has a copyable report with time, client and addon version,
project, element, template (widget type, addon, markers, catalog setup code), message, stack, layout, properties, the
element's scripts and all other scripts of the project. Identical errors are merged and counted; the last 50 entries
are kept across reloads.

## Limitations

- Frames cannot be destroyed in WoW. The editor reuses them; only widgets that received script hooks in the preview
  are discarded.
- An element's strata is only exported, it is not applied on the canvas.
- 3D models partly ignore the canvas clipping.

## Localization

English and German (`Locales/`). The German file only overrides what it translates.
