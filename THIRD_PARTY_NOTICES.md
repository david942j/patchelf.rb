# Third-party test fixture notices

The files described here are used only by the test suite under `spec/files` and
are excluded from the released Ruby gem. They retain their upstream license
terms; the repository's MIT license does not replace those terms.

## NixOS/patchelf 0.15.0 test material

`spec/files/contiguous-note-sections.s` and
`spec/files/contiguous-note-sections.ld` match the corresponding source files in
the [NixOS/patchelf 0.15.0 test suite](https://github.com/NixOS/patchelf/tree/0.15.0/tests).
`spec/files/contiguous-note-sections.elf` is built from those files.

`spec/files/libbig-dynstr.debug` was built from the upstream 0.15.0 test
sources represented by
[`tests/big-dynstr.sh`](https://github.com/NixOS/patchelf/blob/0.15.0/tests/big-dynstr.sh).

NixOS/patchelf 0.15.0 provides the
[GNU General Public License version 3](https://github.com/NixOS/patchelf/blob/0.15.0/COPYING).

## Syncthing 1.4.0

`spec/files/syncthing` was extracted from the historical Homebrew bottle for
Syncthing 1.4.0. It is retained as a regression fixture for ELF layouts that the
default saver can rewrite incorrectly.

- Committed executable SHA-256:
  `996e0fb40fc7f7a5c7bf2c42ee0bb9078c1f7a467d5769a65fb3c56c0edecb29`
- Historical bottle archive SHA-256 recorded when the fixture was added:
  `982b710fe714387b4ce4fb82f16a170ab20e8cda09f4609194f12496848a27ac`
- Upstream source release:
  [syncthing/syncthing v1.4.0](https://github.com/syncthing/syncthing/releases/tag/v1.4.0)
- Upstream license:
  [Mozilla Public License 2.0](https://github.com/syncthing/syncthing/blob/v1.4.0/LICENSE)

The original bottle download endpoint is no longer available. Replacing this
20 MB executable with a small, source-generated reproducer remains preferred.
