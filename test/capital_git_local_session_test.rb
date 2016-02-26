require 'test_helper'
require 'tmpdir'
require 'json'

# TODO:
# want to be able to call multiple repository methods
# and skip the constant pulling/pushing in-between
# and batch the interaction with server all into one
# so...
# call these transactions?
# 
# some form of block syntax?
#
# repo.sync do |r|
#   r.list
#   r.log
# end
#  
# within the block, one pull! is issued before all statements
# and they then don't individually call sync
# 
# or more explicitly
# 
# repo.start_synced
# repo.list
# repo.log
# repo.end_synced
# 
# tx = repo.get_transaction
# tx.list
# tx.log
# tx.end_transaction
# 
# 
# or use the system clock and a config setting (with a default)
# CapitalGit.config.sync_interval = 5s
#
# repo.list    # will pull
# repo.log     # won't pull
#              # wait 5 seconds
# repo.list    # will pull
#
# then any calls that take place within 5 seconds of a previous pull will not pull again


class CapitalGitSessionTest < Minitest::Test
  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    @fixtures_path = File.expand_path("fixtures", File.dirname(__FILE__))
    @database = CapitalGit::Database.new({:local_path => @tmp_path})
    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
  end

  def test_synchronized_requests
    mock = MiniTest::Mock.new
    mock.expect(:call, {})
    
    @repo.stub :"pull!", mock do
      @repo.sync do |r|
        r.list
        r.log
        r.read_all
      end
    end

    # expect pull! to only be called once
    mock.verify
  end

  def test_repeated_sync1_requests
    mock = MiniTest::Mock.new
    mock.expect(:call, {})
    mock.expect(:call, {})
    
    @repo.stub :"pull!", mock do
      @repo.sync do |r|
        r.log
      end
      @repo.list
    end

    mock.verify
  end

  def test_repeated_sync2_requests
    mock = MiniTest::Mock.new
    mock.expect(:call, {})
    mock.expect(:call, {})
    
    @repo.stub :"pull!", mock do
      @repo.sync do |r|
        r.log
      end
      @repo.sync do |r|
        r.list
      end
    end

    mock.verify
  end

  def test_repeated_sync3_requests
    mock = MiniTest::Mock.new
    mock.expect(:call, {})
    mock.expect(:call, {})
    
    @repo.stub :"pull!", mock do
      @repo.sync do |r|
        r.log
        r.read_all
      end
      @repo.sync do |r|
        r.list
      end
    end

    mock.verify
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
  end
end
