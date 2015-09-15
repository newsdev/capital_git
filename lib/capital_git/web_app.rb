require 'sinatra/base'
require 'yaml'
require 'json'
if ENV['RACK_ENV'] == "development" || ENV['RACK_ENV'].nil?
  require 'byebug'
end

module CapitalGit
  class WebApp < Sinatra::Base

    configure :production, :staging, :development do
      enable :logging
    end

    @@env = ENV['RACK_ENV'] || 'development'
    @@repos = {}
    @@databases = {}
    @@config_path = File.expand_path( ENV['CONFIG_PATH'] || File.join('../../','config','repos.yml'), File.dirname(__FILE__) )
    YAML::load(File.read(@@config_path))[@@env].each do |repo|
      # @@repos[repo['slug']] = repo
      # @@repos[repo['slug']] = CapitalGit::LocalRepository.new(repo)
      if !@@databases.has_key?(repo['server'])
        @@databases[repo['server']] = CapitalGit::Database.new(repo['server'])
        if repo['credentials']
          @@databases[repo['server']].credentials = repo['credentials']
        end
      end
      @@repos[repo['name']] = CapitalGit::LocalRepository.new(@@databases[repo['server']], repo['name'])
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

    get '/' do
      'capital_git'
    end

    get '/:repo' do
      @repo = @@repos[params[:repo]]
      if @repo.nil?
        status 404
        return "Repo doesn't exist"
      end

      resp = {}
      resp[:items] = @repo.list
      resp[:commits] = @repo.log

      puts resp.inspect

      return resp.to_json
    end

    get '/:repo/*' do |repo, path|
      @repo = @@repos[params[:repo]]
      if @repo.nil?
        status 404
        return "Repo doesn't exist"
      end

      if !path.start_with?(@repo.directory)
        status 404
        return "Not found"
      end

      # resp = {}
      resp = @repo.read(path)

      if resp.empty?
        status 404
        return "Not found"
      end

      return resp.to_json

      # repo = @repo.repository

      # repo.head.target.tree.walk_blobs do |root,entry|
      #   if root[0,5] == @repo.directory
      #     if File.join(root, entry[:name]) == path
      #       blob = repo.read(entry[:oid])
      #       resp[:value] = blob.data.force_encoding('UTF-8')
      #       resp[:entry] = entry
      #       walker = Rugged::Walker.new(repo)
      #       walker.push(repo.head.target.oid)
      #       walker.sorting(Rugged::SORT_DATE)
      #       walker.push(repo.head.target)
      #       resp[:commits] = walker.map do |commit|
      #         if commit.parents.size == 1 && commit.diff(paths: [path]).size > 0
      #           {
      #             :message => commit.message,
      #             :author => commit.author
      #           }
      #         else
      #           nil
      #         end
      #       end.compact.first(10)
      #     end
      #   end
      # end
    end

    put '/:repo/*' do |repo, path|
      resp = {}

      text = params["value"]
      committer = {
        :email => params["commit_user_email"],
        :name => params["commit_user_name"],
        :time => Time.now }
      message = params["commit_message"] || ""

      @repo = @@repos[params[:repo]]
      if @repo.nil?
        status 404
        return "Repo doesn't exist"
      end
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
end