# 1. Why the tools and the library are split

This page needs no snap experience. If you already know debs and snaps, skip
to [The rule](#the-rule) or to [For all-in-one fans](#for-all-in-one-fans).

## Words first

| Word | Meaning | gpiod example |
|---|---|---|
| **Tool** | A program you run. Lives in `/usr/bin`. | `gpiodetect`, `gpioinfo` |
| **Shared library** | Code that many programs load when they start. A `.so` file in `/usr/lib/<arch>/`. | `libgpiod.so.2` |
| **Soname** | The exact library file name a tool asks for. The number is the ABI version: `.so.2` and `.so.3` are not interchangeable. | `gpiodetect` asks for `libgpiod.so.2` |
| **deb** | An Ubuntu package. One source project usually builds **several** debs: the tools in one, the library in another. | `gpiod` (tools) and `libgpiod2t64` (library), both from the source package `libgpiod` |
| **Interface, plug, slot** | A snap is sealed, so it must ask snapd for anything outside the box. Each kind of access is an **interface**; the snap that asks declares a **plug**, the snap (or the system) that offers declares a **slot**, and `snap connect` joins the two. | the `gpio-control` plug lets `gpiod` open `/dev/gpiochip*` |
| **Content interface** | An interface that mounts a folder of one snap inside another snap. That is how a library snap hands its `.so` files to a tool snap. | the `libgpiod` snap's `lib/` folder appears as `$SNAP/libgpiod` inside the `gpiod` snap |
| **system-files** | An interface that lets a snap read named paths of the host system; on classic Ubuntu the host's files appear under `/var/lib/snapd/hostfs`. | `host-libgpiod` reads the host's `/usr/lib/x86_64-linux-gnu` |

## Debs share, snaps are sealed

On classic Ubuntu every deb unpacks into the same `/usr`. There is **one**
`libgpiod.so.2` on the system, and every program that needs it loads that
one. When `apt` updates the library, every program uses the new one at its
next start.

A snap is a sealed box. Whatever is inside the box is a **private copy** that
only that snap sees, and it stays exactly as it was on the day the snap was
built. Ubuntu Core has no `apt` at all: everything arrives as snaps.

```text
classic Ubuntu (debs)                    a snap with everything inside
---------------------                    -----------------------------
/usr/bin/gpiodetect ─┐                   gpiod snap
/usr/bin/gpioinfo  ──┼─► /usr/lib/.../     ├── gpiodetect ─┐
python3-libgpiod   ──┘   libgpiod.so.2     ├── gpioinfo  ──┴─► its own libgpiod.so.2
                         (one, updated     └── (frozen at build time; the system's
                          by apt)               copy is never used)
```

## Why that matters for testing

We use these tools to test devices. A test result is only useful when it
says something about the system under test.

- **On classic Ubuntu**, an all-in-one snap tests *its own* library, not the
  one the image ships. If the image's library has a bug, the test passes
  anyway; if the snap's copy has a bug the image does not have, the test
  fails for nothing.
- **Over time**, the copy inside the snap only changes when somebody rebuilds
  the snap. The archive keeps moving; the test tool does not.
- **On Ubuntu Core**, there is no system library to test, so the library
  must come in a snap. Putting it in its *own* snap means every tool that
  needs it shares one copy that can be updated without touching the tools.

## The rule

> **The tool snap carries the tools and nothing else.**
> On classic Ubuntu the tools use the library the system already ships.
> On Ubuntu Core they use a separate library snap.

```text
classic Ubuntu 24.04                         Ubuntu Core 24
/usr/lib/.../libgpiod.so.2  (host deb)       libgpiod snap  ($SNAP/lib/libgpiod.so.2)
        │  plug: host-libgpiod                       │  plug: libgpiod (content)
        └───────────────┬───────────────────────────┘
                        ▼
        gpiod snap: bin/gpiod-env.sh picks the library, then starts the tool
                        │  plug: gpio-control (permission to open the device)
                        ▼
                  /dev/gpiochip*
```

Two separate things have to be granted, and they never replace each other:

1. **Permission** to touch the hardware: a snapd interface such as
   `gpio-control` (or `alsa` for audio). It gives no library.
2. **The library itself**: a content interface (Ubuntu Core) or a
   `system-files` plug that reads the host's copy (classic). It gives no
   hardware access.

And every file has **one owner**: the library belongs to the library snap
(or to the system), the tools belong to the tool snap. No snap *ships* a
second copy of somebody else's file. (On classic the wrapper copies the
host's library into the snap's writable area each time a tool starts; that
is a run-time cache of the system's file, not a second owner.)

## The same idea at a larger scale

Audio follows the same shape with at least three snaps instead of two (not in this
repository yet; it is the shape to follow), because it also has
board-specific data: `alsa-utils` (tools), `alsa-lib` (the library and
its plugins) and `alsa-ucm-conf` (the per-board configuration). A board
vendor can swap the configuration snap without rebuilding the tools. The
pattern is always the same: **split along the lines that change for
different reasons.**

## For all-in-one fans

Putting the library inside the tool snap is the easiest way to get a working
snap, and for some cases it is the right call. Here is a fair comparison for
**test tools from the Ubuntu archive**:

| | One snap with everything | Tools snap + library from system or library snap |
|---|---|---|
| Snaps to install | 1 | 1 on classic, 2 on Ubuntu Core |
| Commands to connect | permission plug only | permission plug + one library plug |
| Library a test exercises on classic | the snap's frozen copy | **the image's library** (the rest of the userspace, such as libc, still comes from the snap's base) |
| Library update reaches the tests | only after a tool rebuild | classic: next `apt upgrade`; Core: refresh one library snap |
| Several tools need the same library | one copy per snap | one shared copy |
| Wrong-version risk | none: tool and library are built together | possible when snaps of different series are mixed; the wrapper only checks that the soname file exists, so follow the same-series rule (see below) |
| Same bits on every run | yes: one snap revision fixes tool and library | classic: follows the host's library; Core: fixed by the pair of snap revisions |
| Rollback | one snap | the tool snap and the library snap separately |
| Recipe complexity | lowest | one wrapper script and two plugs more |

### Common objections

**"It is more snaps and more connections."** Yes. On Ubuntu Core: one more
snap and one more `snap connect`. On classic: no extra snap, one extra
`snap connect` (the host-library plug). In exchange the test measures the
system, which is the point of these tests.

**"Content interfaces are fragile; the wrong library could be mounted."**
Partly true. For snaps installed with `--dangerous`, which is how the snaps
from this repository are installed, snapd skips its connection policy, so
`snap connect` will join a library snap of another series. (For snaps from
the Snap Store, snapd requires the `content` labels to match.) Nothing in
snapd checks that the library really fits the tool. The wrapper adds a first
check: it starts the tool only if a file with the exact soname exists
(`libgpiod.so.2`), and otherwise stops with `libgpiod.so.2 not found` and the
command to fix it. A library with the right name from a different Ubuntu
release can still fail when it loads, for example with `GLIBC_2.38 not
found`. The rule that prevents both: take every snap from the same series as
the system ([INSTALL-MATRIX.md](../INSTALL-MATRIX.md)).

**"Which library did my test actually use?"** If both library plugs are
connected on classic and the host copy fails, the wrapper quietly uses the
library snap. When it matters, connect only one library plug, and check with
`sudo snap run --shell gpiod.gpiodetect -c 'echo "$LD_LIBRARY_PATH"'`: the
first folder is the library in use.

**"A bundle is reproducible; yours depends on the host."** True, and for
some tests that is exactly what you want (see the list below). The tests
these recipes serve check the image, so they follow the image. Every release
of the build CI records which archive versions it was built from.

**"I can just stage the library and set `LD_LIBRARY_PATH`."** That is the
all-in-one snap again: it works, and it tests the snap's copy instead of the
system's.

**"Debs work fine, why snaps at all?"** On classic, use the debs if you can.
These snaps exist because Ubuntu Core has no `apt`, and because the same
recipe should give the same tools on classic and Core.

### When one snap is still the right choice

- The tool links only against libraries that are already in the base snap
  (libc and friends): there is nothing to split.
- The tool is statically linked.
- The library is not packaged anywhere you could share it from, and only this
  one tool will ever use it.
- You want a fixed userspace on purpose: the same tool and library bits on
  every device and every run, because the test is about the kernel or the
  hardware, not the image's libraries. Then bundle, and say so in the test's
  description.
- A throwaway demo that nobody will test against or maintain.

## Beyond local installs

Everything here assumes snaps installed with `--dangerous`, from a local
build or a CI release. Publishing them in the Snap Store adds steps this
repository does not cover: the `system-files` interface needs Store
approval, connections made by a gadget snap name snaps by their Store ID,
and `default-provider` only installs a provider snap; it does not pick the
right series.

Everything else in this repository uses the split. The next page shows how to
find where to split: [2. How to find the split](2-find-the-split.md).
