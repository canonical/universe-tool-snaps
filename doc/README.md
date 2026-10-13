# Library and tools: how every recipe here is built

Every snap pair in this repository follows one rule:

> **The tool snap carries the tools and nothing else.**
> The shared library the tools need comes from the system on classic Ubuntu,
> or from a separate library snap on Ubuntu Core.

This folder explains that rule from zero, so that you can apply it to a new
tool and end up with a recipe that looks like every other recipe here.

| Read | When you want to know |
|---|---|
| [1. Why the tools and the library are split](1-why-split.md) | what a deb, a snap, a library and a tool are; why one snap with everything inside is the wrong default for test tools; when it is still fine |
| [2. How to find the split](2-find-the-split.md) | the six commands that tell you which deb is the tool, which is the library, and what stays in the base |
| [3. The recipe shape](3-recipe-shape.md) | the two snapcraft.yaml templates, the naming rules, the wrapper script, and the checklist a reviewer uses |

## The idea in one picture

```text
              Ubuntu archive                               snaps built here
  -----------------------------------------      -------------------------------------
  source package libgpiod
    ├── deb gpiod          (the tools)     ──►   gpiod snap     usr/bin/gpio*  only
    ├── deb libgpiod2t64   (the library)   ──►   libgpiod snap  lib/libgpiod.so*  only
    └── deb libgpiod-dev, python3-libgpiod       not needed by the tools

  At run time the gpiod snap finds libgpiod.so.2:
    classic Ubuntu  ->  the host's copy  (the deb the system already ships)
    Ubuntu Core     ->  the libgpiod snap, mounted through a content interface
```

Which snaps to install on which system is in
[INSTALL-MATRIX.md](../INSTALL-MATRIX.md); how to add a series or an arch is
in [CONTRIBUTING.md](../CONTRIBUTING.md).
