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

To start the app, copy and rename `config.ru.sample` and `repos.yml.sample` to `config.ru` and `repos.yml` respectively with the proper configuration.

Then run:

`shotgun -p 4567 config.ru`



