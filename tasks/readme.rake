# frozen_string_literal: true

desc 'Generate README.md from README.tpl.md'
task :readme do
  next if ENV['CI']

  require 'patchelf'

  readme = File.open('README.md', 'w')

  def patcher
    @patcher
  end

  def replace(prefix)
    @cur.gsub!(/#{prefix}\(.*\)/) do |s|
      yield(s[(prefix.size + 1)...-1])
    end
  end

  File.readlines('README.tpl.md').each do |line|
    @cur = line
    replace('SHELL_OUTPUT_OF') do |cmd|
      '$ ' + cmd + "\n" + `#{cmd}`.lines.map do |c|
        next "#\n" if c.strip.empty?

        '# ' + c
      end.join
    end

    replace('SHELL_EXEC') do |cmd|
      `#{cmd}`
      # bad idea..
      @cur = +''
    end

    replace('DEFINE_PATCHER') do |str|
      @patcher = PatchELF::Patcher.new(str)
      "patcher = PatchELF::Patcher.new('#{str}')"
    end

    replace('RUBY_OUTPUT_OF') do |cmd|
      res = instance_eval(cmd)
      cmd + "\n" + '#=> ' + res.inspect + "\n"
    end

    replace('RUBY_EVAL') do |cmd|
      instance_eval(cmd)
      cmd
    end

    readme.write @cur
  end

  readme.close
end
