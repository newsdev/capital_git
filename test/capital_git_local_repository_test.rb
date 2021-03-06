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
    @repo.log
    assert Dir.exists? @repo.local_path
    assert_kind_of Rugged::Repository, @repo.repository
  end

  def test_paths
    assert_equal @repo.local_path, File.join(@tmp_path, "testrepo")
    assert_equal @repo.remote_url, "#{@fixtures_path}/testrepo.git"
  end

  def test_listing_items
    assert_equal [
        {:entry=>{:name=>"README", :oid=>"1385f264afb75a56a5bec74243be9b367ba4ca08"}, :path=>"README"},
        {:entry=>{:name=>"new.txt", :oid=>"fa49b077972391ad58037050f2a75f74e3671e92"}, :path=>"new.txt"},
        {:entry=>{:name=>"README", :oid=>"1385f264afb75a56a5bec74243be9b367ba4ca08"}, :path=>"subdir/README"},
        {:entry=>{:name=>"new.txt", :oid=>"fa49b077972391ad58037050f2a75f74e3671e92"}, :path=>"subdir/new.txt"},
        {:entry=>{:name=>"README", :oid=>"1385f264afb75a56a5bec74243be9b367ba4ca08"}, :path=>"subdir/subdir2/README"},
        {:entry=>{:name=>"new.txt", :oid=>"fa49b077972391ad58037050f2a75f74e3671e92"}, :path=>"subdir/subdir2/new.txt"}
      ], @repo.list, "Git list items works"
  end

  def test_log
    assert_equal [
        {
          "message"=>"subdirectories\n",
          "author"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-10-26 15:44:21 -0200"},
          "committer"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-10-26 15:44:21 -0200"},
          "time"=>"2010-10-26 13:44:21 -0400", "commit"=>"36060c58702ed4c2a40832c51758d5344201d89a"
        },
        {
          "message"=>"another commit\n",
          "author"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-05-11 13:38:42 -0700"},
          "committer"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-05-11 13:38:42 -0700"},
          "time"=>"2010-05-11 16:38:42 -0400", "commit"=>"5b5b025afb0b4c913b4c338a42934a3863bf3644"
        },
        {
          "message"=>"testing\n",
          "author"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-05-08 16:13:06 -0700"},
          "committer"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-05-08 16:13:06 -0700"},
          "time"=>"2010-05-08 19:13:06 -0400", "commit"=>"8496071c1b46c854b31185ea97743be6a8774479"
        }
      ], JSON.parse(@repo.log.to_json), "Git log works"

    # this silly json round trip is to convert symbols to strings and dates to right format

    assert_equal [
        {
          "message"=>"subdirectories\n",
          "author"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-10-26 15:44:21 -0200"},
          "committer"=>{"name"=>"Scott Chacon", "email"=>"schacon@gmail.com", "time"=>"2010-10-26 15:44:21 -0200"},
          "time"=>"2010-10-26 13:44:21 -0400", "commit"=>"36060c58702ed4c2a40832c51758d5344201d89a"
        }
      ], JSON.parse(@repo.log(:limit => 1).to_json), "Git log works"

    log_item = @repo.log.first
    assert_equal [:message, :author, :committer, :time, :commit].sort, log_item.keys.sort
    assert_kind_of Time, log_item[:time]
  end

  def test_read
    item = @repo.read("README")
    assert_equal "hey\n", item[:value]
    assert_equal [:value, :entry, :commits], item.keys
    assert_equal({:name=>"README", :oid=>"1385f264afb75a56a5bec74243be9b367ba4ca08"}, item[:entry])
    assert_equal 1, item[:commits].length
    assert_equal "8496071c1b46c854b31185ea97743be6a8774479", item[:commits].first[:commit]

    assert_equal @repo.read("new.txt")[:commits].length, 1

    assert_nil @repo.read("nonexistent.txt"), "Read returns nil when object doesn't exist"
  end

  def test_read_sha
    item = @repo.read("README", { :sha => "8496071c1b46c854b31185ea97743be6a8774479" })
    assert_equal "hey\n", item[:value]
    assert_equal [:value, :entry, :commits], item.keys
    assert_equal({:name=>"README", :oid=>"1385f264afb75a56a5bec74243be9b367ba4ca08"}, item[:entry])
    assert_equal 1, item[:commits].length
    assert_equal "8496071c1b46c854b31185ea97743be6a8774479", item[:commits].first[:commit]

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

  def test_read_all_sha
    flat = [
        {:path => "README", :value => "hey\n"}
      ]
    tree = {
        "README" => {:path => "README", :value => "hey\n"}
      }

    assert_equal flat, @repo.read_all({ :sha => "8496071c1b46c854b31185ea97743be6a8774479" })
    assert_equal flat, @repo.read_all({ :mode => :flat, :sha => "8496071c1b46c854b31185ea97743be6a8774479" })
    assert_equal tree, @repo.read_all({ :mode => :tree, :sha => "8496071c1b46c854b31185ea97743be6a8774479" })
  end

  def test_show
    refute_nil @repo.show 

    assert_equal @repo.show, @repo.show("36060c58702ed4c2a40832c51758d5344201d89a")
    assert_equal @repo.show, @repo.show(nil, :branch => "master")
    refute_equal @repo.show, @repo.show("5b5b025afb0b4c913b4c338a42934a3863bf3644")

    refute_nil @repo.show @repo.log[0][:commit]
    refute_nil @repo.show @repo.log[1][:commit]
    refute_nil @repo.show @repo.log[2][:commit]

    show_val = {
      :commit=>"36060c58702ed4c2a40832c51758d5344201d89a",
      :message=>"subdirectories\n",
      :author=>{:name=>"Scott Chacon", :email=>"schacon@gmail.com", :time=>Time.parse("2010-10-26 13:44:21 -0400")},
      :committer=>{:name=>"Scott Chacon", :email=>"schacon@gmail.com", :time=>Time.parse("2010-10-26 13:44:21 -0400")},
      :time=>Time.parse("2010-10-26 13:44:21 -0400"),
      :diff => {
        :files_changed=>4, :additions=>4, :deletions=>0,
        :changes=>{:added=>[{:old_path=>"subdir/README", :new_path=>"subdir/README", :patch=>"diff --git a/subdir/README b/subdir/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/README\n@@ -0,0 +1 @@\n+hey\n", :additions=>1, :deletions=>0},{:old_path=>"subdir/new.txt", :new_path=>"subdir/new.txt", :patch=>"diff --git a/subdir/new.txt b/subdir/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/subdir/new.txt\n@@ -0,0 +1 @@\n+new file\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/subdir2/README", :new_path=>"subdir/subdir2/README", :patch=>"diff --git a/subdir/subdir2/README b/subdir/subdir2/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/subdir2/README\n@@ -0,0 +1 @@\n+hey\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/subdir2/new.txt", :new_path=>"subdir/subdir2/new.txt", :patch=>"diff --git a/subdir/subdir2/new.txt b/subdir/subdir2/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/subdir/subdir2/new.txt\n@@ -0,0 +1 @@\n+new file\n", :additions=>1, :deletions=>0}]}
      }
    }

    assert_equal show_val, @repo.show
  end

  def test_diff

    # no changes on diff to head 
    diff_val = {:commits => ["36060c58702ed4c2a40832c51758d5344201d89a", "36060c58702ed4c2a40832c51758d5344201d89a"], :files_changed=>0, :additions=>0, :deletions=>0, :changes=>{}}
    assert_equal diff_val, @repo.diff(@repo.log[0][:commit])

    diff_val = {:commits=>["5b5b025afb0b4c913b4c338a42934a3863bf3644", "36060c58702ed4c2a40832c51758d5344201d89a"], :files_changed=>4, :additions=>4, :deletions=>0, :changes=>{:added=>[{:old_path=>"subdir/README", :new_path=>"subdir/README", :patch=>"diff --git a/subdir/README b/subdir/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/README\n@@ -0,0 +1 @@\n+hey\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/new.txt", :new_path=>"subdir/new.txt", :patch=>"diff --git a/subdir/new.txt b/subdir/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/subdir/new.txt\n@@ -0,0 +1 @@\n+new file\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/subdir2/README", :new_path=>"subdir/subdir2/README", :patch=>"diff --git a/subdir/subdir2/README b/subdir/subdir2/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/subdir2/README\n@@ -0,0 +1 @@\n+hey\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/subdir2/new.txt", :new_path=>"subdir/subdir2/new.txt", :patch=>"diff --git a/subdir/subdir2/new.txt b/subdir/subdir2/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/subdir/subdir2/new.txt\n@@ -0,0 +1 @@\n+new file\n", :additions=>1, :deletions=>0}]}}
    assert_equal diff_val, @repo.diff(@repo.log[1][:commit])

    diff_val = {:commits=>["8496071c1b46c854b31185ea97743be6a8774479", "36060c58702ed4c2a40832c51758d5344201d89a"], :files_changed=>5, :additions=>5, :deletions=>0, :changes=>{:added=>[{:old_path=>"new.txt", :new_path=>"new.txt", :patch=>"diff --git a/new.txt b/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/new.txt\n@@ -0,0 +1 @@\n+new file\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/README", :new_path=>"subdir/README", :patch=>"diff --git a/subdir/README b/subdir/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/README\n@@ -0,0 +1 @@\n+hey\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/new.txt", :new_path=>"subdir/new.txt", :patch=>"diff --git a/subdir/new.txt b/subdir/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/subdir/new.txt\n@@ -0,0 +1 @@\n+new file\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/subdir2/README", :new_path=>"subdir/subdir2/README", :patch=>"diff --git a/subdir/subdir2/README b/subdir/subdir2/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/subdir2/README\n@@ -0,0 +1 @@\n+hey\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/subdir2/new.txt", :new_path=>"subdir/subdir2/new.txt", :patch=>"diff --git a/subdir/subdir2/new.txt b/subdir/subdir2/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/subdir/subdir2/new.txt\n@@ -0,0 +1 @@\n+new file\n", :additions=>1, :deletions=>0}]}}
    assert_equal diff_val, @repo.diff(@repo.log[2][:commit])

    # diff between two commits
    diff_val = {:commits => ["5b5b025afb0b4c913b4c338a42934a3863bf3644", "8496071c1b46c854b31185ea97743be6a8774479"], :files_changed=>1, :additions=>0, :deletions=>1, :changes=>{:deleted=>[{:old_path=>"new.txt", :new_path=>"new.txt", :patch=>"diff --git a/new.txt b/new.txt\ndeleted file mode 100644\nindex fa49b07..0000000\n--- a/new.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-new file\n", :additions=>0, :deletions=>1}]}}
    assert_equal diff_val, @repo.diff(@repo.log[1][:commit], @repo.log[2][:commit])

    # confine changes to specific path
    diff_val = {:commits=>["8496071c1b46c854b31185ea97743be6a8774479", "36060c58702ed4c2a40832c51758d5344201d89a"], :files_changed=>2, :additions=>2, :deletions=>0, :changes=>{:added=>[{:old_path=>"subdir/README", :new_path=>"subdir/README", :patch=>"diff --git a/subdir/README b/subdir/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/README\n@@ -0,0 +1 @@\n+hey\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/subdir2/README", :new_path=>"subdir/subdir2/README", :patch=>"diff --git a/subdir/subdir2/README b/subdir/subdir2/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/subdir2/README\n@@ -0,0 +1 @@\n+hey\n", :additions=>1, :deletions=>0}]}}
    opts = {:paths => ['*README']}
    assert_equal diff_val, @repo.diff(@repo.log[2][:commit], nil, opts)

  end

  def test_diff_branches
    diff_val = {:commits=>["41bc8c69075bbdb46c5c6f0566cc8cc5b46e8bd9", "36060c58702ed4c2a40832c51758d5344201d89a"], :files_changed=>8, :additions=>6, :deletions=>2, :changes=>{:added=>[{:old_path=>"README", :new_path=>"README", :patch=>"diff --git a/README b/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/README\n@@ -0,0 +1 @@\n+hey\n", :additions=>1, :deletions=>0}, {:old_path=>"new.txt", :new_path=>"new.txt", :patch=>"diff --git a/new.txt b/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/new.txt\n@@ -0,0 +1 @@\n+new file\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/README", :new_path=>"subdir/README", :patch=>"diff --git a/subdir/README b/subdir/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/README\n@@ -0,0 +1 @@\n+hey\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/new.txt", :new_path=>"subdir/new.txt", :patch=>"diff --git a/subdir/new.txt b/subdir/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/subdir/new.txt\n@@ -0,0 +1 @@\n+new file\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/subdir2/README", :new_path=>"subdir/subdir2/README", :patch=>"diff --git a/subdir/subdir2/README b/subdir/subdir2/README\nnew file mode 100644\nindex 0000000..1385f26\n--- /dev/null\n+++ b/subdir/subdir2/README\n@@ -0,0 +1 @@\n+hey\n", :additions=>1, :deletions=>0}, {:old_path=>"subdir/subdir2/new.txt", :new_path=>"subdir/subdir2/new.txt", :patch=>"diff --git a/subdir/subdir2/new.txt b/subdir/subdir2/new.txt\nnew file mode 100644\nindex 0000000..fa49b07\n--- /dev/null\n+++ b/subdir/subdir2/new.txt\n@@ -0,0 +1 @@\n+new file\n", :additions=>1, :deletions=>0}], :deleted=>[{:old_path=>"another.txt", :new_path=>"another.txt", :patch=>"diff --git a/another.txt b/another.txt\ndeleted file mode 100644\nindex 7c3f1a8..0000000\n--- a/another.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-yet another file\n", :additions=>0, :deletions=>1}, {:old_path=>"second.txt", :new_path=>"second.txt", :patch=>"diff --git a/second.txt b/second.txt\ndeleted file mode 100644\nindex bb61d81..0000000\n--- a/second.txt\n+++ /dev/null\n@@ -1 +0,0 @@\n-what file?\n", :additions=>0, :deletions=>1}]}}
    assert_equal diff_val, @repo.diff("packed")

    assert_equal diff_val, @repo.diff("packed", "master")
  end


  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
  end
end

class CapitalGitLocalPullTest < Minitest::Test
  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    @fixtures_path = File.expand_path("fixtures", File.dirname(__FILE__))
    @database = CapitalGit::Database.new({:local_path => @tmp_path})
    
  end

  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
  end

  def test_pull_sequence
    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
    refute_nil @repo
    refute Dir.exists? @repo.local_path
    assert @repo.repository
    assert Dir.exists? @repo.local_path
    assert_kind_of Rugged::Repository, @repo.repository
  end

  def test_pull_sequence2
    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
    refute_nil @repo
    refute Dir.exists? @repo.local_path
    assert @repo.log
    assert Dir.exists? @repo.local_path
    assert_kind_of Rugged::Repository, @repo.repository
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
    write_commit = @repo.write("test-create-new-file","b", :message => "test_write")
    assert write_commit, "write succeeds"
    refute_nil write_commit[:commit]
    assert_equal "b", @repo.read("test-create-new-file")[:value], "Write to new file"
    assert_equal @repo.log[0][:commit], write_commit[:commit]

    assert @repo.write("README", "fancy fancy", :message => "Update readme")
    assert_equal "fancy fancy", @repo.read("README")[:value], "Write to existing file"


    # test that it pushed
    # and that commit id's of the source and local copy match
    assert_equal @bare_repo.head.target.oid, @repo.repository.head.target.oid
  end

  def test_write_encoding
    assert @repo.write("README", "a curly quote’s bug", :message => "Update readme’s contents\n")
    assert_equal "a curly quote’s bug", @repo.read("README")[:value], "Write to existing file"
    assert_equal "Update readme’s contents\n", @repo.show[:message], "Write has the right commit message with curly quote"

    assert_equal(
        JSON.parse(@repo.show.to_json)["diff"]["changes"]["modified"][0]["patch"],
        "diff --git a/README b/README\nindex 1385f26..85eb8bc 100644\n--- a/README\n+++ b/README\n@@ -1 +1 @@\n-hey\n+a curly quote’s bug\n\\ No newline at end of file\n",
        "patch from show can be output as UTF-8"
      )

    assert_equal @repo.show[:diff][:changes][:modified][0][:old_path], "README"
    assert_equal @repo.show[:diff][:changes][:modified][0][:new_path], "README"
  end

  def test_write_many
    write_result = @repo.write_many([
      {:path => "test-create-new-file", :value => "b"},
      {:path => "README", :value => "write_many hello world\n"}
      ], :message => "test_write")
    assert write_result, "write_many on existing repo succeeds"
    refute_nil write_result[:commit]
    assert_equal @repo.log[0][:commit], write_result[:commit]
    assert_equal "b", @repo.read("test-create-new-file")[:value], "write_many to new file succeeded"
    assert_equal "write_many hello world\n", @repo.read("README")[:value], "write_many to existing file succeeded"
    assert_equal 7, @repo.list.length

    assert_equal @bare_repo.head.target.oid, @repo.repository.head.target.oid
  end

  def test_delete
    assert @repo.write("d","hello world", :message => "test_delete write")
    assert_equal "hello world", @repo.read("d")[:value]

    delete_result = @repo.delete("d", :message => "test_delete")
    assert delete_result, "Delete returns true when successfully deleted"
    refute_nil delete_result[:commit]
    assert_equal @repo.log[0][:commit], delete_result[:commit]

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

  def test_write_author
    author = {
        :name=>"Test A. Author", :email=>"author@example.com"
      }
    assert @repo.write("test-create-new-file","b", :message => "test_write", :author => author), "write succeeds with an author"
    
    assert_equal "b", @repo.read("test-create-new-file")[:value], "Write to new file"

    assert_equal author[:name], @repo.read("test-create-new-file")[:commits].first[:author][:name], "Author is set"
    assert_equal author[:email], @repo.read("test-create-new-file")[:commits].first[:author][:email], "Author is set"
    refute_equal author[:name], @repo.read("test-create-new-file")[:commits].first[:committer][:name], "Committer was not set to author"
    refute_equal author[:email], @repo.read("test-create-new-file")[:commits].first[:committer][:email], "Committer was not set to author"
    assert_equal author[:name], @repo.log.first[:author][:name], "Author is set"
    assert_equal author[:email], @repo.log.first[:author][:email], "Author is set"
    refute_equal author[:name], @repo.log.first[:committer][:name], "Committer was not set to author"
    refute_equal author[:email], @repo.log.first[:committer][:email], "Committer was not set to author"

    assert_equal [:name, :email, :time], @repo.read("test-create-new-file")[:commits].first[:author].keys
    assert @repo.read("test-create-new-file")[:commits].first[:author][:time].is_a?(Time), "commit author has a Time"

    refute_equal author[:name], @repo.read("README")[:commits].first[:committer][:name], "Doesn't affect log for a different file"
    refute_equal author[:email], @repo.read("README")[:commits].first[:committer][:email], "Doesn't affect log for a different file"
  end

  def test_write_many_author
    author = {
      :name=>"Prolific A. Author", :email=>"prolific@example.com"
    }

    # new.txt
    assert @repo.write_many([
      {:path => "test-create-new-file", :value => "abc"},
      {:path => "README", :value => "hello world\n"}
      ], :message => "test_write", :author => author), "write_many with author option succeeds"

    assert_equal author[:name], @repo.read("test-create-new-file")[:commits].first[:author][:name], "Author is set"
    assert_equal author[:email], @repo.read("test-create-new-file")[:commits].first[:author][:email], "Author is set"
    assert_equal author[:name], @repo.read("README")[:commits].first[:author][:name], "Author is set"
    assert_equal author[:email], @repo.read("README")[:commits].first[:author][:email], "Author is set"
    refute_equal author[:name], @repo.read("new.txt")[:commits].first[:author][:name], "Author is not updated for other file"
    refute_equal author[:email], @repo.read("new.txt")[:commits].first[:author][:email], "Author is not updated for other file"
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

