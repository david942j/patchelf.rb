# frozen_string_literal: true

require 'patchelf/patcher'
require 'patchelf/alt_saver'

describe PatchELF::AltSaver do
  it 'reports the missing old section index without masking the patch error' do
    saver = described_class.allocate
    saver.instance_variable_set(:@old_sections, [Object.new, nil])

    expect { saver.__send__(:new_section_idx, 1) }
      .to raise_error(PatchELF::PatchError, 'old_sections[1] is nil')
  end
end
