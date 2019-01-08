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
SHELL_OUTPUT_OF(patchelf.rb)
```

### Display information
```
SHELL_OUTPUT_OF(patchelf.rb --print-interpreter --print-needed /bin/ls)
```

### Change the dynamic loader (interpreter)
```
# $ patchelf.rb --interp NEW_INTERP input.elf output.elf
SHELL_OUTPUT_OF(patchelf.rb --interp /lib/AAAA.so /bin/ls ls.patch)
SHELL_OUTPUT_OF(file ls.patch)
SHELL_EXEC(rm -f ls.patch)
```

### Change SONAME of a shared library
```
SHELL_OUTPUT_OF(patchelf.rb --so libc.so.217 /lib/x86_64-linux-gnu/libc.so.6 ./libc.patched)
SHELL_OUTPUT_OF(readelf -d libc.patched | grep SONAME)
SHELL_EXEC(rm -f libc.patched)
```

### As Ruby library
```rb
require 'patchelf'

DEFINE_PATCHER(/bin/ls)
RUBY_OUTPUT_OF(patcher.get(:interpreter))
RUBY_EVAL(patcher.interpreter = '/lib/AAAA.so.2')
RUBY_OUTPUT_OF(patcher.get(:interpreter))
RUBY_EVAL(patcher.save('ls.patch'))

# SHELL_OUTPUT_OF(file ls.patch)
SHELL_EXEC(rm ls.patch)
```

## Environment

patchelf.rb is implemented in pure Ruby, so it should work in all environments include Linux, maxOS, and Windows!
