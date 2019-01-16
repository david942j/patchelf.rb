# frozen_string_literal: true

require 'patchelf/saver'
require 'patchelf/patcher' # To check patched file works as imagine

describe PatchELF::Saver do
  describe 'interpreter=' do
    it 'different length' do
      test_proc = proc do |file, str, filename|
        described_class.new(bin_path(file), filename, interpreter: str).save!
        expect(PatchELF::Patcher.new(filename).interpreter).to eq str
        File.open(filename) do |f|
          expect(ELFTools::ELFFile.new(f).section_by_name('.interp').data).to eq str + "\x00"
        end
      end

      with_tempfile do |tmp|
        # Both PIE and no-PIE should be tested
        %w[pie.elf nopie.elf].each do |f|
          test_proc.call(f, '~test~', tmp)
          test_proc.call(f, 'A' * 30, tmp) # slightly larger than the original interp
          test_proc.call(f, 'A' * 0x1000, tmp) # very large, need extend bin
        end
      end
    end
  end

  describe 'soname' do
    it 'different length' do
      test_proc = proc do |name|
        with_tempfile do |tmp|
          described_class.new(bin_path('libtest.so'), tmp, soname: name).save!
          expect(PatchELF::Patcher.new(tmp).soname).to eq name
        end
      end

      test_proc.call('so.217') # exists string
      test_proc.call('short.so')
      test_proc.call('.so'.rjust(0x10, 'long'))
      test_proc.call('.so'.rjust(0x1000, 'super-long'))
    end
  end

  describe 'needed' do
    it 'modify' do
      bin = bin_path('pie.elf')
      with_tempfile do |tmp|
        described_class.new(bin, tmp, needed: %w[a.so b.so]).save!
        expect(PatchELF::Patcher.new(tmp).needed).to eq %w[a.so b.so]
      end
    end

    it 'remove' do
      bin = bin_path('pie.elf')
      with_tempfile do |tmp|
        described_class.new(bin, tmp, needed: %w[libc.so.6]).save!
        expect(PatchELF::Patcher.new(tmp).needed).to eq %w[libc.so.6]
      end
    end

    it 'add' do
      bin = bin_path('pie.elf')
      with_tempfile do |tmp|
        described_class.new(bin, tmp, needed: %w[libc.so.6 a.so b.so]).save!
        expect(PatchELF::Patcher.new(tmp).needed).to eq %w[a.so libc.so.6 b.so]
      end
    end
  end

  describe 'Mixed' do
    it 'runpath and needed' do
      linux_only!

      %w[pie.elf nopie.elf].each do |f|
        bin = bin_path(f)
        with_tempfile do |tmp|
          described_class.new(bin, tmp,
                              needed: %w[libc.so.6 libstdc++.so.6 libtest.so],
                              runpath: bin_path('')).save!
          expect(`#{tmp} < /dev/null`).to eq "It works!\n"
          expect($CHILD_STATUS.exitstatus).to eq 217
        end
      end
    end
  end
end
