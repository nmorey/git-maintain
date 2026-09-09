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
    begin
      repo = GitMaintain::Repo.load()
      # Non-existent command should raise RunError
      assert_raises(GitMaintain::RunError) do
        repo.run("nonexistentcommand")
      end
      # Ref existence check on non-existent ref should raise NoRefError
      assert_raises(GitMaintain::NoRefError) do
        repo.ref_exist?("nonexistentref")
      end
    end
  end

  def test_cp_breaker_option_parsing
    opts = {
        :br_suff => "master",
        :yn_default => nil,
    }
    parser = OptionParser.new
    GitMaintain::BranchIterator.set_opts(:cp, parser, opts)
    parser.parse!(["-c", "abcdef012345", "--breaker", "1234567890ab"])

    assert_equal ["abcdef012345"], opts[:commits]
    assert_equal "1234567890ab", opts[:breaker]
  end

  def test_cp_breaker_filtering
    orig_repo_infos = GitMaintain.class_variable_get(:@@repo_infos) rescue nil
    GitMaintain.class_variable_set(:@@repo_infos, nil)

    begin
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          # Initialize git repo and set identity
          `git init`
          `git checkout -b master 2>/dev/null || git checkout master 2>/dev/null || true`
          `git config user.name "Test User"`
          `git config user.email "test@example.com"`

          # Set up git-maintain configurations
          `git config maintain.valid-repo origin`
          `git config maintain.stable-repo origin`
          `git config maintain.branch-format 'v([0-9]+)'`
          `git config maintain.stable-branch-format 'stable/\\\\1'`
          `git config maintain.stable-base-format 'v\\\\1.0'`

          # Make initial commit
          File.write("foo", "initial content")
          `git add foo`
          `git commit -m "initial commit"`
          `git remote add origin .`

          # Create stable base tags so findStableBase can resolve them
          `git tag v1.0`
          `git tag v2.0`

          # Create a "breaker" commit on master
          File.write("foo", "breaker content")
          `git add foo`
          `git commit -m "breaker commit"`
          breaker_sha = `git rev-parse HEAD`.strip

          # Create a "fix" commit on master
          File.write("foo", "fix content")
          `git add foo`
          `git commit -m "fix commit"`
          fix_sha = `git rev-parse HEAD`.strip

          # Create branch "v1/master" that does NOT contain the breaker (forked from initial commit)
          `git checkout -b v1/master HEAD~2 2>/dev/null`

          # Create branch "v2/master" that DOES contain the breaker (forked from breaker commit)
          `git checkout -b v2/master #{breaker_sha} 2>/dev/null`

          # Load repo and branches
          repo = GitMaintain::Repo.load()
          br1 = GitMaintain::Branch.load(repo, "1", nil, "master")
          br2 = GitMaintain::Branch.load(repo, "2", nil, "master")

          # Verify is_in_tree? correctly finds or doesn't find the breaker
          br1.checkout()
          assert_equal false, br1.send(:is_in_tree?, breaker_sha)

          br2.checkout()
          assert_equal true, br2.send(:is_in_tree?, breaker_sha)

          # Verify cp with breaker on br1 (should skip because breaker is missing)
          br1.checkout()
          initial_head_1 = `git rev-parse HEAD`.strip
          br1.cp({ :commits => [fix_sha], :breaker => breaker_sha })
          assert_equal initial_head_1, `git rev-parse HEAD`.strip, "v1/master should have skipped cp"

          # Verify cp with breaker on br2 (should succeed because breaker is present)
          br2.checkout()
          initial_head_2 = `git rev-parse HEAD`.strip
          br2.cp({ :commits => [fix_sha], :breaker => breaker_sha })
          refute_equal initial_head_2, `git rev-parse HEAD`.strip, "v2/master should have applied cp"

          # Verify that running cp again skips the already applied patch (head doesn't change)
          post_head_2 = `git rev-parse HEAD`.strip
          br2.cp({ :commits => [fix_sha], :breaker => breaker_sha })
          assert_equal post_head_2, `git rev-parse HEAD`.strip, "v2/master should have skipped already applied cp"
        end
      end
    ensure
      GitMaintain.class_variable_set(:@@repo_infos, orig_repo_infos)
    end
  end
end
