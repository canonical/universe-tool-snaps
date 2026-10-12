# gpiod

The libgpiod command-line tools from the Ubuntu archive. The snap does not
ship `libgpiod`: it uses the host library on classic Ubuntu or the
[libgpiod](../libgpiod/README.md) snap on Ubuntu Core. See
[INSTALL-MATRIX.md](../INSTALL-MATRIX.md) for which one you need.

| Series | Base | Deb | Version | Needs | Tools |
|---|---|---|---|---|---|
| series22 | core22 | `gpiod` | 1.6.3-1build1 | `libgpiod.so.2` | gpiodetect, gpioinfo, gpioget, gpioset, gpiofind, gpiomon |
| series24 | core24 | `gpiod` | 1.6.3-1.1build1 | `libgpiod.so.2` | gpiodetect, gpioinfo, gpioget, gpioset, gpiofind, gpiomon |
| series26 | core26 | `gpiod` | 2.2.1-3build1 | `libgpiod.so.3` | gpiodetect, gpioinfo, gpioget, gpioset, gpiomon, gpionotify |

libgpiod v2 (series26) changed the command-line syntax as well as the tool
set; check `gpioget --help` before reusing a v1 command line.

## Plugs

| Plug | Why | Connect |
|---|---|---|
| `gpio-control` | read and drive `/dev/gpiochip*` | always |
| `hardware-observe` | GPIO metadata under `/sys` | always |
| `libgpiod` | library from the libgpiod snap | Ubuntu Core, or classic without the library |
| `host-libgpiod` | library from the host | classic with the library deb installed |

## Build

```bash
cd gpiod/series24
snapcraft pack
bash ../tests/test-gpiod-env.sh   # library selection logic, from any folder
```

## Use

```bash
sudo snap connect gpiod:gpio-control
sudo snap connect gpiod:hardware-observe
sudo snap connect gpiod:libgpiod libgpiod:libgpiod   # or: sudo snap connect gpiod:host-libgpiod
```

Aliases, so the commands have their usual names:

```bash
# series22 / series24
for t in gpiodetect gpioinfo gpioget gpioset gpiofind gpiomon; do sudo snap alias gpiod.$t $t; done
# series26
for t in gpiodetect gpioinfo gpioget gpioset gpiomon gpionotify; do sudo snap alias gpiod.$t $t; done
```

`gpiodetect` and `gpioinfo` only read. `gpioset` drives a line: on a real
board, check what a line is wired to before you set it.
