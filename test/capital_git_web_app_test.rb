require 'test_helper'
require 'tmpdir'
require 'json'

class CapitalGitWebAppTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    @fixtures_path = File.expand_path("fixtures", File.dirname(__FILE__))
    @database = CapitalGit::Database.new({:local_path => @tmp_path})
    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
  end

  def app
    CapitalGit::WebApp
  end

  def test_index
    get '/'
    assert last_response.ok?
    assert_equal "capital_git", last_response.body
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
  end
end
