require 'test_helper'
require 'tmpdir'
require 'json'

# branch_name = repo.create_branch
# repo.write(.... :branch => branch_name)
# proposal_id = @repo.propose("README", "just a thought", :message => "a proposed edit") # branch
#
# array_of_proposals = @repo.branches
# array_of_proposals = @repo.branches(:paths => ["README"]) # branches where README changed
# @repo.merge_branch(array_of_proposals[:name]) # merge
# 
# @repo.branches(:author_email => "TKTK@example.com")

class CapitalGitHeadMergeTest < Minitest::Test
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

  def test_ff_merge
    branch_name = @repo.create_branch[:name]
    assert @repo.write("README", "brand new readme\n", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "first commit on new branch"
      })
    refute_equal @repo.read_all, @repo.read_all(branch: branch_name)

    last_commit_sha = @repo.log(branch: branch_name)[0][:commit]
    refute_equal last_commit_sha, @repo.log[0][:commit]

    merge_result = @repo.merge_branch(branch_name)
    refute_nil merge_result

    assert_equal last_commit_sha, merge_result[:commit]
    assert_equal last_commit_sha, @repo.log[0][:commit]

    assert_equal "brand new readme\n", @repo.read("README")[:value]
  end

  def test_merge_preview
    merge_base = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :message => "create sandwich"
      })
    branch_name = @repo.create_branch[:name]
    orig_head = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nBacon\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "a commit on master (add Bacon)"
      })
    merge_head = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "B"},
        :message => "a commit on branch (normal mustard)"
      })

    # merge preview shows the diff between merge_base and merge_head
    diff_val = {:commits => [merge_base[:commit], merge_head[:commit]], :files_changed=>1, :additions=>1, :deletions=>1, :changes=>{:modified=>[{:old_path=>"sandwich.txt", :new_path=>"sandwich.txt", :patch=>"diff --git a/sandwich.txt b/sandwich.txt\nindex c76e978..d41fe58 100644\n--- a/sandwich.txt\n+++ b/sandwich.txt\n@@ -3,5 +3,5 @@ Mayonnaise\n Lettuce\n Tomato\n Provolone\n-Creole Mustard\n+Mustard\n Bottom piece of bread\n\\ No newline at end of file\n", :additions=>1, :deletions=>1}]}}
    merge_preview_diff = @repo.merge_preview(branch_name)
    regular_diff = @repo.diff(merge_base[:commit], merge_head[:commit])

    assert_equal regular_diff, merge_preview_diff
    assert_equal diff_val, merge_preview_diff
  end

  def test_auto_merge
    merge_base_sha = @repo.log[0][:commit]

    @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :message => "create sandwich"
      })
    assert_equal "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", @repo.read("sandwich.txt")[:value], "sanity check"

    branch_name = @repo.create_branch[:name]
    @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nBacon\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "a commit on master (add Bacon)"
      })
    @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "B"},
        :message => "a commit on branch (normal mustard)"
      })
    

    head_commit_sha = @repo.log[0][:commit]
    branch_commit_sha = @repo.log(branch: branch_name)[0][:commit]

    refute_equal @repo.read_all, @repo.read_all(branch: branch_name)
    refute_equal @repo.log[0][:commit], @repo.log(branch: branch_name)[0][:commit]
    refute_equal merge_base_sha, @repo.log[0][:commit]

    merge_result = @repo.merge_branch(branch_name, message: "This is an automerge!")
    refute_nil merge_result

    # @repo.log(limit: 3).each {|c| puts c.inspect}
    # puts @repo.read_all
    assert_equal "Top piece of bread\nMayonnaise\nBacon\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", @repo.read("sandwich.txt")[:value]

    assert_equal @repo.log[0][:commit], merge_result[:commit]
    refute_equal @repo.log[0][:commit], head_commit_sha
    refute_equal @repo.log[0][:commit], branch_commit_sha
    assert_equal branch_commit_sha, @repo.log(branch: branch_name)[0][:commit]
    assert_equal @repo.log[1][:commit], branch_commit_sha
    assert_equal @repo.log[2][:commit], head_commit_sha
  end

  def test_conflict_merge
    merge_base = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :message => "create sandwich"
      })
    assert_equal "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", @repo.read("sandwich.txt")[:value], "sanity check"

    branch_name = @repo.create_branch[:name]
    orig_head = @repo.write("sandwich.txt", "Top piece of bread\nAvocado\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "a commit on master (add Bacon)"
      })
    merge_head = @repo.write("sandwich.txt", "Top piece of bread\nKetchup\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "B"},
        :message => "a commit on branch (normal mustard)"
      })

    head_commit_sha = @repo.log[0][:commit]
    branch_commit_sha = @repo.log(branch: branch_name)[0][:commit]

    refute_equal @repo.read_all, @repo.read_all(branch: branch_name)
    refute_equal @repo.log[0][:commit], @repo.log(branch: branch_name)[0][:commit]
    refute_equal merge_base[:commit], @repo.log[0][:commit]

    merge_result = @repo.merge_branch(branch_name, message: "attempting an automerge!")
    # puts merge_result
    refute_nil merge_result
    assert_equal false, merge_result[:success]
    assert_equal [:success, :orig_head, :merge_head, :merge_base, :conflicts].sort, merge_result.keys.sort
    assert_equal merge_base, merge_result[:merge_base]
    assert_equal orig_head, merge_result[:orig_head]
    assert_equal merge_head, merge_result[:merge_head]
    assert_equal 1, merge_result[:conflicts].count
    assert_equal [:merge_file, :path, :ancestor, :ours, :theirs].sort, merge_result[:conflicts][0].keys.sort
  end

  def test_write_merge_branch
    merge_base = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :message => "create sandwich"
      })
    branch_name = @repo.create_branch[:name]
    orig_head = @repo.write("sandwich.txt", "Top piece of bread\nAvocado\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "a commit on master (add avocado)"
      })
    merge_head = @repo.write("sandwich.txt", "Top piece of bread\nKetchup\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "B"},
        :message => "a commit on branch (add ketchup, change mustard)"
      })

    conflicted_merge = @repo.merge_branch(branch_name, message: "attempting an automerge!")

    files = [
      {:path => "sandwich.txt", :value => "Top piece of bread\nKetchup\nAvocado\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread"}
      ]

    commit_msg = "Resolved conflicts and merged\n"
    merge_result, msg = @repo.write_merge_branch(files, branch_name, conflicted_merge[:orig_head][:commit], conflicted_merge[:merge_head][:commit], {:message => commit_msg})

    assert_equal @repo.log[0], merge_result
    assert_equal @repo.log[1], merge_head
    assert_equal @repo.log[2], orig_head
    assert_equal commit_msg, merge_result[:message]
    assert_equal "Top piece of bread\nKetchup\nAvocado\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", @repo.read("sandwich.txt")[:value]
    # puts @repo.read_all
    # puts @repo.log
  end


  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
    FileUtils.remove_entry_secure(@tmp_path2)
  end
end


class CapitalGitBaseMergeTest < Minitest::Test
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
    @base_branch = "packed"
  end

  def test_ff_merge
    master_readme = @repo.read("README")[:value]
    master_commit = @repo.log[0]

    branch_name = @repo.create_branch(:head => @base_branch)[:name]
    assert @repo.write("README", "brand new readme\n", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "commit to be ffwed"
      })
    last_commit_sha = @repo.log(branch: branch_name)[0][:commit]
    refute_equal last_commit_sha, @repo.log(branch: @base_branch)[0][:commit]

    merge_result = @repo.merge_branch(branch_name, {head: @base_branch})
    refute_nil merge_result

    assert_equal "brand new readme\n", @repo.read("README", :branch => @base_branch)[:value]
    assert_equal last_commit_sha, merge_result[:commit]
    assert_equal last_commit_sha, @repo.log(branch: @base_branch)[0][:commit]

    # make sure that the reset head hasn't screwed up other things related to default branch
    assert_equal master_commit, @repo.log[0]
    assert_equal master_readme, @repo.read("README")[:value]
  end

  def test_merge_preview
    master_readme = @repo.read("README")[:value]
    master_commit = @repo.log[0]

    merge_base = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :message => "create sandwich",
        :branch => @base_branch
      })
    branch_name = @repo.create_branch(head: @base_branch)[:name]
    orig_head = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nBacon\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :branch => @base_branch,
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "a commit on base_branch (add Bacon)"
      })
    merge_head = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "B"},
        :message => "a commit on branch (normal mustard)"
      })

    # merge preview shows the diff between merge_base and merge_head
    diff_val = {:commits => [merge_base[:commit], merge_head[:commit]], :files_changed=>1, :additions=>1, :deletions=>1, :changes=>{:modified=>[{:old_path=>"sandwich.txt", :new_path=>"sandwich.txt", :patch=>"diff --git a/sandwich.txt b/sandwich.txt\nindex c76e978..d41fe58 100644\n--- a/sandwich.txt\n+++ b/sandwich.txt\n@@ -3,5 +3,5 @@ Mayonnaise\n Lettuce\n Tomato\n Provolone\n-Creole Mustard\n+Mustard\n Bottom piece of bread\n\\ No newline at end of file\n", :additions=>1, :deletions=>1}]}}
    merge_preview_diff = @repo.merge_preview(branch_name, {head: @base_branch})
    regular_diff = @repo.diff(merge_base[:commit], merge_head[:commit])

    assert_equal regular_diff, merge_preview_diff
    assert_equal diff_val, merge_preview_diff

    # make sure that the reset head hasn't screwed up other things related to default branch
    assert_equal master_commit, @repo.log[0]
    assert_equal master_readme, @repo.read("README")[:value]
  end

  def test_auto_merge
    master_readme = @repo.read("README")[:value]
    master_commit = @repo.log[0]

    merge_base_sha = @repo.log(branch: @base_branch)[0][:commit]

    @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :message => "create sandwich",
        :branch => @base_branch
      })
    branch_name = @repo.create_branch(head: @base_branch)[:name]
    @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nBacon\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :branch => @base_branch,
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "a commit on base_branch (add Bacon)"
      })
    @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "B"},
        :message => "a commit on branch (normal mustard)"
      })

    head_commit_sha = @repo.log(branch: @base_branch)[0][:commit]
    branch_commit_sha = @repo.log(branch: branch_name)[0][:commit]

    refute_equal @repo.read_all(branch: @base_branch), @repo.read_all(branch: branch_name)
    refute_equal @repo.log(branch: @base_branch)[0][:commit], @repo.log(branch: branch_name)[0][:commit]
    refute_equal merge_base_sha, @repo.log(branch: @base_branch)[0][:commit]

    merge_result = @repo.merge_branch(branch_name, {head: @base_branch, message: "This is an automerge!"})
    refute_nil merge_result

    assert_equal "Top piece of bread\nMayonnaise\nBacon\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", @repo.read("sandwich.txt", branch: @base_branch)[:value]

    assert_equal @repo.log(branch: @base_branch)[0][:commit], merge_result[:commit]
    refute_equal @repo.log(branch: @base_branch)[0][:commit], head_commit_sha
    refute_equal @repo.log(branch: @base_branch)[0][:commit], branch_commit_sha
    assert_equal branch_commit_sha, @repo.log(branch: branch_name)[0][:commit]
    assert_equal @repo.log(branch: @base_branch)[1][:commit], branch_commit_sha
    assert_equal @repo.log(branch: @base_branch)[2][:commit], head_commit_sha

    # make sure that the reset head hasn't screwed up other things related to default branch
    assert_equal master_commit, @repo.log[0]
    assert_equal master_readme, @repo.read("README")[:value]
  end

  def test_conflict_merge
    merge_base = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :message => "create sandwich",
        :branch => @base_branch
      })
    branch_name = @repo.create_branch(head: @base_branch)[:name]
    orig_head = @repo.write("sandwich.txt", "Top piece of bread\nAvocado\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :branch => @base_branch,
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "a commit on base_branch (add Bacon)"
      })
    merge_head = @repo.write("sandwich.txt", "Top piece of bread\nKetchup\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "B"},
        :message => "a commit on new branch (normal mustard)"
      })

    head_commit_sha = @repo.log(branch: @base_branch)[0][:commit]
    branch_commit_sha = @repo.log(branch: branch_name)[0][:commit]

    refute_equal @repo.read_all(branch: @base_branch), @repo.read_all(branch: branch_name)
    refute_equal @repo.log(branch: @base_branch)[0][:commit], @repo.log(branch: branch_name)[0][:commit]
    refute_equal merge_base[:commit], @repo.log(branch: @base_branch)[0][:commit]

    merge_result = @repo.merge_branch(branch_name, {head: @base_branch, message: "attempting an automerge!"})
    # puts merge_result
    refute_nil merge_result
    assert_equal false, merge_result[:success]
    assert_equal [:success, :orig_head, :merge_head, :merge_base, :conflicts].sort, merge_result.keys.sort
    assert_equal merge_base, merge_result[:merge_base]
    assert_equal orig_head, merge_result[:orig_head]
    assert_equal merge_head, merge_result[:merge_head]
    assert_equal 1, merge_result[:conflicts].count
    assert_equal [:merge_file, :path, :ancestor, :ours, :theirs].sort, merge_result[:conflicts][0].keys.sort
  end

  def test_write_merge_branch
    master_readme = @repo.read("README")[:value]
    master_commit = @repo.log[0]

    merge_base = @repo.write("sandwich.txt", "Top piece of bread\nMayonnaise\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :message => "create sandwich",
        :branch => @base_branch
      })
    branch_name = @repo.create_branch(head: @base_branch)[:name]
    orig_head = @repo.write("sandwich.txt", "Top piece of bread\nAvocado\nLettuce\nTomato\nProvolone\nCreole Mustard\nBottom piece of bread", {
        :branch => @base_branch,
        :author => {:email => "albert.sun@nytimes.com", :name => "A"},
        :message => "a commit on base_branch (add Bacon)"
      })
    merge_head = @repo.write("sandwich.txt", "Top piece of bread\nKetchup\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", {
        :branch => branch_name,
        :author => {:email => "albert.sun@nytimes.com", :name => "B"},
        :message => "a commit on new branch (normal mustard)"
      })

    conflicted_merge = @repo.merge_branch(branch_name, {head: @base_branch, message: "attempting an automerge!"})

    files = [
      {:path => "sandwich.txt", :value => "Top piece of bread\nKetchup\nAvocado\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread"}
      ]

    commit_msg = "Resolved conflicts and merged\n"
    merge_result, msg = @repo.write_merge_branch(files, branch_name, conflicted_merge[:orig_head][:commit], conflicted_merge[:merge_head][:commit], {:head => @base_branch, :message => commit_msg})

    assert_equal @repo.log(branch: @base_branch)[0], merge_result
    assert_equal @repo.log(branch: @base_branch)[1], merge_head
    assert_equal @repo.log(branch: @base_branch)[2], orig_head
    assert_equal commit_msg, merge_result[:message]
    assert_equal "Top piece of bread\nKetchup\nAvocado\nLettuce\nTomato\nProvolone\nMustard\nBottom piece of bread", @repo.read("sandwich.txt", branch: @base_branch)[:value]

    # make sure that the reset head hasn't screwed up other things related to default branch
    assert_equal master_commit, @repo.log[0]
    assert_equal master_readme, @repo.read("README")[:value]
  end


  def teardown
    FileUtils.remove_entry_secure(@tmp_path)
    FileUtils.remove_entry_secure(@tmp_path2)
  end
end