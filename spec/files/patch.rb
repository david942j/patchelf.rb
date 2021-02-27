#!/usr/bin/env ruby
# encoding: ascii-8bit
# frozen_string_literal: true

require 'elftools'

# To patch the generated ELFs for testing.

# Currently this script is only used for removing "sections" from nosection.elf.
ELFTools::ELFFile.new(File.open('nosection.elf')).tap do |elf|
  elf.header.e_shoff = 0
  elf.header.e_shnum = 0
  elf.header.e_shstrndx = 0
  elf.save('nosection.elf')
end
