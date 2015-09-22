require 'test_helper'

class CapitalGitDatabaseTest < Minitest::Test

  def test_that_it_exists
    refute_nil ::CapitalGit::Database
  end

  def test_instance
    database = CapitalGit::Database.new("test")
    refute_nil database
    assert database.repositories.is_a? Hash
  end

  def test_connection_str
    d1 = CapitalGit::Database.new("/tmp/test")
    assert_equal d1.connection_str, "/tmp/test/"

    d2 = CapitalGit::Database.new("example@example.com")
    assert_equal d2.connection_str, "example@example.com:"
  end

  def test_setting_credentials
    database = CapitalGit::Database.new("test")
    test_credentials = {
      :username => "a_developer",
      :publickey => "testcapitalgit.pub",
      :privatekey => "testcapitalgit",
      :passphrase => "this is a passphrase"
    }
    database.credentials = test_credentials
    assert database.credentials.is_a? Rugged::Credentials::SshKey
  end

  def test_setting_committer
    database = CapitalGit::Database.new("test")
    test_committer = {
      "email" => "developer@example.com",
      "name" => "A Developer"
    }
    database.committer = test_committer
    assert_equal database.committer[:email], test_committer["email"]
    assert_equal database.committer[:name], test_committer["name"]
    assert_in_delta database.committer[:time], Time.now
  end

  def test_cleanup
    database = CapitalGit::Database.new("test")
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    database.local_path = @tmp_path
    assert File.directory?(@tmp_path)
    assert_equal database.local_path, @tmp_path
    database.cleanup
    assert !File.directory?(@tmp_path)
  end

end
