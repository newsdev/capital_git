Capital Git
-----------

A simple REST interface through [Rugged](https://github.com/libgit2/rugged) for interacting with a bare git repo. A Sinatra app run as a server with a `config.ru` rack file.

Can do three things.

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

To run the app, provide a `repos.yml` config file modeled after `repos.yml.sample` to `repos.yml`.

Running `rake repos:clone` clones repos into the `tmp/` directory and pull down the latest changes for any existing ones. This must be done before starting the server. Rugged interacts with its local clone of the repository and then pushes changes to `origin`.


Gem Mode
========

Can also use `capital_git` as a gem to use git as a database within another app.

One caveat, you can't create new repositories via this gem.

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

# clones/pulls a local copy of git@server.example.com:repo-slug.git
@repo = @db.connect('git@server.example.com:repo-slug.git')

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

```

In Rails and Sinatra apps, configuration can be specified in a `config/capitalgit.yml` file. Look at the `config/repos.yml.sample` file here for guidance on syntax. Somewhere during app initialization you'll then need to include this.

```
CapitalGit.load!("config/capitalgit.yml")
```


Installing the gem also provides a `capital_git` binary that can be run as a server.

```
capital_git /path/to/repos.yml
```


Development
===========

Have at it! Set everything up.

```
bundle install
```

Run the server.

```
shotgun -p 4567 config.ru
```

Test suite is written with Minitest. To run, simply.

```
rake
```

To build the gem.

```
gem build capital_git.gemspec
```


----

Disclaimer
==========

This is early pre-release software. Bugs, security holes and future major breaking changes abound. You probably shouldn't be using it yet.

There is no security or authentication to speak of. You should probably not run this on the public internet.


Copyright
=========
MIT License.
Copyright (c) 2014 The New York Times Company.
See LICENSE for details.