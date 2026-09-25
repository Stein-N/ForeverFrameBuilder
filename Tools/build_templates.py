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
FAMILY = "Mainline"
GAME = "Camelot"

# Widget types CreateFrame can build and that make sense on the canvas.
WIDGETS = {
    "Frame", "Button", "CheckButton", "EditBox", "EventEditBox", "Slider", "StatusBar",
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


def condition_allows(text):
    """Evaluates the [..] conditions of a TOC line for this client."""
    for kind, value in re.findall(r"\[(\w+)\s*([^\]]*)\]", text):
        values = [v.strip().lower() for v in value.split(",") if v.strip()]
        kind = kind.lower()
        if kind == "allowloadgametype" and GAME_TYPE not in values:
            return False
        if kind == "excludeloadgametype" and GAME_TYPE in values:
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
    if game_types and GAME_TYPE not in [v.strip().lower() for v in game_types.split(",")]:
        return False
    excluded = headers.get("excludeloadgametype")
    if excluded and GAME_TYPE in [v.strip().lower() for v in excluded.split(",")]:
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


def main():
    with open(os.path.join(SOURCE, "Interface", "ui-toc-list.txt"), encoding="utf-8") as f:
        tocs = [line.strip() for line in f if line.strip()]

    templates, info, seen = {}, {}, set()
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
                    if not template or element.get("virtual") != "true":
                        continue
                    inherits = [t.strip() for t in (element.get("inherits") or "").split(",") if t.strip()]
                    mixins = [m.strip() for m in (element.get("mixin") or "").split(",") if m.strip()]
                    keyvalues = {kv.get("key") for kv in element.iter() if kv.tag.split("}")[-1] == "KeyValue"}
                    # Children and regions reachable as self.<parentKey>.
                    keyvalues |= {sub.get("parentKey") for sub in element.iter() if sub.get("parentKey")}
                    info[template] = (size_of(element), inherits, mixins, keyvalues)
                    if tag not in WIDGETS or element.get("intrinsic") == "true" or template.startswith("$"):
                        templates.pop(template, None)
                        continue
                    templates[template] = (template, tag, addon)

    # Keys the OnLoad of a mixin asserts, e.g. ScrollingFontMixin needs self.fontName.
    # Such templates only work through a derived template that sets the key as KeyValue.
    onload_asserts = {}
    all_lua = "\n".join(lua_sources)
    # Also child frames the OnLoad calls into (self.Dropdown:RegisterCallback(...)) without
    # creating them first; capitalised keys are the convention for child frames.
    mixin_methods = {}
    for match in re.finditer(r"^function (\w+):(\w+)\(", all_lua, re.M):
        mixin_methods.setdefault(match.group(1), set()).add(match.group(2))
    for match in re.finditer(r"^function (\w+):OnLoad\(\)(.*?)^end", all_lua, re.M | re.S):
        body = match.group(2)
        keys = set(re.findall(r"assert\(\s*self\.(\w+)\s*\)", body))
        assigned = set(re.findall(r"self\.(\w+)\s*=[^=]", body))
        # Only unconditional accesses count: lines directly in the function body (one tab deep).
        for line in body.splitlines():
            if not re.match(r"^\t\S", line):
                continue
            for key in re.findall(r"self\.([A-Z]\w*)\s*:", line):
                if key not in assigned and key not in mixin_methods.get(match.group(1), set()):
                    keys.add(key)
        if keys:
            onload_asserts.setdefault(match.group(1), set()).update(keys)

    def chain(name, depth=0):
        entry = info.get(name)
        if not entry or depth > 20:
            return []
        result = [entry]
        for parent in entry[1]:
            result += chain(parent, depth + 1)
        return result

    def missing_keys(name):
        entries = chain(name)
        needed, provided = set(), set()
        for _, _, mixins, keyvalues in entries:
            provided |= keyvalues
            for mixin in mixins:
                needed |= onload_asserts.get(mixin, set())
        return sorted(needed - provided)

    def resolve_size(name, depth=0):
        entry = info.get(name)
        if not entry or depth > 20:
            return 0, 0
        (w, h), inherits = entry[0], entry[1]
        for parent in inherits:
            pw, ph = resolve_size(parent, depth + 1)
            w, h = w or pw, h or ph
        return w, h

    lines = [
        "-- Forever Frame Builder",
        "-- Generated by Tools/build_templates.py - do not edit by hand.",
        "-- { template, widget type, addon, default width, default height, shared, needs }",
        "-- shared = true for general-purpose templates (SharedXML, Menu, UIPanelTemplates, ...).",
        "-- needs = keys its OnLoad asserts but no KeyValue provides: only usable through a derived template.",
        "",
        "local _, ns = ...",
        "",
        "ns.TemplateList = {",
    ]
    for name in sorted(templates, key=str.lower):
        template, tag, addon = templates[name]
        w, h = resolve_size(name)
        shared = "true" if addon in SHARED_ADDONS else "false"
        needs = missing_keys(name)
        needs = ('"%s"' % ", ".join(needs)) if needs else "nil"
        lines.append('\t{ "%s", "%s", "%s", %d, %d, %s, %s },' % (template, tag, addon, w, h, shared, needs))
    lines.append("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print("%d addons load at login, wrote %d templates to %s" % (loaded_addons, len(templates), os.path.normpath(OUT)))


if __name__ == "__main__":
    main()
