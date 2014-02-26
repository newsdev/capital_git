require 'sinatra/base'
require 'debugger'

class CapitalGit < Sinatra::Base

  before do
    content_type :json
    env = ENV['RACK_ENV'] || 'development'
    config_path = File.expand_path('repos.yml', File.dirname(__FILE__))
    @@repos = {}
    YAML::load(File.read(config_path))[env].each do |repo|
      @@repos[repo['slug']] = {:path => repo['path'], :dir => repo['dir']}
    end
  end

  get '/:repo' do
    resp = {}
    resp[:items] = []


    @repo = @@repos[params[:repo]]
    repo = Rugged::Repository.new(@repo[:path])
    
    repo.lookup(repo.head.target).tree.walk_blobs do |root,entry|
      if root[0,5] == @repo[:dir]
        path = File.join(root, entry[:name])
        resp[:items] << {:entry => entry, :path => path}
      end
    end

    return resp.to_json
  end

  get '/:repo/*' do |repo, path|
    resp = {}
    resp[:attributes] = {}

    @repo = @@repos[params[:repo]]
    repo = Rugged::Repository.new(@repo[:path])

    repo.lookup(repo.head.target).tree.walk_blobs do |root,entry|
      if root[0,5] == @repo[:dir]
        if File.join(root, entry[:name]) == path
          blob = repo.read(entry[:oid])
          resp[:attributes][:text] = blob.data.force_encoding('UTF-8')
          resp[:entry] = entry
        end
      end
    end

    return resp.to_json
  end

  put '/:repo/*' do |repo, path|
    resp = {}

    putdata = JSON.parse(request.env["rack.input"].read)
    text = putdata["attributes"]["text"]
    committer = { :email => putdata["committer"]["email"], :name => putdata["committer"]["name"], :time => Time.now }
    message = putdata["message"] || ""

    repo = Rugged::Repository.new(@@repos[params[:repo]][:path])

    options = {}
    updated_oid = repo.write(text.force_encoding("UTF-8"), :blob)
    tree = repo.lookup(repo.head.target).tree

    options[:tree] = update_tree(repo, tree, path, updated_oid)
    options[:author] = committer
    options[:committer] = committer
    options[:message] ||= message
    options[:parents] = repo.empty? ? [] : [ repo.head.target ].compact
    options[:update_ref] = 'HEAD'

    commit = Rugged::Commit.create(repo, options)

    if !repo.bare?
      repo.reset(commit, :hard)
      if repo.remotes.map {|r| r.name}.include? "origin"
        repo.push("origin", [repo.head.name])
      end
    end

    return options.to_json
  end

  # recursively updates a tree.
  # returns the oid of the new tree
  def update_tree repo, tree, path, blob_oid
    segments = path.split("/")
    if segments.length > 1
      segment = segments.shift
      rest = segments.join("/")
      builder = Rugged::Tree::Builder.new(tree)
      original_tree = repo.lookup(builder[segment][:oid])
      builder.remove(segment)
      new_tree = update_tree(repo, original_tree, rest, blob_oid)
      builder << { :type => :tree, :name => segment, :oid => new_tree, :filemode => 0040000 }
      return builder.write(repo)
    else
      segment = segments.shift
      builder = Rugged::Tree::Builder.new(tree)
      builder.remove(segment)
      builder << { :type => :blob, :name => segment, :oid => blob_oid, :filemode => 0100644 }
      return builder.write(repo)
    end
  end

end
