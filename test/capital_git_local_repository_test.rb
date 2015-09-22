require 'test_helper'
require 'tmpdir'
require 'json'

class CapitalGitLocalRepositoryTest < Minitest::Test

  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    @fixtures_path = File.expand_path("fixtures", File.dirname(__FILE__))
    @database = CapitalGit::Database.new(@fixtures_path, {:local_path => @tmp_path})
    @repo = @database.connect("testrepo")
  end

  def test_that_it_exists
    refute_nil @repo
    assert Dir.exists? @repo.local_path
    assert @repo.repository.is_a? Rugged::Repository
  end

  def test_paths
    assert_equal @repo.local_path, File.join(@tmp_path, "testrepo")
    assert_equal @repo.remote_url, "#{@fixtures_path}/testrepo.git"
  end

  def test_listing_items
    assert_equal [
        {:entry=>{:name=>"README", :oid=>"1385f264afb75a56a5bec74243be9b367ba4ca08", :filemode=>33188, :type=>:blob}, :path=>"README"},
        {:entry=>{:name=>"new.txt", :oid=>"fa49b077972391ad58037050f2a75f74e3671e92", :filemode=>33188, :type=>:blob}, :path=>"new.txt"},
        {:entry=>{:name=>"README", :oid=>"1385f264afb75a56a5bec74243be9b367ba4ca08", :filemode=>33188, :type=>:blob}, :path=>"subdir/README"},
        {:entry=>{:name=>"new.txt", :oid=>"fa49b077972391ad58037050f2a75f74e3671e92", :filemode=>33188, :type=>:blob}, :path=>"subdir/new.txt"},
        {:entry=>{:name=>"README", :oid=>"1385f264afb75a56a5bec74243be9b367ba4ca08", :filemode=>33188, :type=>:blob}, :path=>"subdir/subdir2/README"},
        {:entry=>{:name=>"new.txt", :oid=>"fa49b077972391ad58037050f2a75f74e3671e92", :filemode=>33188, :type=>:blob}, :path=>"subdir/subdir2/new.txt"}
      ], @repo.list, "Git list items works"
  end

  def test_log
    assert_equal [
        {"message"=>"subdirectories\n", "author"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-10-26 15:44:21 -0200"}, "time"=>"2010-10-26 13:44:21 -0400", "oid"=>"36060c58702ed4c2a40832c51758d5344201d89a"},
        {"message"=>"another commit\n", "author"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-05-11 13:38:42 -0700"}, "time"=>"2010-05-11 16:38:42 -0400", "oid"=>"5b5b025afb0b4c913b4c338a42934a3863bf3644"},
        {"message"=>"testing\n", "author"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-05-08 16:13:06 -0700"}, "time"=>"2010-05-08 19:13:06 -0400", "oid"=>"8496071c1b46c854b31185ea97743be6a8774479"}
      ], JSON.parse(@repo.log.to_json), "Git log works"

    # this silly json round trip is to convert symbols to strings and dates to right format

    assert_equal [
        {"message"=>"subdirectories\n", "author"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-10-26 15:44:21 -0200"}, "time"=>"2010-10-26 13:44:21 -0400", "oid"=>"36060c58702ed4c2a40832c51758d5344201d89a"}
      ], JSON.parse(@repo.log(:limit => 1).to_json), "Git log works"

    log_item = @repo.log.first
    assert_equal [:message, :author, :time, :oid], log_item.keys
    assert log_item[:time].is_a? Time
  end

  def test_read
    item = @repo.read("README")
    assert_equal "hey\n", item[:value]
    assert_equal [:value, :entry, :commits], item.keys
    assert_equal({:name=>"README", :oid=>"1385f264afb75a56a5bec74243be9b367ba4ca08", :filemode=>33188, :type=>:blob}, item[:entry])
    assert_equal 1, item[:commits].length

    assert_equal @repo.read("new.txt")[:commits].length, 1
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
  end
end
