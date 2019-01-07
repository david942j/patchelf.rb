[![Build Status](https://travis-ci.org/david942j/patchelf.rb.svg?branch=master)](https://travis-ci.org/david942j/patchelf.rb)
[![Dependabot Status](https://api.dependabot.com/badges/status?host=github&repo=david942j/patchelf.rb)](https://dependabot.com)
[![Code Climate](https://codeclimate.com/github/david942j/patchelf.rb/badges/gpa.svg)](https://codeclimate.com/github/david942j/patchelf.rb)
[![Issue Count](https://codeclimate.com/github/david942j/patchelf.rb/badges/issue_count.svg)](https://codeclimate.com/github/david942j/patchelf.rb)
[![Test Coverage](https://codeclimate.com/github/david942j/patchelf.rb/badges/coverage.svg)](https://codeclimate.com/github/david942j/patchelf.rb/coverage)
[![Inline docs](https://inch-ci.org/github/david942j/patchelf.rb.svg?branch=master)](https://inch-ci.org/github/david942j/patchelf.rb)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](http://choosealicense.com/licenses/mit/)

# patchelf.rb

Implements features of NixOS/patchelf in pure Ruby.

## Installation

WIP.

## Usage

```
$ patchelf.rb
# Usage: patchelf.rb <commands> FILENAME [OUTPUT_FILE]
#         --pi, --print-interpreter    Show interpreter's name.
#         --pn, --print-needed         Show needed libraries specified in DT_NEEDED.
#         --ps, --print-soname         Show soname specified in DT_SONAME.
#         --si, --set-interpreter INTERP
#                                      Set interpreter's name.
#         --version                    Show current gem's version.

```

### Display information
```
$ patchelf.rb --print-interpreter --print-needed /bin/ls
# Interpreter: /lib64/ld-linux-x86-64.so.2
# Needed: libselinux.so.1 libc.so.6

```

### Change the dynamic loader (interpreter)
```
$ patchelf.rb --si /lib64/my-ld-linux-x86-64.so.2 program.elf output.elf
```

```
$ patchelf.rb --si /lib64/AAAA.so /bin/ls ls.patch

$ file ls.patch
# ls.patch: ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/AAAA.so, for GNU/Linux 3.2.0, BuildID[sha1]=9567f9a28e66f4d7ec4baf31cfbf68d0410f0ae6, stripped

```

### As Ruby library
```rb
require 'patchelf'

patcher = PatchELF::Patcher.new('/bin/ls')
patcher.get(:interpreter)
#=> "/lib64/ld-linux-x86-64.so.2"

patcher.interpreter = '/lib/AAAA.so.2'
patcher.get(:interpreter)
#=> "/lib/AAAA.so.2"

patcher.save('ls.patch')

# $ file ls.patch
# ls.patch: ELF 64-bit LSB shared object, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib/AAAA.so.2, for GNU/Linux 3.2.0, BuildID[sha1]=9567f9a28e66f4d7ec4baf31cfbf68d0410f0ae6, stripped

```

## Environment

patchelf.rb is implemented in pure Ruby, so it should work in all environments include Linux, maxOS, and Windows!
