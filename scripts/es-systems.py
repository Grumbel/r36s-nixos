#!/usr/bin/env python3
"""Generate an ES-DE es_systems.xml that only lists what is installed.

ES-DE's bundled es_systems.xml knows ~200 systems with ~20 emulators
each. Keep only the RetroArch commands whose core is installed, with the
RetroArch and core paths filled in, and drop systems that end up without
any command. The output starts with <loadExclusive/>, so ES-DE ignores
its bundled file.

Usage: es-systems.py BUNDLED_XML CORES_DIR RETROARCH PREFERRED_CORES OUT
PREFERRED_CORES is a comma separated list of core names (e.g.
"gpsp,picodrive"); a system's commands using these cores come first, as
the first command is ES-DE's default emulator.
"""

import os
import re
import sys
import xml.etree.ElementTree as ET

CORE_RE = re.compile(r"^%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/(\w+)_libretro\.so (.*)$")


def main():
    bundled, cores_dir, retroarch, preferred, out = sys.argv[1:]
    preferred = [c for c in preferred.split(",") if c]
    installed = {
        f.removesuffix("_libretro.so")
        for f in os.listdir(cores_dir)
        if f.endswith("_libretro.so")
    }

    tree = ET.parse(bundled)
    root = tree.getroot()
    result = ET.Element("systemList")

    for system in root.findall("system"):
        commands = []
        for command in system.findall("command"):
            m = CORE_RE.match(command.text.strip())
            if m and m.group(1) in installed:
                core, args = m.groups()
                command.text = f"{retroarch} -L {cores_dir}/{core}_libretro.so {args}"
                commands.append((core, command))
        if not commands:
            continue

        def rank(item):
            core = item[0]
            return preferred.index(core) if core in preferred else len(preferred)

        # sorted() is stable, the bundled order is kept otherwise
        commands.sort(key=rank)
        for command in system.findall("command"):
            system.remove(command)
        # <command> entries have to come right after <extension>
        pos = list(system).index(system.find("extension")) + 1
        for i, (_, command) in enumerate(commands):
            system.insert(pos + i, command)
        result.append(system)

    ET.indent(result)
    # <loadExclusive/> has to be a top level element next to <systemList>,
    # which ElementTree can't write
    with open(out, "w", encoding="utf-8") as f:
        f.write('<?xml version="1.0"?>\n<loadExclusive/>\n')
        f.write(ET.tostring(result, encoding="unicode"))
        f.write("\n")
    print(f"{len(result)} systems", file=sys.stderr)


if __name__ == "__main__":
    main()
