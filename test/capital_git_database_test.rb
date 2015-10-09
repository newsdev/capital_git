require 'test_helper'

class CapitalGitDatabaseTest < Minitest::Test

  def test_that_it_exists
    refute_nil ::CapitalGit::Database
  end

  def test_empty_instance
    database = CapitalGit::Database.new
    assert_kind_of CapitalGit::Database, database
    assert_respond_to database, :connect
    assert File.directory? database.local_path
  end

  def test_server_str
    d1 = CapitalGit::Database.new(:server => "git@example.com")
    assert_equal d1.server, "git@example.com"
  end

  def test_connect
    tmp_path = Dir.mktmpdir("capital-git-test-repos")
    fixtures_path = File.expand_path("fixtures", File.dirname(__FILE__))
    database = CapitalGit::Database.new({:local_path => tmp_path})
    repo = database.connect("#{fixtures_path}/testrepo.git")
    assert_kind_of CapitalGit::LocalRepository, repo
    FileUtils.remove_entry_secure(tmp_path)
  end

  def test_setting_credentials
    database = CapitalGit::Database.new
    database.credentials = {
      :username => "git",
      :publickey => File.expand_path("fixtures/keys/testcapitalgit.pub", File.dirname(__FILE__)),
      :privatekey => File.expand_path("fixtures/keys/testcapitalgit", File.dirname(__FILE__)),
      :passphrase => "capital_git passphrase"
    }
    assert database.credentials.is_a? Rugged::Credentials::SshKey
  end

  def test_setting_committer
    database = CapitalGit::Database.new
    test_committer = {
      "email" => "developer@example.com",
      "name" => "A Developer"
    }
    database.committer = test_committer
    assert_equal database.committer[:email], test_committer["email"]
    assert_equal database.committer[:name], test_committer["name"]
    assert_in_delta database.committer[:time], Time.now
  end

  def test_empty_committer
    database = CapitalGit::Database.new
    assert_nil database.committer
  end

  def test_cleanup
    database = CapitalGit::Database.new
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    database.local_path = @tmp_path
    assert File.directory?(@tmp_path)
    assert_equal database.local_path, @tmp_path
    database.cleanup
    assert !File.directory?(@tmp_path)
  end

end

class CapitalGitRemoteDatabaseTest < Minitest::Test
  def test_ssh_connect
    database = CapitalGit::Database.new(:server => "git@github.com", :local_path => Dir.mktmpdir("capital-git-test-repos"))

    database.credentials = {
      :username => "git",
      :publickey => File.expand_path("fixtures/keys/testcapitalgit.pub", File.dirname(__FILE__)),
      :privatekey => File.expand_path("fixtures/keys/testcapitalgit", File.dirname(__FILE__)),
      :passphrase => "capital_git passphrase"
    }

    assert_kind_of CapitalGit::LocalRepository, database.connect("git@github.com:newsdev/capital_git_testrepo")

    database.cleanup
  end
end

