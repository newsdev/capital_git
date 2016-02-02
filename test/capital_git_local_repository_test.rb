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
    assert_equal "8496071c1b46c854b31185ea97743be6a8774479", item[:commits].first[:oid]

    assert_equal @repo.read("new.txt")[:commits].length, 1

    assert_nil @repo.read("nonexistent.txt"), "Read returns nil when object doesn't exist"
  end

  def test_read_sha
    item = @repo.read("README", { :sha => "8496071c1b46c854b31185ea97743be6a8774479" })
    assert_equal "hey\n", item[:value]
    assert_equal [:value, :entry, :commits], item.keys
    assert_equal({:name=>"README", :oid=>"1385f264afb75a56a5bec74243be9b367ba4ca08", :filemode=>33188, :type=>:blob}, item[:entry])
    assert_equal 1, item[:commits].length
    assert_equal "8496071c1b46c854b31185ea97743be6a8774479", item[:commits].first[:oid]

    assert_nil @repo.read("README", { :sha => "deadbeef"}), "Read returns nil when object doesn't exist at that sha"

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

  def test_show
    refute_nil @repo.show 

    assert_equal @repo.show, @repo.show("36060c58702ed4c2a40832c51758d5344201d89a")
    assert_equal @repo.show, @repo.show(nil, :branch => "master")
    refute_equal @repo.show, @repo.show("5b5b025afb0b4c913b4c338a42934a3863bf3644")

    refute_nil @repo.show @repo.log[0][:oid]
    refute_nil @repo.show @repo.log[1][:oid]
    refute_nil @repo.show @repo.log[2][:oid]

    show_val = {:oid=>"36060c58702ed4c2a40832c51758d5344201d89a", :message=>"subdirectories\n", :author=>{:name=>"Scott Chacon", :email=>"schacon@gmail.com", :time=>Time.parse("2010-10-26 15:44:21 -0200")}, :time=>Time.parse("2010-10-26 13:44:21 -0400"), :changes=>{:added=>[{:old_path=>"subdir/README", :new_path=>"subdir/README", :patch=>"diff --git a/subdir/README b/subdir/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/README\n@@ -0,0 +1 @@\n+hey\n"}, {:old_path=>"subdir/new.txt", :new_path=>"subdir/new.txt", :patch=>"diff --git a/subdir/new.txt b/subdir/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/subdir/new.txt\n@@ -0,0 +1 @@\n+new file\n"}, {:old_path=>"subdir/subdir2/README", :new_path=>"subdir/subdir2/README", :patch=>"diff --git a/subdir/subdir2/README b/subdir/subdir2/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/subdir2/README\n@@ -0,0 +1 @@\n+hey\n"}, {:old_path=>"subdir/subdir2/new.txt", :new_path=>"subdir/subdir2/new.txt", :patch=>"diff --git a/subdir/subdir2/new.txt b/subdir/subdir2/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/subdir/subdir2/new.txt\n@@ -0,0 +1 @@\n+new file\n"}]}}

    assert_equal show_val, @repo.show
  end

  def test_diff

    # no changes on diff to head 
    diff_val = {:left=>"36060c58702ed4c2a40832c51758d5344201d89a", :right=>"36060c58702ed4c2a40832c51758d5344201d89a", :changes=>{}}
    assert_equal diff_val, @repo.diff(@repo.log[0][:oid])

    diff_val = {:left=>"36060c58702ed4c2a40832c51758d5344201d89a", :right=>"5b5b025afb0b4c913b4c338a42934a3863bf3644", :changes=>{:deleted=>[{:old_path=>"subdir/README", :new_path=>"subdir/README", :patch=>"diff --git a/subdir/README b/subdir/README\ndeleted file mode 100644\nindex 1385f26..0000000\n--- a/subdir/README\n+++ /dev/null\n@@ -1 +0,0 @@\n-hey\n"}, {:old_path=>"subdir/new.txt", :new_path=>"subdir/new.txt", :patch=>"diff --git a/subdir/new.txt b/subdir/new.txt\ndeleted file mode 100644\nindex fa49b07..0000000\n--- a/subdir/new.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-new file\n"}, {:old_path=>"subdir/subdir2/README", :new_path=>"subdir/subdir2/README", :patch=>"diff --git a/subdir/subdir2/README b/subdir/subdir2/README\ndeleted file mode 100644\nindex 1385f26..0000000\n--- a/subdir/subdir2/README\n+++ /dev/null\n@@ -1 +0,0 @@\n-hey\n"}, {:old_path=>"subdir/subdir2/new.txt", :new_path=>"subdir/subdir2/new.txt", :patch=>"diff --git a/subdir/subdir2/new.txt b/subdir/subdir2/new.txt\ndeleted file mode 100644\nindex fa49b07..0000000\n--- a/subdir/subdir2/new.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-new file\n"}]}}
    assert_equal diff_val, @repo.diff(@repo.log[1][:oid])

    diff_val = {:left=>"36060c58702ed4c2a40832c51758d5344201d89a", :right=>"8496071c1b46c854b31185ea97743be6a8774479", :changes=>{:deleted=>[{:old_path=>"new.txt", :new_path=>"new.txt", :patch=>"diff --git a/new.txt b/new.txt\ndeleted file mode 100644\nindex fa49b07..0000000\n--- a/new.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-new file\n"}, {:old_path=>"subdir/README", :new_path=>"subdir/README", :patch=>"diff --git a/subdir/README b/subdir/README\ndeleted file mode 100644\nindex 1385f26..0000000\n--- a/subdir/README\n+++ /dev/null\n@@ -1 +0,0 @@\n-hey\n"}, {:old_path=>"subdir/new.txt", :new_path=>"subdir/new.txt", :patch=>"diff --git a/subdir/new.txt b/subdir/new.txt\ndeleted file mode 100644\nindex fa49b07..0000000\n--- a/subdir/new.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-new file\n"}, {:old_path=>"subdir/subdir2/README", :new_path=>"subdir/subdir2/README", :patch=>"diff --git a/subdir/subdir2/README b/subdir/subdir2/README\ndeleted file mode 100644\nindex 1385f26..0000000\n--- a/subdir/subdir2/README\n+++ /dev/null\n@@ -1 +0,0 @@\n-hey\n"}, {:old_path=>"subdir/subdir2/new.txt", :new_path=>"subdir/subdir2/new.txt", :patch=>"diff --git a/subdir/subdir2/new.txt b/subdir/subdir2/new.txt\ndeleted file mode 100644\nindex fa49b07..0000000\n--- a/subdir/subdir2/new.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-new file\n"}]}}

    assert_equal diff_val, @repo.diff(@repo.log[2][:oid])

    # diff between two commits
    diff_val = {:left=>"5b5b025afb0b4c913b4c338a42934a3863bf3644", :right=>"8496071c1b46c854b31185ea97743be6a8774479", :changes=>{:deleted=>[{:old_path=>"new.txt", :new_path=>"new.txt", :patch=>"diff --git a/new.txt b/new.txt\ndeleted file mode 100644\nindex fa49b07..0000000\n--- a/new.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-new file\n"}]}}
    assert_equal diff_val, @repo.diff(@repo.log[1][:oid], @repo.log[2][:oid])

    # confine changes to specific path
    diff_val = {:left=>"36060c58702ed4c2a40832c51758d5344201d89a", :right=>"8496071c1b46c854b31185ea97743be6a8774479", :changes=>{:deleted=>[{:old_path=>"subdir/README", :new_path=>"subdir/README", :patch=>"diff --git a/subdir/README b/subdir/README\ndeleted file mode 100644\nindex 1385f26..0000000\n--- a/subdir/README\n+++ /dev/null\n@@ -1 +0,0 @@\n-hey\n"}, {:old_path=>"subdir/subdir2/README", :new_path=>"subdir/subdir2/README", :patch=>"diff --git a/subdir/subdir2/README b/subdir/subdir2/README\ndeleted file mode 100644\nindex 1385f26..0000000\n--- a/subdir/subdir2/README\n+++ /dev/null\n@@ -1 +0,0 @@\n-hey\n"}]}}
    opts = {:paths => ['*README']}
    assert_equal diff_val, @repo.diff(@repo.log[2][:oid], nil, opts)

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
    assert @repo.write("test-create-new-file","b", :message => "test_write"), "write succeeds"
    assert_equal "b", @repo.read("test-create-new-file")[:value], "Write to new file"

    assert @repo.write("README", "fancy fancy", :message => "Update readme")
    assert_equal "fancy fancy", @repo.read("README")[:value], "Write to existing file"

    # test that it pushed
    # and that commit id's of the source and local copy match
    assert_equal @bare_repo.head.target.oid, @repo.repository.head.target.oid
  end

  def test_write_many
    assert @repo.write_many([
      {:path => "test-create-new-file", :value => "b"},
      {:path => "README", :value => "write_many hello world\n"}
      ], :message => "test_write"), "write_many on existing repo succeeds"
    assert_equal "b", @repo.read("test-create-new-file")[:value], "write_many to new file succeeded"
    assert_equal "write_many hello world\n", @repo.read("README")[:value], "write_many to existing file succeeded"
    assert_equal 7, @repo.list.length

    assert_equal @bare_repo.head.target.oid, @repo.repository.head.target.oid
  end

  def test_delete
    assert @repo.write("d","hello world", :message => "test_delete write")
    assert_equal "hello world", @repo.read("d")[:value]

    assert @repo.delete("d", :message => "test_delete"), "Delete returns true when successfully deleted"
    assert_nil @repo.read("d"), "Read returns nil when object doesn't exist"
    assert_equal false, @repo.delete("d", :message => "test_delete again"), "Delete returns false when object can't be deleted or doesn't exist"

    assert_equal @bare_repo.head.target.oid, @repo.repository.head.target.oid
  end

  def test_empty_write
    old_remote_oid = @bare_repo.head.target.oid
    old_oid = @repo.repository.head.target.oid
    refute @repo.write("README", @repo.read("README")[:value])
    assert_equal old_oid, old_remote_oid
    assert_equal old_oid, @repo.repository.head.target.oid
  end

  def test_empty_delete
    old_remote_oid = @bare_repo.head.target.oid
    old_oid = @repo.repository.head.target.oid
    refute @repo.delete("nonexistent-file")
    assert_equal old_oid, old_remote_oid
    assert_equal old_oid, @repo.repository.head.target.oid
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


class CapitalGitEmptyRepositoryTest < Minitest::Test
  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos") # will have the bare fixture repo
    @tmp_path2 = Dir.mktmpdir("capital-git-test-repos") # will have the clone of the bare fixture repo
   
    @empty_bare_repo = Rugged::Repository.init_at(
          File.join(@tmp_path, "empty-bare-testrepo.git"),
          true # is_bare
        )
    @database = CapitalGit::Database.new({:local_path => @tmp_path2})
    @database.committer = {"email"=>"albert.sun@nytimes.com", "name"=>"albert_capital_git dev"}
    @repo = @database.connect("#{@tmp_path}/empty-bare-testrepo.git")
  end

  def test_list
    assert_equal [], @repo.list, "Empty list"
  end

  def test_log
    assert_equal [], @repo.log, "Empty commits"
  end

  def test_read
    assert_nil @repo.read("README"), "File doesn't exist returns nil"
  end

  def test_read_all
    assert_equal([], @repo.read_all, "No contents for read_all")
    assert_equal([], @repo.read_all(:mode => :flat))
    assert_equal({}, @repo.read_all(:mode => :tree))
  end

  def test_write
    assert @repo.write("test-create-new-file","b", :message => "test_write"), "write succeeds"
    assert_equal "b", @repo.read("test-create-new-file")[:value], "New file has correct contents"

    assert_equal 1, @repo.log.length
    assert_equal 1, @repo.list.length

    assert_equal @empty_bare_repo.head.target.oid, @repo.repository.head.target.oid
  end

  def test_write_non_default_branch
    skip("todo - implement this feature")
    # assert @repo.write("test-create-new-file","b", :message => "test_write", :branch => "other-branch"), "write to other-branch succeeds"
  end

  def test_write_many
    assert @repo.write_many([
      {:path => "test-create-new-file", :value => "b"},
      {:path => "README", :value => "hello world\n"}
      ], :message => "test_write"), "write_many succeeds"
    assert_equal 1, @repo.log.length
    assert_equal 2, @repo.list.length
    assert_equal @empty_bare_repo.head.target.oid, @repo.repository.head.target.oid
  end

  def test_delete
    refute @repo.delete("nonexistent")
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

    assert_equal "packed commit two\n", commits[0][:message]
    assert_equal "packed commit one\n", commits[1][:message]
  end

  def test_read_another_branch
    file = @repo.read("another.txt", branch: "packed")
    assert_equal :blob, file[:entry][:type]
    assert_equal "yet another file\n", file[:value]
    assert_equal "packed commit one\n", file[:commits][0][:message]
  end

  def test_read_all_another_branch
    contents = @repo.read_all(branch: "packed")
    assert_equal 2, contents.length
    assert_equal ["another.txt", "second.txt"], contents.map {|c| c[:path]}
    assert_equal ["yet another file\n", "what file?\n"], contents.map {|c| c[:value]}

    contents = @repo.read_all(branch: "packed", mode: :tree)
    assert_equal 2, contents.keys.length
    assert_equal ["another.txt", "second.txt"], contents.keys
    assert_equal ["yet another file\n", "what file?\n"], contents.values.map {|c| c[:value]}
  end

  def test_error_missing_branch
    # assert_raises RuntimeError do
    #   @repo.read("README", branch: "nonexistent-branch")
    # end
    assert_nil @repo.read("README", branch: "nonexistent-branch")
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
  end
end

# Test cases for cloning on one default branch
# and then reading files from another branch

class CapitalGitSwitchBranchesTest < Minitest::Test
  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    @fixtures_path = File.expand_path("fixtures", File.dirname(__FILE__))
    @database = CapitalGit::Database.new({:local_path => @tmp_path})
  end

  def test_list_another_branch
    repo1 = @database.connect("#{@fixtures_path}/testrepo.git", :default_branch => "master")
    assert_equal 6, repo1.list(branch: "master").count, "6 items on default branch"

    repo2 = @database.connect("#{@fixtures_path}/testrepo.git", :default_branch => "packed")

    assert_equal repo1.local_path, repo2.local_path

    items = repo2.list(branch: "packed")
    assert_equal 2, items.length, "2 items on branch 'packed'"

    assert_equal "another.txt", items[0][:entry][:name]
    assert_equal "second.txt", items[1][:entry][:name]
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
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
    @bare_repo.remotes['origin'].fetch("+refs/*:refs/*")
    @database = CapitalGit::Database.new({:local_path => @tmp_path2})
    @database.committer = {"email"=>"albert.sun@nytimes.com", "name"=>"albert_capital_git dev"}
    @repo = @database.connect("#{@tmp_path}/bare-testrepo.git", :default_branch => "master")
  end

  def test_write_existing_branch
    assert @repo.write("new-existing-branch.txt", "here it is", :branch => "packed", :message => "test_write_existing_branch"), "write succeeds"
    assert_equal "here it is", @repo.read("new-existing-branch.txt", :branch => "packed")[:value], "Write to new file on existing branch"
    assert_equal 3, @repo.list(branch: "packed").length, "One new item on branch 'packed'"
    assert_nil @repo.read("new-existing-branch.txt"), "New file not on default branch"
    assert_equal 6, @repo.list.length, "6 items on default branch"

    assert_equal @bare_repo.references['refs/heads/packed'].target.oid, @repo.repository.references['refs/heads/packed'].target.oid, "ref pushed"
  end

  def test_write_on_a_new_branch
    assert @repo.write("test-create-new-file", "b", :branch => "new-branch", :message => "test_write")
    assert_equal "b", @repo.read("test-create-new-file", :branch => "new-branch")[:value], "Write to new file on new branch"
    assert_equal 7, @repo.list(branch: "new-branch").length, "7 items on new branch"
    assert_equal 6, @repo.list.length, "6 items on default branch"
    assert_nil @repo.read("test-create-new-file"), "New file not on default branch"
    assert_equal @bare_repo.references['refs/heads/new-branch'].target.oid, @repo.repository.references['refs/heads/new-branch'].target.oid, "ref pushed"
  end

  def test_delete_on_existing_branch
    assert @repo.write("test-create-new-file", "b", :branch => "new-branch", :message => "test_write")
    assert_equal 7, @repo.list(branch: "new-branch").length, "7 items on new branch after write"
    old_oid = @bare_repo.references['refs/heads/new-branch'].target.oid
    assert @repo.delete("test-create-new-file", :branch => "new-branch", :message => "test_delete")
    assert_equal 6, @repo.list(branch: "new-branch").length, "6 items on new branch after delete"
    refute_equal old_oid, @bare_repo.references['refs/heads/new-branch'].target.oid, "A commit was created"
  end

  def test_delete_on_new_branch
    assert @repo.write("test-create-new-file", "b", :message => "test_write")
    assert @repo.delete("test-create-new-file", :branch => "new-branch", :message => "test_delete")
    assert_equal 7, @repo.list.length, "7 items on default branch after write and delete"
    assert_equal 6, @repo.list(branch: "new-branch").length, "6 items on new branch after delete"
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
    FileUtils.remove_entry_secure(@tmp_path2)
  end
end



