# 2. How to find the split

You have a tool you want as a snap. Six steps tell you which deb is the
tool, which deb is the library, and what you can leave to the base snap. Run
them on a classic Ubuntu machine of the **same release** as the series you
are building (Ubuntu 24.04 for `series24`), in an empty folder. The outputs
below are real, for gpiod on Ubuntu 24.04 amd64. Where other tools behave
differently, the text says so (examples from `i2c-tools` and `v4l-utils`).

## Step 1: Which deb has the tool, and what does it need?

```bash
apt-cache show gpiod | grep -E '^(Package|Source|Version|Depends):'
```

```text
Package: gpiod
Version: 1.6.3-1.1build1
Source: libgpiod
Depends: libc6 (>= 2.38), libgpiod2t64 (>= 1.5.1)
```

`Depends` lists the debs the tool cannot run without. For the split, only
the **library** entries matter: names starting with `lib` (`libc6`,
`libgpiod2t64`). Other entries are helpers the deb's install scripts or
extra scripts use, such as `perl:any`, `adduser` or `udev` in
`i2c-tools`; they are not shared libraries and do not change the split.

No `Source:` line means the source package has the same name as the deb
(`i2c-tools`, `v4l-utils`, `alsa-utils` all look like this).

To find which deb ships a command: search "the contents of packages" on
[packages.ubuntu.com](https://packages.ubuntu.com), or
`apt-file search /usr/sbin/i2cdetect` (after `sudo apt install apt-file &&
sudo apt-file update`).

## Step 2: Which debs come from the same project?

One **source package** builds several **binary debs**. Take the `lib*` names
from step 1 and check them one by one:

```bash
for p in gpiod libgpiod2t64; do apt-cache show "$p" | grep -E '^(Package|Source):'; echo; done
```

```text
Package: gpiod
Source: libgpiod

Package: libgpiod2t64
Source: libgpiod
```

Both come from the source package `libgpiod`. To see **every** deb that
source package builds, open
`https://packages.ubuntu.com/source/<release>/<source package>` (for example
`.../source/noble/libgpiod`): its binary packages are `gpiod`,
`libgpiod2t64`, `libgpiod-dev`, `libgpiod-doc` and `python3-libgpiod` (the
other links on that page are build tools). Debian names them by convention, which is
the first hint where the split is:

| Deb name pattern | Holds | Goes into |
|---|---|---|
| `lib<name><N>` (`libgpiod2t64`, `libi2c0`, `libv4l-0t64`; `t64` is a 24.04 rename) | the runtime library `lib<name>.so.<N>` | the **library snap** |
| the tool name (`gpiod`, `i2c-tools`, `v4l-utils`) | programs in `/usr/bin` or `/usr/sbin` | the **tool snap** |
| `lib<name>-dev` | headers for compiling other software | nothing; not needed at run time |
| `python3-<name>`, `-doc`, ... | other users of the library | nothing, unless you package those too |

## Step 3: What files does each deb install?

```bash
apt-get download gpiod libgpiod2t64
dpkg -c gpiod_*.deb | awk '{print $6}'
dpkg -c libgpiod2t64_*.deb | awk '{print $6}'
```

```text
gpiod:                                 libgpiod2t64:
./usr/bin/gpiodetect                   ./usr/lib/x86_64-linux-gnu/libgpiod.so.2.2.2
./usr/bin/gpiofind                     ./usr/lib/x86_64-linux-gnu/libgpiod.so.2
./usr/bin/gpioget                      ./usr/lib/x86_64-linux-gnu/libgpiodcxx.so.1.1.2
./usr/bin/gpioinfo                     ./usr/lib/x86_64-linux-gnu/libgpiodcxx.so.1
./usr/bin/gpiomon                      ./usr/share/doc/libgpiod2t64/copyright
./usr/bin/gpioset                      ...
./usr/share/doc/gpiod/copyright
./usr/share/man/man1/*.1.gz
```

The tool deb holds programs and documentation; the library deb holds the
`.so` files. That is the split. Note **where** the programs are: `i2c-tools`
puts its tools in `/usr/sbin`, not `/usr/bin`, and the recipe must use that
path. The file list of any deb, for any release, is also on
packages.ubuntu.com (`/<release>/<arch>/<deb>/filelist`).

## Step 4: Which libraries does each program really load?

```bash
dpkg-deb -x gpiod_*.deb x
for t in x/usr/bin/* x/usr/sbin/*; do [ -f "$t" ] && echo "${t##*/}: $(readelf -d "$t" 2>/dev/null | grep NEEDED | grep -oE '\[[^]]+\]' | tr '\n' ' ')"; done
```

```text
gpiodetect: [libgpiod.so.2] [libc.so.6]
gpiofind: [libgpiod.so.2] [libc.so.6]
...
gpioset: [libgpiod.so.2] [libc.so.6]
```

`readelf -d ... NEEDED` lists the sonames a program asks for when it starts.
It is more precise than `Depends`: the library deb also ships
`libgpiodcxx.so.1` (C++ bindings), but no tool needs it, so the library snap
does not ship it either. Write down every soname, per program.

An empty list means one of two things, and `file <path>` tells which. A
**script** (`... script, ASCII text executable`): `head -1` shows its
interpreter (`#!/usr/bin/perl` for `decode-dimms` in `i2c-tools`); expose it
only if that interpreter is in the base (step 5) or in the snap, otherwise
leave it out. A **statically linked** program: it needs no shared library at
all.

Then do the same for each library `.so` from step 3, because a library can
need another library:

```bash
dpkg-deb -x libgpiod2t64_*.deb y
readelf -d y/usr/lib/*/libgpiod.so.2 | grep NEEDED
```

```text
 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]
```

Use `grep NEEDED`, not a pattern on `lib...`: a library's dynamic section
also names the library itself (its `SONAME` line). libgpiod needs nothing
else. `libv4l2.so.0` (from `libv4l-0t64`) needs
`libv4lconvert.so.0`, which comes from yet another deb, `libv4lconvert0t64`:
that one belongs in the library snap too.

## Step 5: Which of those are already in the base snap?

Every snap runs on a base snap (`core24` for `series24`) that already
contains the C library and other basics. Anything in the base needs no
snap of its own. Install the base if you do not have it
(`sudo snap install core24`), then map each soname to its deb and look for
that deb in the base's package list:

```bash
dpkg -S /usr/lib/x86_64-linux-gnu/libc.so.6          # which deb ships this soname (installed debs only)
grep -E ' (libc6|libgpiod[0-9a-z]*):' /snap/core24/current/usr/share/snappy/dpkg.list
```

```text
libc6:amd64: /usr/lib/x86_64-linux-gnu/libc.so.6
ii  libc6:amd64   2.39-0ubuntu8.8 ...
```

`libc6` is in the base, `libgpiod` is not. So:

| Soname the tool needs | Deb | In the base? | Where it comes from |
|---|---|---|---|
| `libc.so.6` | `libc6` | yes | the base snap; do nothing |
| `libgpiod.so.2` | `libgpiod2t64` | no | **the library snap** (Ubuntu Core) or the host (classic) |

`libstdc++.so.6`, `libgcc_s.so.1`, `libm.so.6` and `libudev.so.1` (all
needed by `v4l-utils`) are in `core24` too.

## Step 6: Does the library load anything else at run time?

Some libraries open more files after they start: plugins, configuration,
data. Those must travel with the library, and if a board vendor may want to
change them, they get **their own** snap. List what the library deb ships
besides the sonames you already have:

```bash
dpkg -c libgpiod2t64_*.deb | awk '{print $6}' | grep -vE '/libgpiod\.so|/libgpiodcxx\.so|/doc/|/lintian/|/$'
```

For libgpiod this prints nothing. For `libv4l-0t64` it prints
`.../libv4l/plugins/libv4l-mplane.so`: a **plugin**, which `libv4l2` loads
from that folder at run time. It must be in the library snap, and because the plugin folder is compiled into the
library (`strings libv4l2.so.0` shows `/usr/lib/x86_64-linux-gnu/libv4l/plugins/*.so`),
the tool snap also needs a `layout:` that maps that folder to the library
snap's copy. The same list shows `v4l1compat.so` and `v4l2convert.so`: those
are helpers for `LD_PRELOAD`, not plugins, and matter only if your tests use
them.

ALSA shows all three kinds of extra files: `libasound.so.2` (deb
`libasound2t64`) reads its configuration from `/usr/share/alsa/` (deb
`libasound2-data`), loads plugins from `/usr/lib/<arch>/alsa-lib/` (deb
`libasound2-plugins`), and the per-board UCM configuration in
`/usr/share/alsa/ucm2/` comes from `alsa-ucm-conf`. That is why audio is
split into three snaps, and that is the right split, because each part
changes for a different reason:

| Snap | Ships | Changes when |
|---|---|---|
| `alsa-utils` | the tools (`aplay`, `arecord`, `amixer`, `alsactl`, `alsaucm`, ...) | the tools are updated |
| `alsa-lib` | `libasound.so.2` with its configuration (deb `libasound2-data`); the everyday plugins (`hw`, `plug`, `dmix`, `dsnoop`, `rate`, `softvol`) are built into `libasound.so.2` | the library is updated |
| `alsa-ucm-conf` | the per-board UCM configuration | a board needs different audio routing: a vendor ships its own snap with the same content label, and neither the tools nor the library are rebuilt |

The separate `libasound2-plugins` deb only adds bridges to other audio
stacks (PulseAudio, JACK, OSS) and extra resamplers, and it depends on
libraries that are not in the base (`libpulse0`, `libjack-jackd2-0`,
`libavcodec60`, ...). Test tools rarely need it; if yours do, those libraries
go through the same six steps and become snaps of their own. (The ALSA recipes are not in this repository yet; this is the
shape they follow.)

## Decide

```text
For every soname from step 4 (programs AND libraries):
  in the base snap (step 5)?                -> nothing to do
  otherwise                                 -> it goes into a library snap:
     several sonames from the SAME source   -> one library snap, all of them in it
     sonames from a DIFFERENT source        -> a separate library snap each
     plugins or data (step 6)?              -> in the same library snap
     a board needs its own data?            -> that data gets its own snap
Everything left in the tool deb (/usr/bin, /usr/sbin, man pages, copyright)
                                            -> the tool snap
```

If every soname is in the base snap, there is nothing to split: build one
snap with the tool, and you are done.

Write down what you found; you will need these values for the templates in
[3. The recipe shape](3-recipe-shape.md):

| Value | gpiod on series24 | i2c-tools on series24 |
|---|---|---|
| tool deb | `gpiod` | `i2c-tools` |
| programs (apps) and their folder | `gpiodetect gpiofind gpioget gpioinfo gpiomon gpioset` in `usr/bin` | `i2cdetect i2cdump i2cget i2cset i2ctransfer` in `usr/sbin` |
| library deb(s) | `libgpiod2t64` | `libi2c0` |
| soname(s) | `libgpiod.so.2` | `libi2c.so.0` |
| content label (`lib<name><N>`) | `libgpiod2` | `libi2c0` |
| permission interface(s) | `gpio-control`, `hardware-observe` | `i2c` (on Ubuntu Core the gadget snap declares one `i2c` slot per bus) |
| extra run-time files | none | none |

Repeat the steps for every series: package names, sonames and even the tool
list change between Ubuntu releases (on 26.04 the deb is `libgpiod3`, the
soname `libgpiod.so.3`, and `gpiofind` is replaced by `gpionotify`).

The permission interfaces are listed in snapd's
[supported interfaces](https://snapcraft.io/docs/supported-interfaces); pick
the narrowest one that lets the tool open its device.
