#!/usr/bin/env python3
"""Generates Data/Templates.lua from a wow-ui-source checkout.

The repository contains the files of every flavor, so the TOC files are evaluated the way
the WoW: Forever client does: game type "camelot", [Family] = Mainline, [Game] = Camelot.
Per-line conditions ([AllowLoadGameType], [ExcludeLoadGameType], [AllowLoadTextLocale]),
load-on-demand and login-screen-only addons and XML <Include>s are honoured, and a template
defined twice keeps its last definition in load order, like in the client.

Usage: python3 Tools/build_templates.py [/path/to/wow-ui-source]
"""
import os
import re
import sys
import xml.etree.ElementTree as ET

SOURCE = sys.argv[1] if len(sys.argv) > 1 else "/home/nico/Projekte/wow-ui-source"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Data", "Templates.lua")

GAME_TYPE = "camelot"
# Names a TOC condition can use for this client: its own game type and its family group.
# "mainline" covers every Mainline-family game type (camelot included), just like
# "classic" covers vanilla to mists; that is why files use [ExcludeLoadGameType camelot].
GAME_TYPE_NAMES = {GAME_TYPE, "mainline"}
FAMILY = "Mainline"
GAME = "Camelot"

# Widget types CreateFrame can build and that make sense on the canvas.
WIDGETS = {
    "Frame", "Button", "CheckButton", "EditBox", "EventEditBox", "Slider", "StatusBar", "ItemButton",
    "ScrollFrame", "EventFrame", "EventButton", "DropdownButton", "Cooldown", "PlayerModel",
    "Model", "DressUpModel", "ModelScene", "SimpleHTML", "MessageFrame", "ScrollingMessageFrame",
    "ColorSelect",
}

# Addons whose templates are general-purpose building blocks.
SHARED_ADDONS = {
    "Blizzard_SharedXML", "Blizzard_SharedXMLBase", "Blizzard_SharedXMLGame", "Blizzard_UIPanelTemplates",
    "Blizzard_Menu", "Blizzard_MoneyFrame", "Blizzard_FrameXML", "Blizzard_FrameXMLBase",
}

AddOnsDir = os.path.join(SOURCE, "Interface", "AddOns")


def matches_game_type(values):
    return any(v.strip().lower() in GAME_TYPE_NAMES for v in values)


def condition_allows(text):
    """Evaluates the [..] conditions of a TOC line for this client."""
    for kind, value in re.findall(r"\[(\w+)\s*([^\]]*)\]", text):
        values = [v.strip().lower() for v in value.split(",") if v.strip()]
        kind = kind.lower()
        if kind == "allowloadgametype" and not matches_game_type(values):
            return False
        if kind == "excludeloadgametype" and matches_game_type(values):
            return False
        if kind == "allowloadtextlocale":
            return False
    return True


def resolve(base, relative):
    """Case-insensitive path lookup (the source uses Windows paths)."""
    path = base
    for part in relative.replace("\\", "/").split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            path = os.path.dirname(path)
            continue
        candidate = os.path.join(path, part)
        if not os.path.exists(candidate) and os.path.isdir(path):
            lower = part.lower()
            for entry in os.listdir(path):
                if entry.lower() == lower:
                    candidate = os.path.join(path, entry)
                    break
        path = candidate
    return path if os.path.exists(path) else None


def parse_toc(path):
    headers, files = {}, []
    with open(path, encoding="utf-8-sig") as f:
        for line in f:
            line = line.rstrip("\n")
            if line.startswith("##"):
                match = re.match(r"##\s*([\w-]+)\s*:\s*(.*)", line)
                if match:
                    value = match.group(2)
                    if condition_allows(value):
                        headers[match.group(1).lower()] = re.sub(r"\[.*?\]", "", value).strip()
                continue
            if not line.strip() or line.startswith("#"):
                continue
            if not condition_allows(line):
                continue
            name = re.sub(r"\s*\[(?!Family\]|Game\])[^\]]*\]", "", line).strip()
            name = name.replace("[Family]", FAMILY).replace("[Game]", GAME)
            files.append(name)
    return headers, files


def addon_loads(headers):
    if headers.get("loadondemand", "0").strip() == "1":
        return False
    if headers.get("allowload", "").strip().lower() == "glue":
        return False
    game_types = headers.get("allowloadgametype")
    if game_types and not matches_game_type(game_types.split(",")):
        return False
    excluded = headers.get("excludeloadgametype")
    if excluded and matches_game_type(excluded.split(",")):
        return False
    return True


def xml_files(path, seen):
    """Yields an XML file and, depth-first in document order, the files it includes."""
    if path in seen:
        return
    seen.add(path)
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError):
        return
    yield path, root
    for element in root:
        if element.tag.split("}")[-1] == "Include" and element.get("file"):
            included = resolve(os.path.dirname(path), element.get("file"))
            if included:
                yield from xml_files(included, seen)


def size_of(element):
    for child in element:
        if child.tag.split("}")[-1] == "Size":
            try:
                return int(float(child.get("x", 0))), int(float(child.get("y", 0)))
            except ValueError:
                pass
    return 0, 0


def api_function_names(root):
    """Names of all documented widget/API functions (to tell them from custom methods)."""
    names = set()
    folder = os.path.join(root, "Interface", "AddOns", "Blizzard_APIDocumentationGenerated")
    for entry in os.listdir(folder):
        text = open(os.path.join(folder, entry), encoding="utf-8", errors="replace").read()
        names |= set(re.findall(r'Name = "(\w+)",\s*\n\s*Type = "Function"', text))
    return names


class HandlerAnalysis:
    """Static checks of the OnLoad/OnShow handlers a template runs when it is created or shown.

    Handlers are collected over the whole inheritance chain (mixin methods, function="..."
    handlers and inline scripts) and followed two calls deep (self:Method(), Mixin.Method(self),
    Global(self)). Only unconditional lines (directly in the function body) are inspected.
    """

    SCRIPTS = ("OnLoad", "OnShow")

    def __init__(self, lua, api_names):
        self.api = api_names
        self.methods, self.functions, self.mixin_parents = {}, {}, {}
        for m in re.finditer(r"^function (\w+)[:.](\w+)\(([^)]*)\)(.*?)^end", lua, re.M | re.S):
            self.methods[(m.group(1), m.group(2))] = m.group(4)
        for m in re.finditer(r"^function (\w+)\(([^)]*)\)(.*?)^end", lua, re.M | re.S):
            first = m.group(2).split(",")[0].strip()
            body = m.group(3)
            if first and first != "self":
                body = re.sub(r"\b%s\b" % re.escape(first), "self", body)
            self.functions[m.group(1)] = body
        for m in re.finditer(r"^(\w+)\s*=\s*CreateFromMixins\(([^)]*)\)", lua, re.M):
            self.mixin_parents[m.group(1)] = [x.strip() for x in m.group(2).split(",") if x.strip()]

    def expand(self, mixins, depth=0):
        result = []
        for mixin in mixins:
            result.append(mixin)
            if depth < 6:
                result += self.expand(self.mixin_parents.get(mixin, []), depth + 1)
        return result

    def method(self, mixins, name):
        for mixin in mixins:
            if (mixin, name) in self.methods:
                return self.methods[(mixin, name)]

    def bodies(self, entries):
        mixins = self.expand([m for entry in entries for m in entry[2]])
        found = []
        for entry in entries:
            for scripts in entry[4]:
                if scripts.tag.split("}")[-1] != "Scripts":
                    continue
                for handler in scripts:
                    if handler.tag.split("}")[-1] not in self.SCRIPTS:
                        continue
                    if handler.get("method"):
                        body = self.method(mixins, handler.get("method"))
                    elif handler.get("function"):
                        body = self.functions.get(handler.get("function"))
                    else:
                        text = (handler.text or "").strip()
                        body = ("\n\t" + "\n\t".join(text.splitlines())) if text else None
                    if body:
                        found.append(body)
        # Follow calls made from those handlers.
        frontier = list(found)
        for _ in range(2):
            called = []
            for body in frontier:
                for line in self.unconditional(body):
                    for name in re.findall(r"self:(\w+)\(", line):
                        body2 = self.method(mixins, name)
                        if body2:
                            called.append(body2)
                    for mixin, name in re.findall(r"(\w+)\.(\w+)\(self\b", line):
                        if (mixin, name) in self.methods:
                            called.append(self.methods[(mixin, name)])
                    for name in re.findall(r"(?<![:.\w])(\w+)\(self\b", line):
                        if name in self.functions:
                            called.append(self.functions[name])
            found += called
            frontier = called
        return found, mixins

    @staticmethod
    def unconditional(body):
        return [line for line in body.splitlines() if re.match(r"^\t\S", line)]

    def check(self, entries):
        provided = set()
        for entry in entries:
            provided |= entry[3]
        bodies, mixins = self.bodies(entries)
        custom = {name for (mixin, name) in self.methods if mixin in mixins}
        assigned = set()
        for body in bodies:
            assigned |= set(re.findall(r"self\.(\w+)\s*=[^=]", body))
        needs, needs_name = set(), False
        for body in bodies:
            needs |= set(re.findall(r"assert\(\s*self\.(\w+)\s*\)", body)) - provided - assigned
            for line in self.unconditional(body):
                # Child frames used before anyone created them (capitalised by convention).
                for key in re.findall(r"self\.([A-Z]\w*)\s*:", line):
                    if key not in provided and key not in assigned and key not in custom:
                        needs.add(key)
                # Methods only a specific parent frame has, or parent fields used further.
                for name in re.findall(r"self:GetParent\(\):(\w+)\(", line):
                    if name not in self.api:
                        needs.add("parent:" + name)
                for key in re.findall(r"self:GetParent\(\)\.(\w+)\s*[:.\[]", line):
                    needs.add("parent." + key)
                if re.search(r"self:GetName\(\)", line):
                    needs_name = True
        return sorted(needs), needs_name


def main():
    with open(os.path.join(SOURCE, "Interface", "ui-toc-list.txt"), encoding="utf-8") as f:
        tocs = [line.strip() for line in f if line.strip()]

    templates, info, intrinsics, seen = {}, {}, {}, set()
    lua_sources = []
    loaded_addons = 0
    for toc in tocs:
        toc_path = resolve(SOURCE, toc)
        if not toc_path:
            continue
        headers, files = parse_toc(toc_path)
        if not addon_loads(headers):
            continue
        loaded_addons += 1
        addon = os.path.basename(os.path.dirname(toc_path))
        for name in files:
            path = resolve(os.path.dirname(toc_path), name)
            if not path:
                continue
            if name.lower().endswith(".lua"):
                try:
                    lua_sources.append(open(path, encoding="utf-8", errors="replace").read())
                except OSError:
                    pass
                continue
            if not name.lower().endswith(".xml"):
                continue
            for _, root in xml_files(path, seen):
                for element in root:
                    tag = element.tag.split("}")[-1]
                    template = element.get("name")
                    intrinsic = element.get("intrinsic") == "true"
                    if not template or (element.get("virtual") != "true" and not intrinsic):
                        continue
                    inherits = [t.strip() for t in (element.get("inherits") or "").split(",") if t.strip()]
                    mixins = [m.strip() for m in (element.get("mixin") or "").split(",") if m.strip()]
                    keyvalues = {kv.get("key") for kv in element.iter() if kv.tag.split("}")[-1] == "KeyValue"}
                    # Children and regions reachable as self.<parentKey>.
                    keyvalues |= {sub.get("parentKey") for sub in element.iter() if sub.get("parentKey")}
                    info[template] = (size_of(element), inherits, mixins, keyvalues, element, tag)
                    if intrinsic:
                        # Intrinsic widget types (ItemButton, EventFrame, ...) act as the base of
                        # every template declared with their tag.
                        intrinsics[template] = info[template]
                    if tag not in WIDGETS or intrinsic or template.startswith("$"):
                        templates.pop(template, None)
                        continue
                    templates[template] = (template, tag, addon)

    analysis = HandlerAnalysis("\n".join(lua_sources), api_function_names(SOURCE))

    def bases(entry):
        """Inherited templates, then the intrinsic widget type the template is declared with."""
        names = list(entry[1])
        tag = entry[5]
        if tag in intrinsics and intrinsics[tag] is not entry:
            names.append(tag)
        return names

    def chain(name, depth=0):
        entry = info.get(name)
        if not entry or depth > 20:
            return []
        result = [entry]
        for parent in bases(entry):
            result += chain(parent, depth + 1)
        return result

    def resolve_size(name, depth=0):
        entry = info.get(name)
        if not entry or depth > 20:
            return 0, 0
        w, h = entry[0]
        for parent in bases(entry):
            pw, ph = resolve_size(parent, depth + 1)
            w, h = w or pw, h or ph
        return w, h

    lines = [
        "-- Forever Frame Builder",
        "-- Generated by Tools/build_templates.py - do not edit by hand.",
        "-- { template, widget type, addon, default width, default height, shared, needs, needsName }",
        "-- shared = true for general-purpose templates (SharedXML, Menu, UIPanelTemplates, ...).",
        "-- needs = what its OnLoad/OnShow expects from a derived template or a specific parent",
        "--         (asserted keys, child frames, parent methods): not usable on its own.",
        "-- needsName = its OnLoad/OnShow builds names from self:GetName(): needs a global name.",
        "",
        "local _, ns = ...",
        "",
        "ns.TemplateList = {",
    ]
    for name in sorted(templates, key=str.lower):
        template, tag, addon = templates[name]
        w, h = resolve_size(name)
        shared = "true" if addon in SHARED_ADDONS else "false"
        needs, needs_name = analysis.check(chain(name))
        needs = ('"%s"' % ", ".join(needs)) if needs else "nil"
        needs_name = "true" if needs_name else "false"
        lines.append('\t{ "%s", "%s", "%s", %d, %d, %s, %s, %s },' % (template, tag, addon, w, h, shared, needs, needs_name))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("%d addons load at login, wrote %d templates to %s" % (loaded_addons, len(templates), os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
