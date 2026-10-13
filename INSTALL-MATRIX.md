# Install matrix: tool snap alone, or tool snap plus library snap

A tool snap in this repo ships the tool, not its shared library. At run time
its command-chain script looks for the library in this order:

1. **Host library** (classic Ubuntu only), through the `host-<lib>` plug.
   This is what the system ships, so it is what a test should exercise.
2. **Library snap**, through the `<lib>` content plug.
3. Neither: the tool exits with a message naming the plug to connect.

So the question for each system is: can the tool load the host's library?
That needs the exact soname the tool was built against **and** a host on the
same Ubuntu release as the snap's series. Inside the snap the tool runs on the
base's C library (core22 ships glibc 2.35), and a library built for a newer
release can need a newer one: Ubuntu 24.04's `libgpiod.so.2` needs
`GLIBC_2.38`, so a series22 tool cannot load it even though the soname matches.

## Decision table

| System | Install | Connect |
|---|---|---|
| Ubuntu Core (no apt) | library snap + tool snap, same series | `<tool>:<lib> <lib>:<lib>` |
| Classic, same release as the snap's series, library deb installed | **tool snap only** | `<tool>:host-<lib>` |
| Classic, same release, library deb missing but apt allowed | the library deb with apt, then **tool snap only** | `<tool>:host-<lib>` |
| Classic, same release, apt not allowed | library snap + tool snap, same series | `<tool>:<lib> <lib>:<lib>` |
| Classic, **different** release from the snap's series | library snap + tool snap, same series | `<tool>:<lib> <lib>:<lib>`, and **disconnect** `<tool>:host-<lib>` |

When both plugs are connected the **host library wins**, which is why the
last row must disconnect `host-<lib>`: otherwise the tool keeps picking the
host library it cannot load.

## gpiod

The tool snap also needs `gpio-control` (access to `/dev/gpiochip*`) and
`hardware-observe` in every case.

| Series of the gpiod snap | Soname | Host deb that provides it | Library snap content label |
|---|---|---|---|
| series22 | `libgpiod.so.2` | `libgpiod2` (Ubuntu 22.04) | `libgpiod2` |
| series24 | `libgpiod.so.2` | `libgpiod2t64` (Ubuntu 24.04) | `libgpiod2` |
| series26 | `libgpiod.so.3` | `libgpiod3` (Ubuntu 26.04) | `libgpiod3` |

Snap file names: a local `snapcraft pack` gives `gpiod_<version>_<arch>.snap`
in the series folder; the Canonical CI release adds the series,
`gpiod_<version>_<series>_<arch>.snap`. Use whichever files you have, and put
the library and tool snaps of the same series side by side.

Ubuntu Core, or classic without the library:

```bash
sudo snap install --dangerous ./libgpiod_<version>_[<series>_]<arch>.snap
sudo snap install --dangerous ./gpiod_<version>_[<series>_]<arch>.snap
sudo snap connect gpiod:gpio-control
sudo snap connect gpiod:hardware-observe
sudo snap connect gpiod:libgpiod libgpiod:libgpiod
```

Classic with the library already installed (for example Ubuntu 24.04 with
`libgpiod2t64`, and the series24 gpiod snap):

```bash
sudo snap install --dangerous ./gpiod_<version>_[<series>_]<arch>.snap
sudo snap connect gpiod:gpio-control
sudo snap connect gpiod:hardware-observe
sudo snap connect gpiod:host-libgpiod
```

## Rules that keep this safe

- **Take both snaps from the same series.** For snaps installed with
  `--dangerous`, snapd skips its connection policy and does not compare
  content labels, so a series24 `gpiod` can be connected to a series26
  `libgpiod`. The tool then refuses to start with
  `libgpiod.so.2 not found`, because it only accepts the exact soname it was
  built against. If you see that message while the library snap is
  connected, the two snaps come from different series. Mixing series can also
  end in a loader error such as `version GLIBC_2.38 not found` (a series22
  tool with a series24 library: both are `libgpiod.so.2`).
- **Run the tools with `sudo`** unless your user can already open
  `/dev/gpiochip*` (`ls -l /dev/gpiochip*`: often root only, or root plus a
  group such as `dialout`). Connected plugs do not change those file
  permissions, so without access you get `Permission denied`.
- **Check which library is in use** when a result looks wrong:
  `sudo snap run --shell gpiod.gpiodetect -c 'echo "$LD_LIBRARY_PATH"'`
  prints the chosen directory first.
