require 'test_helper'
require 'tmpdir'
require 'json'

# want to be able to call multiple repository methods
# and skip the constant pulling/pushing in-between
# and batch the interaction with server all into one
# so...
#
# repo.sync do |r|
#   r.list
#   r.log
# end
#  
# within the block, one pull! is issued before all statements
# and they then don't individually call sync

class CapitalGitSessionTest < Minitest::Test
  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    @fixtures_path = File.expand_path("fixtures", File.dirname(__FILE__))
    @database = CapitalGit::Database.new({:local_path => @tmp_path})
  end

  def test_one_request
    clone_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :clone!) { clone_count += 1}
    pull_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :pull!) { pull_count += 1}

    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
    @repo.log

    assert_equal 1, clone_count
    assert_equal 0, pull_count
  end

  def test_two_requests
    clone_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :clone!) { clone_count += 1}
    pull_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :pull!) { pull_count += 1}

    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
    @repo.log
    @repo.list

    assert_equal 1, clone_count
    assert_equal 1, pull_count
  end

  def test_repo_with_existing_dir
    clone_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :clone!) { clone_count += 1}
    pull_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :pull!) { pull_count += 1}

    @repo = @database.connect("#{@fixtures_path}/testrepo.git", :default_branch => "master")

    revisions = @repo.sync do |repo|
      commits = repo.log limit:100
      commits.each do |r|
        r.merge!(repo.show(r[:commit]))
      end
      commits
    end

    assert_equal 1, clone_count
    assert_equal 0, pull_count

    @repo2 = @database.connect("#{@fixtures_path}/testrepo.git", :default_branch => "master")

    revisions = @repo2.sync do |repo|
      commits = repo.log limit:100
      commits.each do |r|
        r.merge!(repo.show(r[:commit]))
      end
      commits
    end

    assert_equal 1, clone_count
    assert_equal 1, pull_count
  end

  def test_synchronized_requests
    clone_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :clone!) { clone_count += 1}
    pull_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :pull!) { pull_count += 1}

    @repo = @database.connect("#{@fixtures_path}/testrepo.git")

    @repo.sync do |r|
      r.list
      r.log
      r.read_all
    end

    assert_equal 1, clone_count
    assert_equal 0, pull_count
  end

  def test_repeated_sync1_requests
    clone_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :clone!) { clone_count += 1}
    pull_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :pull!) { pull_count += 1}

    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
    @repo.sync do |r|
      r.log
    end
    @repo.list

    assert_equal 1, clone_count
    assert_equal 1, pull_count
  end

  def test_repeated_sync2_requests
    clone_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :clone!) { clone_count += 1}
    pull_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :pull!) { pull_count += 1}

    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
    @repo.sync do |r|
      r.log
    end
    @repo.sync do |r|
      r.list
    end

    assert_equal 1, clone_count
    assert_equal 1, pull_count
  end

  def test_repeated_sync3_requests
    clone_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :clone!) { clone_count += 1}
    pull_count = 0
    Spy.on_instance_method(CapitalGit::LocalRepository, :pull!) { pull_count += 1}

    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
    @repo.sync do |r|
      r.log
      r.read_all
    end
    @repo.sync do |r|
      r.list
    end

    assert_equal 1, clone_count
    assert_equal 1, pull_count
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
  end
end
