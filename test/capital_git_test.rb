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

  # def test_it_does_something_useful
  #   assert false
  # end

  def teardown
    # puts 'teardown'
  end
end
