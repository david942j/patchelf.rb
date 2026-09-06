#!/usr/bin/env ruby
# frozen_string_literal: true

require 'patchelf/cli'

exit PatchELF::CLI.work(ARGV)
