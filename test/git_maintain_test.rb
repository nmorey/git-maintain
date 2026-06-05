# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative '../lib/git-maintain'

class GitMaintainTest < Minitest::Test
  def setup
    # Determine the absolute path to the bin/git-maintain script
    @bin_path = File.expand_path('../bin/git-maintain', __dir__)
    # Ensure we include the local lib directory in the ruby load path
    @lib_path = File.expand_path('../lib', __dir__)
  end

  def run_git_maintain(*args)
    # Run the bin script with ruby -Ilib to ensure it uses the local codebase
    stdout, stderr, status = Open3.capture3('ruby', "-I#{@lib_path}", @bin_path, *args)
    [stdout, stderr, status]
  end

  def test_help_option
    stdout, stderr, status = run_git_maintain('--help')

    assert_equal 0, status.exitstatus, "Expected exit status 0, but got standard error: #{stderr}"
    assert_empty stderr, "Expected stderr to be empty"
    assert_match(/Usage: .*git-maintain <action>/, stdout)
    assert_match(/-h, --help/, stdout)
    assert_match(/--verbose/, stdout)
    assert_match(/Possible actions:/, stdout)
  end

  def test_list_actions_action
    stdout, stderr, status = run_git_maintain('list_actions')

    assert_equal 0, status.exitstatus, "Expected exit status 0, but got standard error: #{stderr}"
    assert_empty stderr, "Expected stderr to be empty"

    # Check that common/default actions are listed
    assert_match(/^list_actions$/m, stdout)
    assert_match(/^cp$/m, stdout)
    assert_match(/^steal$/m, stdout)
    assert_match(/^list$/m, stdout)
    assert_match(/^merge$/m, stdout)
    assert_match(/^pull$/m, stdout)
    assert_match(/^push$/m, stdout)
    assert_match(/^monitor$/m, stdout)
    assert_match(/^release$/m, stdout)
    assert_match(/^reset$/m, stdout)
    assert_match(/^create$/m, stdout)
    assert_match(/^delete$/m, stdout)
    assert_match(/^summary$/m, stdout)
  end

  def test_custom_exceptions
    # Verify exception classes exist and inherit from the base error
    assert_includes GitMaintain::GitMaintainError.ancestors, RuntimeError
    assert_includes GitMaintain::RunError.ancestors, GitMaintain::GitMaintainError
    assert_includes GitMaintain::CPAbort.ancestors, GitMaintain::GitMaintainError
    assert_includes GitMaintain::CPSkip.ancestors, GitMaintain::GitMaintainError
    assert_includes GitMaintain::NoRefError.ancestors, GitMaintain::GitMaintainError
    assert_includes GitMaintain::CherryPickErrorException.ancestors, GitMaintain::GitMaintainError
    assert_includes GitMaintain::ShaNotFoundError.ancestors, GitMaintain::GitMaintainError
    assert_includes GitMaintain::MissingArgumentError.ancestors, GitMaintain::GitMaintainError
    assert_includes GitMaintain::FileNotFoundError.ancestors, GitMaintain::GitMaintainError

    # Test message generation
    run_err = GitMaintain::RunError.new(127, "command not found")
    assert_equal 127, run_err.err_code
    assert_equal "command not found", run_err.msg
    assert_match(/127/, run_err.message)

    cp_skip = GitMaintain::CPSkip.new("abcdef")
    assert_match(/abcdef/, cp_skip.message)

    no_ref = GitMaintain::NoRefError.new("non-existent-ref")
    assert_match(/non-existent-ref/, no_ref.message)
  end

  def test_repo_command_execution_failure
    # Create a temporary directory and test Repo and CLIClassTool command execution
    dir = `mktemp -d`.chomp
    `cd "#{dir}" && git init`
    begin
      repo = GitMaintain::Repo.load(dir)
      # Non-existent command should raise RunError
      assert_raises(GitMaintain::RunError) do
        repo.run("nonexistentcommand")
      end
      # Ref existence check on non-existent ref should raise NoRefError
      assert_raises(GitMaintain::NoRefError) do
        repo.ref_exist?("nonexistentref")
      end
    ensure
      `rm -rf #{dir}`
    end
  end
end
