# patchelf.rb
Implements NixOS/patchelf in pure Ruby.

## Installation

Simply execute:
```
$ gem install patchelf
```

## Usage

```
$ patchelf.rb
# Usage: patchelf.rb <commands> FILENAME [OUTPUT_FILE]
#         --pi, --print-interpreter    Show interpreter's name.
#         --pn, --print-needed         Show needed libraries specified in DT_NEEDED.
#         --ps, --print-soname         Show soname specified in DT_SONAME.
#         --set-interpreter INTERP     Set interpreter's name.
#         --version                    Show current gem's version.

```

```
$ patchelf.rb --print-interpreter --print-needed /bin/ls
# Interpreter: /lib64/ld-linux-x86-64.so.2
# Needed: libselinux.so.1 libc.so.6

```
