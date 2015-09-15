Capital Git
-----------

A simple REST interface through [Rugged](https://github.com/libgit2/rugged) for interacting with a bare git repo.

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

To start the app, copy and rename `repos.yml.sample` to `repos.yml` with the proper configuration.

Then run:

`shotgun -p 4567 config.ru`


Running `rake repos:clone` clones repos into the `tmp/` directory and pull down the latest changes for any existing ones. This must be done before starting the server. Rugged interacts with its local clone of the repository and then pushes changes to `origin`.


Gem Mode
========

Can also use `capital_git` as a gem to use git as a database within another app. Can't create a repo here.

```

@db = CapitalGit::RemoteServer.connect("git@server.example.com")

@db.set_credentials(
    :username => "git",
    :publickey => '...',
    :privatekey => '...',
    :passphrase => "a passphrase goes here"
)

@db.config(
    :committer => {
        :email => "me@example.com",
        :name => "Me at Work"
    }
)


@db.repos

@repo = @db.repos['repo-slug'] # this would correspond to git@servier.example.com:repo-slug.git

# clones/pulls a local copy automatically

@repo.all() # list of files

@repo.read(...) # read a specific file's contents

@repo.commit(...)


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