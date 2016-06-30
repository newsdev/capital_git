CapitalGit
-----------

Implementing revisions and workflows for text and written documents in a normal database kind of sucks. Git does it so well, why not use it for things we write in human language too? Unfortunately teaching most writers to work on the command line seems to be a non-starter, so let's build higher-level interfaces for them.

CapitalGit provides a database adapter like interface into a remote git repository. It's a higher-level abstraction wrapping the [Rugged](https://github.com/libgit2/rugged) gem which itself wraps the [libgit2](http://github.com/libgit2/libgit2/) library.

Building a CMS shaped tool for a small number of users? Try plugging CapitalGit in instead of MongoDB or MySQL.

Or run the included Sinatra app in server mode to read and write from repositories over a REST interface. Just provide a configuration file to indicate which remote repositories can be edited.


Gem Mode
========

CapitalGit is installed much like any database. If you're using bundler, add this to your `Gemfile`

```
gem 'capital_git', git: 'git@github.com:newsdev/capital_git.git', branch: 'master'
```

In Rails and Sinatra apps, configuration can be specified in a `config/capitalgit.yml` file. Look at the `config/repos.yml.sample` file here for guidance on syntax. Somewhere during app initialization (like in a `config/initializers/capital_git.rb` file) you'll then need to include this.

```
CapitalGit.load!("config/capitalgit.yml")
```

Now you can interact with repositories like so:

```
# clones/pulls a local copy of git@server.example.com:repo-slug.git
@repo = CapitalGit.connect("git@github.com:newsdev/capital_git_testrepo.git")

# list files
@repo.list

# show commit log
@repo.log

# read a specific file
item = @repo.read("path/to/file.txt")

# string with file contents
item[:value]

# update a file, commit, and push
@repo.write("path/to/file.txt", "new contents\nare here\n",
      :message => "Write and commit"
    )

# each of these methods can take a :branch option to operate on a non-default branch
@repo.list(branch: "some-branch")

# can also see what's changed
@repo.show # equivalent to git show
@repo.show(:branch => "master")
@repo.show(:commit => "9db5b61dd6761c647cb537c7fe2fd8339d80219f")
# returns some commit information
# along with a :changes attribute with arrays of :added, :deleted, :renamed, :modified, etc objects

# simple listing of all paths that changed at HEAD
@repo.show[:diff][:changes].values.flatten.map {|o| o[:new_path]}

# text diffs of each modified (but not added/deleted) file in the latest commit on master
@repo.show(:branch => "master")[:diff][:changes][:modified].map {|o| o[:patch]}

# diff between two commits
@repo.diff(COMMIT_SHA_1, COMMIT_SHA_2)
        {
          :commits => [COMMIT_SHA_1, COMMIT_SHA_2],
          :files_changed => diff.stat[0],
          :additions => diff.stat[1],
          :deletions => diff.stat[2],
          :changes => changes # changes hash
        }

# listing of branches
@repo.branches

# listing of branches, with difference from a specified base branch
@repo.branches("master")


# each of these methods that read the repository will pull from the remote
# to reduce the number of pulls to call multiple in succession use sync
# to ensure everything in the block will see the same repository state
@repo.sync do |repo|
  {
    files: repo.list,
    commits: repo.log
  }
end

```

If you want to manually configure databases and skip the config file:

```
# set up connection information
@db = CapitalGit::Database.new

# optional configuration
@db.credentials = {
  :username => "git",
  :publickey => '...',
  :privatekey => '...',
  :passphrase => "a passphrase goes here"
}
@db.committer = {
  :email => "me@example.com",
  :name => "Me at Work"
}
```

Right now, only local repositories and repositories cloned over ssh with keys specified as a file. Support for HTTP(S) basic auth and SSH agent key support are planned. (Or you could implement it!)

Another caveat, CapitalGit can't initialize new repositories.

Installing the gem provides a `capital_git` binary that can be run as a server by specifying the path to a configuration file.

```
capital_git /path/to/repos.yml
```


### Branching and Merging

You can also work on a branch to test out your changes, then merge it back into `master`.

Create a branch, (with a uniquely generated name (how?)) and return it  
```
branch_name = repo.create_branch
```

Write to the new branch  
```
repo.write_many(files, {:branch => branch_name})
```

Return an array of matching branch names — ones that have any unmerged commits by `albert.sun@nytimes.com`  
```
repo.find_branches(author_email: "albert.sun@nytimes.com")
```

Read back files from a branch  
```
files = repo.read_all(branch: branch_name)
```


Preview what changes a merge would do. This is equivalent to `repo.diff` between the merge_base of HEAD and branch and the branch  
```
repo.merge_preview(branch_name)
```


Merge a branch back into `HEAD`.  
The merge result can either be a:  
  - commit (a successful automerge)  
  - maybe with some flags showing   
  - index, with conflicts (an unsuccessful merge)  
`merge_result` can then be returned to client for a new commit set to be resolved  
```
merge_result = repo.merge_branch(branch_name)
merge_result
```

If a merge has conflicts, they can be resolved manually, and new objects written back directly to resolve the conflicts. The commit ids of the two parent commits are passed back to create the merge commit.  
If `commit_one` and `commit_two` are both at the tip of their respective branches/HEAD this will create a new commit and set both as parents. Otherwise, it will fail again.
```
repo.write_merge_branch(files, {:parents => [commit_one, commit_two]})
```

By default, branching and merging works from whatever you defined as the `:default_branch`. If you want to branch from or merge into a different branch, pass `head: "other-branch"` as an option to any of the merge methods.


Server Mode
===========

The server can be run as a binary, or with anything else that takes a `config.ru` file. In that mode it defaults to looking for configuration at `config/repos.yml`. Look in `config/repos.yml.sample` for an example.

The API looks like this.

- `GET /:repo-slug`
    List contents of a git repo or subfolder of that repo. Response in JSON format.

- `GET /:repo-slug/path/to/file`
    Return the contents of a file in that git repo wrapped in JSON.

- `PUT /:repo-slug/path/to/file`
    Update and commit changes to a file. Expects the following POST parameters:
    
    - `value` The new contents of the file.
    - `commit_user_email` User email for the commit
    - `commit_user_name` User name for the commit
    - `commit_message` Commit message

    Puts are immediately pushed to the remote server.


Development
===========

Set everything up:

```
bundle install
```

Run the server:

```
shotgun -p 4567 config.ru
```

Or load things from the command line with `./bin/console`

```
# set up where the local working copy will be
tmp_path = Dir.mktmpdir("capital-git-test-repos")
database = CapitalGit::Database.new({:local_path => tmp_path})

# set which ssh keys to use
database.credentials = {
  :username => "git",
  :publickey => "../test/fixtures/keys/testcapitalgit.pub",
  :privatekey => "../test/fixtures/keys/testcapitalgit",
  :passphrase => "capital_git passphrase"
}

# clone and pull
repo = database.connect("git@github.com:newsdev/capital_git_testrepo.git")

repo.list
#=> [ ...stuff... ]

# clean up
FileUtils.remove_entry_secure(tmp_path)
```

Have at it!

The test suite is written with Minitest. To run, simply:

```
rake
```

Please try and maintain test coverage for new features. They're in the test directory and hopefully should be fairly easy to follow along with.

To build the gem:

```
gem build capital_git.gemspec
```

Troubleshooting
===============

There are potential issues with installing to be able to handle ssh keys and cloning remotely. On OS X you need both cmake and libssh2 (of version at least 1.4.3) installed, and then the gem must be compiled with libssh2 available for dynamic linking.

Hopefully this will work.

```
brew install cmake libssh2
```

If not, get in touch.


----

Disclaimer
==========

This is pre-release software. Bugs abound. API unstable. Versioning erratic. You probably shouldn't be using it yet and definitely don't expose the web app to the internet.


Copyright
=========
MIT License.
Copyright (c) 2014 The New York Times Company.
See LICENSE for details.