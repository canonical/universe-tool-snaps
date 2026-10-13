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
  snap version shows which archive version is inside (snap versions cannot
  hold `:`, so an epoch `1:` becomes `1-`, and they are cut to 32
  characters).
- `confinement: strict`. Use interfaces for device access, never `devmode`.
- No `aliases:` in `apps:`. snapd ignores it for `--dangerous` installs; the
  README of the snap lists the `snap alias` commands instead.
- Set `license:` to the upstream license of what the snap ships.
- Declare every architecture you can build (`amd64` and `arm64` today).

## Add a tool

1. Find the split: [doc/2-find-the-split.md](doc/2-find-the-split.md).
2. Create `<tool>/seriesNN/snap/snapcraft.yaml` (and the library snap's) for
   every series the tool exists in, from the templates in
   [doc/3-recipe-shape.md](doc/3-recipe-shape.md).
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

Every tool here ships without its shared library. [doc/](doc/README.md)
explains why, shows how to find the split for a new tool, and gives the two
recipe templates with the naming rules and the reviewer checklist. In short:

- the tool snap primes only the tools (`prime:` lists `usr/bin/...`);
- the library snap ships only the sonames the tools need, under `$SNAP/lib`,
  over a content slot labelled `lib<name><N>`;
- every app runs through a copy of `gpiod-env.sh`, which takes the host
  library on classic and the library snap on Ubuntu Core, and stops with a
  clear message when the exact soname is missing.

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
3. Build on a machine of that arch, or with `snapcraft remote-build` from a
   copy of the series folder (see the README; remote-build needs the project
   at the top level of its own git repository).
4. Say in the pull request that you added an arch. Canonical's build CI needs
   a runner for every arch it builds; until one exists for the new arch, the
   CI stops and names the arch instead of building without it.
