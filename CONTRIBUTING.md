# Contributing

Contributions to Canonical projects need a signed
[Canonical contributor license agreement](https://ubuntu.com/legal/contributors).
Open a pull request; say which systems you tested the snap on.

## Conventions

- The folder name is the snap name. Each series has its own folder,
  `seriesNN/`, built on base `coreNN` from the Ubuntu NN.04 archive.
- Every series folder is a complete snapcraft project. Do not share files
  between series folders with `../`: snapcraft builds in a container that only
  sees the project folder. A helper script is copied into each series, and a
  test checks the copies are identical.
- Build from archive debs: `plugin: nil` with `stage-packages`. Take the snap
  version from the staged deb (`adopt-info` + `craftctl set version`), so the
  snap version says exactly which archive version is inside.
- `confinement: strict`. Use interfaces for device access, never `devmode`.
- No `aliases:` in `apps:`. snapd ignores it for `--dangerous` installs; the
  README of the snap lists the `snap alias` commands instead.
- Set `license:` to the upstream license of what the snap ships.
- Declare every architecture you can build (`amd64` and `arm64` today).

## Add a tool

1. Decide whether the library needs its own snap; see the next section.
2. Create `<tool>/seriesNN/snap/snapcraft.yaml` for every series the tool
   exists in. Copy the closest existing recipe (`gpiod` for a tool with a
   library snap) and change names, debs, sonames and the app list.
3. List the apps from the deb's file list (`/usr/bin/...`) on
   [packages.ubuntu.com](https://packages.ubuntu.com) for each series; tool
   sets change between releases (libgpiod v2 dropped `gpiofind` and added
   `gpionotify`).
4. Build every series you added (`snapcraft pack` in each folder).
5. Install it on classic and, if you can, Ubuntu Core, following
   [INSTALL-MATRIX.md](INSTALL-MATRIX.md). Check each app starts and finds
   its library.
6. Add a `README.md` to the tool folder (what it ships per series, the
   connect and alias commands) and a row to the table in the top README.

## Split a library from its tools

Split when the tool links against a shared library that comes from **its own
deb** (for example `gpiod` needs `libgpiod2`). Do not split when the tool only
needs libraries that are already in the base snap (libc and friends).

The split gives you two snaps that are updated and replaced independently:

```text
classic:      host libgpiod.so.2  --system-files (host-libgpiod)-->  gpiod
Ubuntu Core:  libgpiod snap       --content (libgpiod2)----------->  gpiod
```

### Library snap (content provider)

- Stage only the runtime library deb.
- Move the library to an arch-neutral directory so the slot path is the same
  on every arch:

  ```yaml
  organize:
    usr/lib/*/libgpiod.so*: lib/
  prime:
    - lib/libgpiod.so*
    - usr/share/doc/*/copyright
  ```

- Export it with a content slot whose label is the **library ABI**, that is
  the soname package name (`libgpiod2`, `libgpiod3`), not the project name.
  snapd only connects a plug and a slot with the same label, so a tool built
  for one ABI can never load another:

  ```yaml
  slots:
    libgpiod:
      interface: content
      content: libgpiod2
      read:
        - $SNAP/lib
  ```

### Tool snap (content consumer)

- Stage the tool deb, but prime **only the tools**; the library deb comes in
  as a dependency and must stay out:

  ```yaml
  prime:
    - usr/bin/gpio*
    - usr/share/doc/gpiod/copyright
  ```

- Silence the linter that reports the library as missing; that is the point:

  ```yaml
  lint:
    ignore:
      - library
  ```

- Declare two plugs: the content plug (same label as the slot) and a
  `system-files` plug that reads the host library directory for every
  supported arch triplet.
- Put the soname in `environment:` and run every app through a
  `command-chain` script that picks the library. Copy
  `gpiod/series24/scripts/gpiod-env.sh` and its test
  `gpiod/tests/test-gpiod-env.sh`, then rename `GPIOD_SONAME`, the plug names
  and the content directory. The order is: host library, then the content
  snap, then a clear error.
- If the library also loads plugins or data from fixed paths, export those
  too and set the variable the library reads. ALSA is the example: one snap
  each for the tools (`alsa-utils`), the library and its plugins (`alsa-lib`,
  with `ALSA_PLUGIN_DIR`), and the board-specific data (`alsa-ucm-conf`, with
  `ALSA_CONFIG_UCM2`), so a board can replace the data snap without
  rebuilding the tools.

### Check the split

```bash
unsquashfs -l gpiod_*.snap | grep -c 'libgpiod.so'      # 0: the tool snap ships no library
sudo snap run --shell gpiod.gpiodetect -c 'ldd "$SNAP/usr/bin/gpiodetect" | grep gpiod'
bash gpiod/tests/test-gpiod-env.sh                       # library selection logic
```

## Add a series

1. Copy the newest series folder: `cp -r gpiod/series26 gpiod/series28`.
2. Set `base: core28` and update the debs. Package names change between
   releases (Ubuntu 24.04 renamed `libgpiod2` to `libgpiod2t64`; libgpiod v2
   ships `libgpiod3`); look them up with `rmadison -u ubuntu <package>` or on
   [packages.ubuntu.com](https://packages.ubuntu.com).
3. Update the soname, the content label (if the ABI changed) and the app
   list.
4. Do the same for the library snap, with the same content label.
5. Build both, then add the series to the tool README.

## Add an architecture

1. Add it to `platforms:` (core24 and later) or `architectures:` (core22) in
   every recipe that should support it.
2. Make sure the `host-<lib>` plug lists that arch's library triplet and
   that the command-chain script maps `SNAP_ARCH` to it.
3. Build on a machine of that arch, or with `snapcraft remote-build`.
