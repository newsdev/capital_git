require 'test_helper'
require 'tmpdir'
require 'json'

class CapitalGitBranchesTest < Minitest::Test
  def setup
    @tmp_path = Dir.mktmpdir("capital-git-test-repos")
    @fixtures_path = File.expand_path("fixtures", File.dirname(__FILE__))
    @database = CapitalGit::Database.new({:local_path => @tmp_path})
    @repo = @database.connect("#{@fixtures_path}/testrepo.git")
  end

  def test_list_branches
    branches = @repo.branches
    
    assert_equal 2, branches.count
    assert_equal ["master", "packed"], branches.map {|b| b[:name] }

    assert_equal JSON.parse('[{"name":"master","commit":{"commit":"36060c58702ed4c2a40832c51758d5344201d89a","message":"subdirectories\n","author":{"name":"Scott Chacon","email":"schacon@gmail.com","time":"2010-10-26 15:44:21 -0200"},"committer":{"name":"Scott Chacon","email":"schacon@gmail.com","time":"2010-10-26 15:44:21 -0200"},"time":"2010-10-26 13:44:21 -0400"},"head?":true}, {"name":"packed","commit":{"commit":"41bc8c69075bbdb46c5c6f0566cc8cc5b46e8bd9","message":"packed commit two\n","author":{"name":"Scott Chacon","email":"schacon@gmail.com","time":"2010-05-11 13:40:41 -0700"},"committer":{"name":"Scott Chacon","email":"schacon@gmail.com","time":"2010-05-11 13:40:41 -0700"},"time":"2010-05-11 16:40:41 -0400"},"head?":false}]'),
      JSON.parse(branches.to_json)
  end

  def test_branches_with_base
    branches = @repo.branches(base: "master")

    assert_equal ["master", "packed"], branches.map {|b| b[:name] }
    # assert_equal 1, branches.map {|b| b[:stats]}.compact.count
    assert_equal [0,8], branches.map {|b| b[:diff][:files_changed]}
    
    assert_equal 2, branches.count
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


  def test_create_branch
    branch_name = @repo.create_branch[:name]
    # puts branch_name
    refute_nil branch_name
    assert_equal @repo.read_all, @repo.read_all(branch: branch_name)
    assert_equal ["master", "packed", branch_name].sort, @repo.branches.map {|b| b[:name] }.sort

    branch_name2 = @repo.create_branch(:head => "packed")[:name]
    refute_nil branch_name2
    assert_equal @repo.read_all(branch: "packed"), @repo.read_all(branch: branch_name2)
    assert_equal ["master", "packed", branch_name, branch_name2].sort, @repo.branches.map {|b| b[:name] }.sort
  end

  def test_delete_branch
    branch_name = @repo.create_branch[:name]
    refute_nil branch_name
    assert_equal @repo.read_all, @repo.read_all(branch: branch_name)
    assert_equal ["master", "packed", branch_name].sort, @repo.branches.map {|b| b[:name] }.sort

    @repo.delete_branch(branch_name)
    assert_equal ["master", "packed"].sort, @repo.branches.map {|b| b[:name] }.sort
  end

  def test_find_branches
    branch_name = @repo.create_branch[:name]
    assert @repo.write("README", "brand new readme\n", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "first commit on new branch"
      })
    refute_equal @repo.read_all, @repo.read_all(branch: branch_name)

    assert_equal [branch_name], @repo.branches(author_email: "albert.sun@nytimes.com").map {|b| b[:name] }
    assert_equal [branch_name], @repo.branches(author_name: "A").map {|b| b[:name] }
    assert_equal [], @repo.branches(author_email: "tester@example.com").map {|b| b[:name] }
    assert_equal ["master", "packed", branch_name].sort, @repo.branches.map {|b| b[:name] }.sort

    assert @repo.write("README", "brand new readme\nwith a second line\n", {
        :branch => branch_name,
        :author => {:email => "tester@example.com", :name => "T"},
        :message => "second commit on new branch"
      })
    assert_equal [branch_name], @repo.branches(author_email: "albert.sun@nytimes.com").map {|b| b[:name] }
    assert_equal [branch_name], @repo.branches(author_name: "A").map {|b| b[:name] }
    assert_equal [branch_name], @repo.branches(author_email: "tester@example.com").map {|b| b[:name] }
  end


  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
    FileUtils.remove_entry_secure(@tmp_path2)
  end
end
