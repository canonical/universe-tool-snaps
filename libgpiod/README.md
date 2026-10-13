# libgpiod

The `libgpiod` shared library from the Ubuntu archive, shared with tool snaps
over a content interface. You need it on Ubuntu Core, and on classic Ubuntu
only when the host does not have the library; see
[INSTALL-MATRIX.md](../INSTALL-MATRIX.md).

| Series | Base | Deb | Version | Soname | Content label |
|---|---|---|---|---|---|
| series22 | core22 | `libgpiod2` | 1.6.3-1build1 | `libgpiod.so.2` | `libgpiod2` |
| series24 | core24 | `libgpiod2t64` | 1.6.3-1.1build1 | `libgpiod.so.2` | `libgpiod2` |
| series26 | core26 | `libgpiod3` | 2.2.1-3build1 | `libgpiod.so.3` | `libgpiod3` |

The versions are the archive versions when the recipes were written; a
rebuild picks up whatever the archive has at that time, and the snap version
is the version of the deb inside.

The slot exports `$SNAP/lib`, which holds `libgpiod.so.*` for the snap's
architecture.

## Build

```bash
cd libgpiod/series24
snapcraft pack
```

## Use

```bash
sudo snap install --dangerous ./libgpiod_<version>_<arch>.snap
sudo snap connect gpiod:libgpiod libgpiod:libgpiod
```
