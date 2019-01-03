require 'patchelf/patcher'

describe PatchELF::Patcher do
  def get(filename)
    described_class.new(File.join(__dir__, 'files', filename))
  end

  it 'print' do
    patcher = get('libtest.so')
    expect(patcher.print(:soname)).to eq 'libtest.so.217'
    expect(patcher.print(:needed)).to eq %w[libstdc++.so.6 libc.so.6]
    expect { patcher.print(:interpreter) }.to output("[WARN] No interpreter found.\n").to_stderr

    expect(get('pie.elf').print(:interpreter)).to eq '/lib64/ld-linux-x86-64.so.2'
  end
end
