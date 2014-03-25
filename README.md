Capital Git
-----------

A simple REST interface through [Rugged](https://github.com/libgit2/rugged) for interacting with a bare git repo.

Can do three things.

- `GET /:repo-slug`
    List contents of a git repo or subfolder of that repo.

- `GET /:repo-slug/path/to/file`
    Return the contents of a file in that git repo wrapped in JSON.

- `PUT /:repo-slug/path/to/file`
    Update and commit changes to a file.

To start the app, copy and rename `repos.yml.sample` to `repos.yml` with the proper configuration.

The `config.ru.sample` file has an example of how to run the app with a different base path.

Then run:

`shotgun -p 4567 config.ru`


The `rake repos:clone` will clone repos into the `tmp/` directory which is where rugged will interact with them before pushing them back up.


----

Disclaimer
==========

This is very early pre-release software. Bugs, security holes and future major breaking changes abound. You probably shouldn't be using it yet.



Copyright
=========
Copyright (c) 2014 The New York Times Company. See LICENSE for details.