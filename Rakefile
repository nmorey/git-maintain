# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.verbose = true
end

desc "Check for trailing whitespace"
task :lint_whitespace do
  puts "Checking for trailing whitespace..."
  files = Dir.glob("{lib,test}/**/*") + ["README.md"]
  errors = []
  
  files.each do |file|
    next if File.directory?(file)
    next if file.end_with?('~') # Ignore backup files
    File.foreach(file).with_index do |line, index|
      if line =~ /[ \t]+$/
        errors << "#{file}:#{index + 1} has trailing whitespace"
      end
    end
  end

  if errors.any?
    puts errors.join("\n")
    fail "Found trailing whitespace in #{errors.size} lines."
  else
    puts "No trailing whitespace found."
  end
end

task default: [:lint_whitespace, :test]
