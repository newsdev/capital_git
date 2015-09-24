require 'test_helper'

class CapitalGitTest < Minitest::Test

  def setup
    # puts 'setup'
  end

  def test_that_it_has_a_version_number
    refute_nil ::CapitalGit::VERSION
  end

  def test_that_modules_loaded
    refute_nil ::CapitalGit::Database
    refute_nil ::CapitalGit::LocalRepository
  end

  def test_test_env
    assert_equal "test", CapitalGit.env_name
  end

  def test_config_methods_exist
    assert_respond_to CapitalGit, :"load!"
    assert_respond_to CapitalGit, :"load_config!"
    assert_respond_to CapitalGit, :"cleanup!"
    assert_respond_to CapitalGit, :"repository"
    assert_respond_to CapitalGit, :"connect"
  end

  def teardown
    # puts 'teardown'
  end
end
