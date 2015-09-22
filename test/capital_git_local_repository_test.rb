require 'test_helper'
require 'tmpdir'

class CapitalGitLocalRepositoryTest < Minitest::Test

  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    @fixtures_path = File.expand_path("fixtures", File.dirname(__FILE__))
    @database = CapitalGit::Database.new(@fixtures_path, {:local_path => @tmp_path})
  end

  def test_that_it_exists
    repo = @database.connect("testrepo")
    refute_nil repo
    assert Dir.exists? repo.local_path
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
  end
end
