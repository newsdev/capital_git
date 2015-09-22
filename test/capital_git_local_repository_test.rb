require 'test_helper'

class CapitalGitLocalRepositoryTest < Minitest::Test

  def setup
    # puts 'setup'
  end

  def test_that_it_exists
    refute_nil ::CapitalGit::LocalRepository
  end

  def teardown
    # puts 'teardown'
  end
end
