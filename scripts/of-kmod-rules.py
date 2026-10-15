#!/usr/bin/env python3
"""
Generate udev rules that skip the module lookup for device tree devices
that can't have a loadable module.

Looking up an `of:` modalias in kmod has to match it against every
wildcard device tree alias of every module, ~18000 with the generic NixOS
kernel, which takes 50-300 ms per device on an RK3326. Only a handful of
the device tree devices of a board actually need a module, so match the
board's DTB against modules.alias once at build time and let udev skip the
lookup for everything else.

udev doesn't allow changing MODALIAS, so this writes a modified copy of
systemd's 80-drivers.rules, replacing its generic `kmod load` rule.

Usage: of-kmod-rules.py <board.dts> <modules.alias> <80-drivers.rules>
"""

import re
import sys
from fnmatch import fnmatchcase


def dt_nodes(dts_path):
    """Yield (name, device_type, [compatible, ...]) for each DT node."""
    stack = []
    node_re = re.compile(r'^\s*(?:[\w-]+:\s*)*([^\s{}]+)\s*\{\s*$')
    for line in open(dts_path):
        m = node_re.match(line)
        if m:
            stack.append({"name": m[1].split("@")[0], "type": None, "compat": []})
            continue
        if re.match(r'^\s*\};\s*$', line):
            node = stack.pop()
            if node["compat"]:
                yield node["name"], node["type"], node["compat"]
            continue
        m = re.match(r'^\s*compatible\s*=\s*(.*);\s*$', line)
        if m and stack:
            stack[-1]["compat"] = re.findall(r'"([^"]*)"', m[1])
            continue
        m = re.match(r'^\s*device_type\s*=\s*"([^"]*)";\s*$', line)
        if m and stack:
            stack[-1]["type"] = m[1]


def of_patterns(alias_path):
    """Yield (pattern, module) for every `of:` alias."""
    for line in open(alias_path):
        parts = line.split()
        if len(parts) == 3 and parts[0] == "alias" and parts[1].startswith("of:"):
            yield parts[1], parts[2]


KMOD_RULE = 'ENV{MODALIAS}=="?*", RUN{builtin}+="kmod load"\n'


def main():
    dts_path, alias_path, drivers_rules = sys.argv[1:4]
    patterns = list(of_patterns(alias_path))

    needed = {}  # compatible -> modules
    for name, dtype, compat in dt_nodes(dts_path):
        # Same format as the kernel's of_modalias()
        modalias = f"of:N{name}T{dtype or '(null)'}" + "".join(
            "C" + c.replace(" ", "_") for c in compat
        )
        modules = sorted({mod for pat, mod in patterns if fnmatchcase(modalias, pat)})
        if modules:
            for c in compat:
                needed.setdefault(c, set()).update(modules)

    rules = [
        'ENV{MODALIAS}!="?*", GOTO="of_kmod_end"',
        'ENV{MODALIAS}!="of:*", RUN{builtin}+="kmod load", GOTO="of_kmod_end"',
        "# Device tree device already bound to a (built-in) driver",
        'DRIVER=="?*", GOTO="of_kmod_end"',
        "# Device tree compatibles of this board that have a module",
    ]
    for c in sorted(needed):
        rules.append(f"# {c}: {' '.join(sorted(needed[c]))}")
        for pat in (f"*C{c}", f"*C{c}C*"):
            rules.append(f'ENV{{MODALIAS}}=="{pat}", RUN{{builtin}}+="kmod load", GOTO="of_kmod_end"')
    rules.append('LABEL="of_kmod_end"')

    upstream = open(drivers_rules).read()
    if upstream.count(KMOD_RULE) != 1:
        sys.exit(f"{drivers_rules}: generic kmod rule not found, update {sys.argv[0]}")
    header = "# Modified by of-kmod-rules.py: skip slow module lookups for device\n# tree devices that can't have a module, see there for details.\n"
    print(header + upstream.replace(KMOD_RULE, "\n".join(rules) + "\n"), end="")


if __name__ == "__main__":
    main()
