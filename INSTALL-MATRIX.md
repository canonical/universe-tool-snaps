# Install matrix: tool snap alone, or tool snap plus library snap

A tool snap in this repo ships the tool, not its shared library. At run time
its command-chain script looks for the library in this order:

1. **Host library** (classic Ubuntu only), through the `host-<lib>` plug.
   This is what the system ships, so it is what a test should exercise.
2. **Library snap**, through the `<lib>` content plug.
3. Neither: the tool exits with a message naming the plug to connect.

So the question for each system is: does the host already have the exact
library (soname) the tool was built against?

## Decision table

| System | Host has the soname the tool needs? | Install | Connect |
|---|---|---|---|
| Ubuntu Core | never (no apt) | library snap + tool snap | `<tool>:<lib> <lib>:<lib>` |
| Classic | yes | **tool snap only** | `<tool>:host-<lib>` |
| Classic | no, but you may install debs | the library deb with apt, then **tool snap only** | `<tool>:host-<lib>` |
| Classic | no, and the deb is not an option (different series, or no apt allowed) | library snap + tool snap | `<tool>:<lib> <lib>:<lib>` |
| Classic | yes, and the library snap is also connected | either works; the **host library wins** | both |

## gpiod

The tool snap also needs `gpio-control` (access to `/dev/gpiochip*`) and
`hardware-observe` in every case.

| Series of the gpiod snap | Soname | Host deb that provides it | Library snap content label |
|---|---|---|---|
| series22 | `libgpiod.so.2` | `libgpiod2` (Ubuntu 22.04) | `libgpiod2` |
| series24 | `libgpiod.so.2` | `libgpiod2t64` (Ubuntu 24.04) | `libgpiod2` |
| series26 | `libgpiod.so.3` | `libgpiod3` (Ubuntu 26.04) | `libgpiod3` |

Ubuntu Core, or classic without the library:

```bash
sudo snap install --dangerous ./libgpiod_<version>_<series>_<arch>.snap
sudo snap install --dangerous ./gpiod_<version>_<series>_<arch>.snap
sudo snap connect gpiod:gpio-control
sudo snap connect gpiod:hardware-observe
sudo snap connect gpiod:libgpiod libgpiod:libgpiod
```

Classic with the library already installed (for example Ubuntu 24.04 with
`libgpiod2t64`, and the series24 gpiod snap):

```bash
sudo snap install --dangerous ./gpiod_<version>_<series>_<arch>.snap
sudo snap connect gpiod:gpio-control
sudo snap connect gpiod:hardware-observe
sudo snap connect gpiod:host-libgpiod
```

## Rules that keep this safe

- **Take both snaps from the same series.** A manual `snap connect` does not
  compare content labels, so a series24 `gpiod` can be connected to a
  series26 `libgpiod`. The tool then refuses to start with
  `libgpiod.so.2 not found`, because it only accepts the exact soname it was
  built against. If you see that message while the library snap is
  connected, the two snaps come from different series.
- **Run the tools with `sudo`.** `/dev/gpiochip*` is owned by root; without
  `sudo` you get `Permission denied` even with every plug connected.
- **Check which library is in use** when a result looks wrong:
  `sudo snap run --shell gpiod.gpiodetect -c 'echo "$LD_LIBRARY_PATH"'`
  prints the chosen directory first.
