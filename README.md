# universe-tool-snaps

Build recipes that turn command-line tools from the Ubuntu **universe**
archive into snaps, so the same tools are available on Ubuntu Core (no apt,
read-only root file system) and on classic Ubuntu.

Each tool is built from the archive deb of the matching Ubuntu release, and
its shared library lives in a separate snap. On classic Ubuntu the tool uses
the library the system already ships; on Ubuntu Core it uses the library
snap. That way a test exercises the system's own library whenever there is
one, and the tool behaves like the deb you would install on a classic image.

## Layout

One folder per snap, one sub-folder per Ubuntu series. Every series folder is
a complete snapcraft project.

```text
universe-tool-snaps/
├── INSTALL-MATRIX.md      which snaps to install on which system
├── CONTRIBUTING.md        add a tool, a series or an arch; split a library from its tools
├── libgpiod/              library snap (content provider)
│   ├── series22/snap/snapcraft.yaml    base core22, Ubuntu 22.04 debs
│   ├── series24/snap/snapcraft.yaml    base core24, Ubuntu 24.04 debs
│   └── series26/snap/snapcraft.yaml    base core26, Ubuntu 26.04 debs
└── gpiod/                 tool snap (content consumer)
    ├── series22/{snap/snapcraft.yaml, scripts/gpiod-env.sh}
    ├── series24/{snap/snapcraft.yaml, scripts/gpiod-env.sh}
    ├── series26/{snap/snapcraft.yaml, scripts/gpiod-env.sh}
    └── tests/test-gpiod-env.sh
```

## Available snaps

| Snap | What it ships | Series | Arches |
|---|---|---|---|
| [libgpiod](libgpiod/README.md) | `libgpiod` shared library, over a content interface | 22, 24, 26 | amd64, arm64 |
| [gpiod](gpiod/README.md) | `gpiodetect`, `gpioinfo`, `gpioget`, `gpioset`, `gpiomon`, ... | 22, 24, 26 | amd64, arm64 |

## Build

You need [snapcraft](https://snapcraft.io/docs/snapcraft-setup) and LXD (or
Multipass). Build from the series folder:

```bash
cd gpiod/series24
snapcraft pack
```

The result is `gpiod_<version>_<arch>.snap` for the machine you build on. To
build for another architecture without such a machine, use Launchpad through
`snapcraft remote-build`. It needs a Launchpad account, uploads the project
publicly, and only works when the project is the top level of a git
repository, so build from a copy of the series folder:

```bash
cp -r gpiod/series24 /tmp/gpiod-series24 && cd /tmp/gpiod-series24
git init -q && git add . && git commit -qm "gpiod series24"
snapcraft remote-build --build-for=arm64
```

## Install

Pick the series that matches the Ubuntu release of the system under test
(Ubuntu Core 24 or Ubuntu 24.04 → `series24`), then check
[INSTALL-MATRIX.md](INSTALL-MATRIX.md) to see whether you need the library
snap. On Ubuntu Core you always need it:

```bash
sudo snap install --dangerous ./libgpiod_<version>_<arch>.snap
sudo snap install --dangerous ./gpiod_<version>_<arch>.snap
sudo snap connect gpiod:gpio-control
sudo snap connect gpiod:hardware-observe
sudo snap connect gpiod:libgpiod libgpiod:libgpiod
# series22/24 tools; series26 has gpionotify instead of gpiofind (see gpiod/README.md)
for t in gpiodetect gpioinfo gpioget gpioset gpiofind gpiomon; do sudo snap alias gpiod.$t $t; done
sudo gpiodetect
```

`--dangerous` is needed because these snaps are not signed by the Snap Store,
and `snap alias` is what gives you the plain `gpiodetect` command name. Run
the tools with `sudo` unless your user can already open `/dev/gpiochip*`
(`ls -l /dev/gpiochip*`: often root only, or root plus a group such as
`dialout`).

Canonical staff: prebuilt snaps for every series and arch are published by the
internal `canonical/universe-tool-snaps-build` CI.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The recipes are licensed under the
[GPL-3.0](LICENSE); each snap carries the license of the upstream project it
packages.
