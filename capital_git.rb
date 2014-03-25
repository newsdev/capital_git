require 'sinatra/base'
require 'yaml'
if ENV['RACK_ENV'] == "development" || ENV['RACK_ENV'].nil?
  require 'byebug'
end

class CapitalGit < Sinatra::Base

  configure :production, :staging, :development do
    enable :logging
  end

  @@env = ENV['RACK_ENV'] || 'development'
  @@repos = {}
  YAML::load(File.read(File.expand_path(File.join('config','repos.yml'), File.dirname(__FILE__))))[@@env].each do |repo|
    @@repos[repo['slug']] = repo
    @@repos[repo['slug']] = LocalRepository.new(repo)
  end
  
  def self.env
    @@env
  end

  def self.repos
    @@repos
  end

  before do
    content_type :json
  end

  get '/:repo' do
    resp = {}
    resp[:items] = []

    @repo = @@repos[params[:repo]]
    @repo.pull!
    repo = @repo.repository
    
    repo.head.target.tree.walk_blobs do |root,entry|
      if root[0,5] == @repo.dir
        path = File.join(root, entry[:name])
        resp[:items] << {:entry => entry, :path => path}
      end
    end

    return resp.to_json
  end

  get '/:repo/*' do |repo, path|
    resp = {}

    @repo = @@repos[params[:repo]]
    @repo.pull!
    repo = @repo.repository

    repo.head.target.tree.walk_blobs do |root,entry|
      if root[0,5] == @repo.dir
        if File.join(root, entry[:name]) == path
          blob = repo.read(entry[:oid])
          resp[:value] = blob.data.force_encoding('UTF-8')
          resp[:entry] = entry
        end
      end
    end

    return resp.to_json
  end

  put '/:repo/*' do |repo, path|
    resp = {}

    # putdata = JSON.parse(request.env["rack.input"].read)
    text = params["value"]
    committer = {
      :email => params["commit_user_email"],
      :name => params["commit_user_name"],
      :time => Time.now }
    message = params["commit_message"] || ""

    @repo = @@repos[params[:repo]]
    repo = Rugged::Repository.new(@repo.local_path)

    if !path.start_with?(@repo.dir)
      return error 403 do
        "Access denied"
      end
    end

    options = {}
    updated_oid = repo.write(text.force_encoding("UTF-8"), :blob)
    tree = repo.head.target.tree

    options[:tree] = update_tree(repo, tree, path, updated_oid)
    options[:author] = committer
    options[:committer] = committer
    options[:message] ||= message
    options[:parents] = repo.empty? ? [] : [ repo.head.target ].compact
    options[:update_ref] = 'HEAD'

    commit = Rugged::Commit.create(repo, options)

    if !repo.bare?
      repo.reset(commit, :hard)

      # TODO:
      # pointing at the albertsun/rugged merge-304 branch so it works but is highly unstable
      # when https://github.com/libgit2/rugged/pull/304 is merged
      # then things will be better
      @repo.push!
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
