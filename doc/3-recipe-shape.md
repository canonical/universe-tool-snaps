# 3. The recipe shape

Every tool in this repository is two snaps with the same shape. Fill the
values you found in [2. How to find the split](2-find-the-split.md) into the
templates below, one file per snap and series:
`<snap>/seriesNN/snap/snapcraft.yaml` (snapcraft looks for the `snap/`
sub-folder).

The templates cover the common case: the tools need **one** library, and
that library loads no plugins or data files (gpiod, i2c-tools). A library
with plugins, data or several sonames (v4l-utils, ALSA) follows the same rule
but needs more than these templates: the library snap also ships the plugin
and data folders, the tool snap needs `layout:` entries for paths compiled
into the library, and the wrapper must handle every soname and, on classic,
the host's plugins too. For such a tool, open an issue with your findings
from page 2 before writing the recipe, so the extra design is agreed once.

## Names

Use the same names everywhere so that every recipe reads the same:

| Thing | Rule | gpiod |
|---|---|---|
| tool snap | the tool deb's name | `gpiod` |
| library snap | the library's upstream name | `libgpiod` |
| `<libname>` | the soname without `.so.<N>` | `libgpiod` (from `libgpiod.so.2`); `libi2c` (from `libi2c.so.0`, deb `libi2c0`) |
| content label | `lib<name><N>`, `N` = soname major version | `libgpiod2` (series22/24), `libgpiod3` (series26) |
| library slot, content plug | the library snap's name | `libgpiod` |
| content mount in the tool snap | `$SNAP/<library snap>` | `$SNAP/libgpiod` |
| host library plug | `host-<library snap>` | `host-libgpiod` |
| soname variable | `<TOOL>_SONAME`, upper case, `-` becomes `_` | `GPIOD_SONAME=libgpiod.so.2`, `I2C_TOOLS_SONAME=libi2c.so.0` |
| wrapper script | `scripts/<tool>-env.sh`, installed as `bin/<tool>-env.sh` | `gpiod-env.sh` |

## Library snap

In the common case it ships one thing: the `.so` files the tools need, in an arch-neutral folder.

```yaml
name: <library snap>                  # libgpiod
base: core24                          # coreNN for seriesNN
adopt-info: <library snap>
summary: <library> runtime library as a content snap
description: |
  Ships <soname> from the Ubuntu NN.04 archive (deb <library deb>) over the
  "<content label>" content interface. See INSTALL-MATRIX.md.
grade: stable
confinement: strict
license: <upstream license of the library>
platforms:                            # core22: architectures: [{build-on, build-for}, ...]
  amd64:
  arm64:

slots:
  <library snap>:
    interface: content
    content: <content label>          # libgpiod2: names the ABI, not the project
    read:
      - $SNAP/lib

parts:
  <library snap>:
    plugin: nil                       # no compiling: the archive deb is the source
    stage-packages:
      - <library deb>                 # libgpiod2t64
    organize:
      usr/lib/*/<libname>.so*: lib/   # usr/lib/x86_64-linux-gnu/... -> lib/, same path on every arch
    prime:
      - lib/<libname>.so*             # only the sonames the tools NEED (not libgpiodcxx)
      - usr/share/doc/*/copyright
    override-build: |
      craftctl default
      ver="$(apt-cache policy <library deb> | awk '/Candidate:/{print $2}')"
      craftctl set version="$(printf '%s' "$ver" | tr ':' '-' | cut -c1-32)"
```

## Tool snap

Ships the tools and the wrapper. No `.so` from the library deb.

```yaml
name: <tool snap>                     # gpiod
base: core24
adopt-info: <tool snap>
summary: <tool> command-line tools
description: |
  The <tool> tools from the Ubuntu NN.04 archive. The snap does not ship
  <library>: it uses the host library on classic Ubuntu or the <library snap>
  content snap on Ubuntu Core. See INSTALL-MATRIX.md.
grade: stable
confinement: strict
license: <upstream license of the tools>
platforms:
  amd64:
  arm64:
lint:
  ignore:
    - library                         # the library is missing on purpose; this
                                      # silences ALL missing-library warnings, so
                                      # check every app's NEEDED list (page 2, step 4)

environment:
  <TOOL>_SONAME: <soname>             # GPIOD_SONAME: libgpiod.so.2

plugs:
  <library snap>:                     # Ubuntu Core: the library snap
    interface: content
    content: <content label>
    target: $SNAP/<library snap>
  host-<library snap>:                # classic: the system's library
    interface: system-files
    read:
      - /var/lib/snapd/hostfs/usr/lib/x86_64-linux-gnu
      - /var/lib/snapd/hostfs/usr/lib/aarch64-linux-gnu
      - /var/lib/snapd/hostfs/usr/lib/arm-linux-gnueabihf
      - /var/lib/snapd/hostfs/usr/lib/riscv64-linux-gnu

apps:
  <tool command>:                     # one entry per program in the tool deb
    command: usr/bin/<tool command>   # or usr/sbin/...: the folder from step 3
    command-chain: [bin/<tool>-env.sh]
    plugs: [<permission interfaces>, <library snap>, host-<library snap>]
                                      # gpiod: gpio-control, hardware-observe

parts:
  <tool snap>:
    plugin: nil
    stage-packages:
      - <tool deb>                    # pulls the library deb too, as a dependency...
    prime:
      - usr/bin/<tool commands>*      # ...and this keeps only the tools: the split happens here
      - usr/sbin/<tool commands>*     # if the programs live there (i2c-tools)
      - usr/share/doc/<tool deb>/copyright
    override-build: |
      craftctl default
      ver="$(apt-cache policy <tool deb> | awk '/Candidate:/{print $2}')"
      craftctl set version="$(printf '%s' "$ver" | tr ':' '-' | cut -c1-32)"
  scripts:
    plugin: dump
    source: scripts/
    organize:
      <tool>-env.sh: bin/<tool>-env.sh
```

Why `prime` and not leaving `stage-packages` out: snapcraft installs a deb
together with what it depends on, so the library deb lands in the build area
no matter what. A `prime:` list that names only the tools decides what
reaches the final snap. Listing what to keep is safer than listing what to
drop: a new file in a future deb is left out by default.

## The wrapper

Every app starts through `bin/<tool>-env.sh` (a `command-chain`), which picks
the library and then starts the tool:

```text
1. classic: copy the host's <soname> into the snap's writable area and use it
   (strict confinement may read the host's /usr/lib but not load from it)
2. otherwise: use $SNAP/<library snap>/<soname> from the library snap
3. neither: stop with "<soname> not found" and the snap connect commands
```

Do not write a new one. Copy `gpiod/series24/scripts/gpiod-env.sh` and
`gpiod/tests/test-gpiod-env.sh` into your tool's folders (one wrapper per
series folder, one test per tool), then replace every gpiod name in **both**
files:

- `GPIOD_SONAME` with `<TOOL>_SONAME`;
- `$SNAP/libgpiod` with `$SNAP/<library snap>`;
- `gpiod-env.sh` with `<tool>-env.sh` (the test looks for it by name);
- the plug, snap and instance names (`gpiod`, `libgpiod`, `host-libgpiod`) in
  the error message and in the test's expected output;
- in the test, the sonames: `libgpiod.so.2` with your soname, and the
  "other series" `libgpiod.so.3` with your library's other soname.

Then run the test: it must pass, and swapping the two library checks in the
wrapper (content before host) must make it fail.

The wrapper checks **one** soname, which is enough when the tools need one
library (gpiod, i2c-tools). A tool whose programs need several (v4l-utils:
`libv4l2.so.0`, `libv4l2rds.so.0`, and `libv4lconvert.so.0` through
`libv4l2`) still gets one library snap per source package, but the wrapper
must then check and copy every soname: extend it to loop over a list, and
add a test case for a missing second soname, in the same pull request.

Keep two details exactly as they are, because both fixed real failures: the
host library is copied to a temporary file and **renamed** into place (a
plain `cp` over the old copy crashes tools that are already running), and
the content snap is used only when the **exact** soname is there (a library
snap from another series must not be loaded).

## Check before you open a pull request

From the repository root, for every series you changed:

```bash
(cd <tool>/series24 && snapcraft pack)
(cd <library snap>/series24 && snapcraft pack)
unsquashfs -l <tool>/series24/<tool>_*.snap | grep '\.so'                  # nothing from the library deb
unsquashfs -l <library snap>/series24/<library snap>_*.snap | grep '\.so'  # only lib/<soname>*
bash <tool>/tests/test-<tool>-env.sh                                       # library selection logic
```

Choose permission interfaces from snapd's
[supported interfaces](https://snapcraft.io/docs/supported-interfaces): the
narrowest one that lets the tool open its device.

Then install both on a test system as in [INSTALL-MATRIX.md](../INSTALL-MATRIX.md)
and start **every** app once through each path (host library on classic,
library snap on Ubuntu Core): `lint: ignore` means nothing else tells you an
app misses a library.

## Reviewer checklist

- [ ] Tool snap: no `.so` from the library deb (`prime:` lists the tools only).
- [ ] Library snap: only the sonames the tools `NEED`, under `lib/`, plus copyright.
- [ ] Content label is `lib<name><N>` and identical in the library slot and the tool plug of the same series.
- [ ] Every app has its permission plug(s) and both library plugs, and runs through the wrapper; `command:` uses the program's real folder (`usr/bin` or `usr/sbin`).
- [ ] The wrapper and its test are copies of the gpiod ones with only the names and sonames changed; the test passes; all series copies of the wrapper are identical.
- [ ] Every app was started once on classic (host library) and, if possible, on Ubuntu Core (library snap).
- [ ] Tool list, deb names and soname were checked for **each** series (they change between releases).
- [ ] `confinement: strict`, version adopted from the deb, no `aliases:`, upstream `license:`.
