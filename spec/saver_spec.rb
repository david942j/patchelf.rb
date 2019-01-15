# frozen_string_literal: true

require 'patchelf/saver'
require 'patchelf/patcher' # To check patched file works as imagine

describe PatchELF::Saver do
  describe 'needed' do
    it 'modify' do
      bin = bin_path('pie.elf')
      with_tempfile do |tmp|
        described_class.new(bin, tmp, needed: %w[a.so b.so]).save!
        expect(PatchELF::Patcher.new(tmp).get(:needed)).to eq %w[a.so b.so]
      end
    end

    it 'remove' do
      bin = bin_path('pie.elf')
      with_tempfile do |tmp|
        described_class.new(bin, tmp, needed: %w[libc.so.6]).save!
        expect(PatchELF::Patcher.new(tmp).get(:needed)).to eq %w[libc.so.6]
      end
    end

    it 'add' do
      bin = bin_path('pie.elf')
      with_tempfile do |tmp|
        described_class.new(bin, tmp, needed: %w[libc.so.6 a.so b.so]).save!
        expect(PatchELF::Patcher.new(tmp).get(:needed)).to eq %w[a.so libc.so.6 b.so]
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
