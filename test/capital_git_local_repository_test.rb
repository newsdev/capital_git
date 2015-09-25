require 'test_helper'
require 'tmpdir'
require 'json'

class CapitalGitLocalRepositoryTest < Minitest::Test
  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    @fixtures_path = File.expand_path("fixtures", File.dirname(__FILE__))
    @database = CapitalGit::Database.new({:local_path => @tmp_path})
    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
  end

  def test_that_it_exists
    refute_nil @repo
    assert Dir.exists? @repo.local_path
    assert_kind_of Rugged::Repository, @repo.repository
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
    assert_kind_of Time, log_item[:time]
  end

  def test_read
    item = @repo.read("README")
    assert_equal "hey\n", item[:value]
    assert_equal [:value, :entry, :commits], item.keys
    assert_equal({:name=>"README", :oid=>"1385f264afb75a56a5bec74243be9b367ba4ca08", :filemode=>33188, :type=>:blob}, item[:entry])
    assert_equal 1, item[:commits].length

    assert_equal @repo.read("new.txt")[:commits].length, 1

    assert_nil @repo.read("nonexistent.txt"), "Read returns nil when object doesn't exist"
  end

  def test_read_all
    flat = [
        {:path => "README", :value => "hey\n"},
        {:path => "new.txt", :value => "new file\n"},
        {:path => "subdir/README", :value => "hey\n"},
        {:path => "subdir/new.txt", :value => "new file\n"},
        {:path => "subdir/subdir2/README", :value => "hey\n"},
        {:path => "subdir/subdir2/new.txt", :value => "new file\n"}
      ]
    tree = {
        "README" => {:path => "README", :value => "hey\n"},
        "new.txt" => {:path => "new.txt", :value => "new file\n"},
        "subdir" => {
          "README" => {:path => "subdir/README", :value => "hey\n"},
          "new.txt" => {:path => "subdir/new.txt", :value => "new file\n"},
          "subdir2" => {
            "README" => {:path => "subdir/subdir2/README", :value => "hey\n"},
            "new.txt" => {:path => "subdir/subdir2/new.txt", :value => "new file\n"}
          }
        }
      }

    assert_equal flat, @repo.read_all
    assert_equal flat, @repo.read_all(:mode => :flat)
    assert_equal tree, @repo.read_all(:mode => :tree)
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
  end
end


class CapitalGitLocalRepositoryWriteTest < Minitest::Test
  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos") # will have the bare fixture repo
    @tmp_path2 = Dir.mktmpdir("capital-git-test-repos") # will have the clone of the bare fixture repo
   
    @bare_repo = Rugged::Repository.clone_at(
          File.join(File.expand_path("fixtures", File.dirname(__FILE__)), "testrepo.git"),
          File.join(@tmp_path, "bare-testrepo.git"),
          :bare => true
        )
    # @bare_repo.head = "refs/heads/master"
    @database = CapitalGit::Database.new({:local_path => @tmp_path2})
    @database.committer = {"email"=>"albert.sun@nytimes.com", "name"=>"albert_capital_git dev"}
    @repo = @database.connect("#{@tmp_path}/bare-testrepo.git")
  end

  def test_write
    assert @repo.write("test-create-new-file","b", :message => "test_write")
    assert_equal "b", @repo.read("test-create-new-file")[:value], "Write to new file"

    assert @repo.write("README", "fancy fancy", :message => "Update readme")
    assert_equal "fancy fancy", @repo.read("README")[:value], "Write to existing file"

    # test that it pushed
    # and that commit id's of the source and local copy match
    assert_equal @bare_repo.head.target.oid, @repo.repository.head.target.oid
  end

  def test_delete
    @repo.write("d","hello world", :message => "test_delete write")
    assert_equal "hello world", @repo.read("d")[:value]

    assert @repo.delete("d", :message => "test_delete"), "Delete returns true when successfully deleted"
    assert_nil @repo.read("d"), "Read returns nil when object doesn't exist"
    assert_equal false, @repo.delete("d", :message => "test_delete again"), "Delete returns false when object can't be deleted or doesn't exist"

    assert_equal @bare_repo.head.target.oid, @repo.repository.head.target.oid
  end

  def test_pull
    tmp_path3 = Dir.mktmpdir("capital-git-test-repos")
    database2 = CapitalGit::Database.new({:local_path => tmp_path3})
    database2.committer = {"email"=>"second.committer@nytimes.com", "name"=>"second dev"}
    repo2 = database2.connect("#{@tmp_path}/bare-testrepo.git")

    assert_equal @bare_repo.head.target.oid, @repo.repository.head.target.oid
    assert_equal @bare_repo.head.target.oid, repo2.repository.head.target.oid
    assert_equal @repo.repository.head.target.oid, repo2.repository.head.target.oid

    # this write should not be immediately seen by repo2
    @repo.write("test-create-new-file","b", :message => "test_write")
    assert_equal @bare_repo.head.target.oid, @repo.repository.head.target.oid
    refute_equal @bare_repo.head.target.oid, repo2.repository.head.target.oid
    refute_equal @repo.repository.head.target.oid, repo2.repository.head.target.oid

    # now bring repo2 up to date
    repo2.pull!
    assert_equal @bare_repo.head.target.oid, @repo.repository.head.target.oid
    assert_equal @bare_repo.head.target.oid, repo2.repository.head.target.oid
    assert_equal @repo.repository.head.target.oid, repo2.repository.head.target.oid
    assert_equal @repo.read_all, repo2.read_all

    database2.cleanup
  end

  def test_push
    @repo.write("test-create-new-file","b", :message => "test_write")
    assert_equal @bare_repo.head.target.oid, @repo.repository.head.target.oid
  end

  def test_clear
    skip("Not implemented and unclear if it should be implemented")
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
    FileUtils.remove_entry_secure(@tmp_path2)
  end
end

class CapitalGitBranchesTest < Minitest::Test
  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    @fixtures_path = File.expand_path("fixtures", File.dirname(__FILE__))
    @database = CapitalGit::Database.new({:local_path => @tmp_path})
    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
  end

  def test_list_another_branch
    items = @repo.list(branch: "packed")
    assert_equal 2, items.length, "2 items on branch 'packed'"

    assert_equal "another.txt", items[0][:entry][:name]
    assert_equal "second.txt", items[1][:entry][:name]
  end

  def test_log_another_branch
    commits = @repo.log(branch: "packed")
    assert_equal 2, commits.length, "2 commits on branch 'packed'"

    assert_equal "packed commit two", commits[0][:message]
    assert_equal "packed commit one", commits[1][:message]
  end

  def test_read_another_branch
    file = @repo.read("another.txt", branch: "packed")
    assert_equal :blob, file[:entry][:type]
    assert_equal "yet another file", file[:value]
    assert_equal "packed commit one", file[:commits][0][:message]
  end

  def test_read_all_another_branch
    contents = @repo.read_all(branch: "packed")
    assert_equal 2. contents.length
    assert_equal ["another.txt", "second.txt"], contents.map {|c| c[:path]}
    assert_equal ["yet another file", "what file?"], contents.map {|c| c[:value]}

    contents = @repo.read_all(branch: "packed", mode: :tree)
    assert_equal 2. contents.keys.length
    assert_equal ["another.txt", "second.txt"], contents.keys
    assert_equal ["yet another file", "what file?"], contents.values.map {|c| c[:value]}
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
    FileUtils.remove_entry_secure(@tmp_path2)
  end
end

class CapitalGitWriteBranchesTest < Minitest::Test
  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos") # will have the bare fixture repo
    @tmp_path2 = Dir.mktmpdir("capital-git-test-repos") # will have the clone of the bare fixture repo
   
    @bare_repo = Rugged::Repository.clone_at(
          File.join(File.expand_path("fixtures", File.dirname(__FILE__)), "testrepo.git"),
          File.join(@tmp_path, "bare-testrepo.git"),
          :bare => true
        )
    @database = CapitalGit::Database.new({:local_path => @tmp_path2})
    @database.committer = {"email"=>"albert.sun@nytimes.com", "name"=>"albert_capital_git dev"}
    @repo = @database.connect("#{@tmp_path}/bare-testrepo.git")
  end

  def test_write_on_another_branch
    skip("TODO")
  end

  def test_delete_on_another_branch
    skip("TODO")
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
    FileUtils.remove_entry_secure(@tmp_path2)
  end
end
