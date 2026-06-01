# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'

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
end
