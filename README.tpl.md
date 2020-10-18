[![Build Status](https://travis-ci.com/david942j/patchelf.rb.svg?branch=master)](https://travis-ci.com/david942j/patchelf.rb)
[![Dependabot Status](https://api.dependabot.com/badges/status?host=github&repo=david942j/patchelf.rb)](https://dependabot.com)
[![Code Climate](https://codeclimate.com/github/david942j/patchelf.rb/badges/gpa.svg)](https://codeclimate.com/github/david942j/patchelf.rb)
[![Issue Count](https://codeclimate.com/github/david942j/patchelf.rb/badges/issue_count.svg)](https://codeclimate.com/github/david942j/patchelf.rb)
[![Test Coverage](https://codeclimate.com/github/david942j/patchelf.rb/badges/coverage.svg)](https://codeclimate.com/github/david942j/patchelf.rb/coverage)
[![Inline docs](https://inch-ci.org/github/david942j/patchelf.rb.svg?branch=master)](https://inch-ci.org/github/david942j/patchelf.rb)
[![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](http://choosealicense.com/licenses/mit/)

# patchelf.rb

Implements features of NixOS/patchelf in pure Ruby.

## Installation

Available on RubyGems.org!
```
$ gem install patchelf
```

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

### Modify dependency libraries

#### Add
```
$ patchelf.rb --add-needed libnew.so /bin/ls ls.patch
```

#### Remove
```
$ patchelf.rb --remove-needed libc.so.6 /bin/ls ls.patch
```

#### Replace
```
SHELL_OUTPUT_OF(patchelf.rb --replace-needed libc.so.6,libcnew.so.6 /bin/ls ls.patch)
SHELL_OUTPUT_OF(readelf -d ls.patch | grep NEEDED)
SHELL_EXEC(rm -f ls.patch)
```

#### Set directly
```
SHELL_OUTPUT_OF(patchelf.rb --needed a.so,b.so,c.so /bin/ls ls.patch)
SHELL_OUTPUT_OF(readelf -d ls.patch | grep NEEDED)
SHELL_EXEC(rm -f ls.patch)
```

### Set RUNPATH of an executable
```
SHELL_OUTPUT_OF(patchelf.rb --runpath . /bin/ls ls.patch)
SHELL_OUTPUT_OF(readelf -d ls.patch | grep RUNPATH)
SHELL_EXEC(rm -f libc.patch)
```

### Change SONAME of a shared library
```
SHELL_OUTPUT_OF(patchelf.rb --so libc.so.217 /lib/x86_64-linux-gnu/libc.so.6 libc.patch)
SHELL_OUTPUT_OF(readelf -d libc.patch | grep SONAME)
SHELL_EXEC(rm -f libc.patch)
```

### As Ruby library
```rb
require 'patchelf'

DEFINE_PATCHER(/bin/ls)
RUBY_OUTPUT_OF(patcher.interpreter)
RUBY_EVAL(patcher.interpreter = '/lib/AAAA.so.2')
RUBY_OUTPUT_OF(patcher.interpreter)
RUBY_EVAL(patcher.save('ls.patch'))

# SHELL_OUTPUT_OF(file ls.patch)
SHELL_EXEC(rm ls.patch)
```

## Environment

patchelf.rb is implemented in pure Ruby, so it should work in all environments include Linux, macOS, and Windows!
