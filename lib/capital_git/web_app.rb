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
        if repo['committer']
          @@databases[repo['server']].committer = repo['committer']
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

      resp = @repo.read(path)

      if resp.empty?
        status 404
        return "Not found"
      end

      return resp.to_json
    end

    put '/:repo/*' do |repo, path|

      @repo = @@repos[params[:repo]]
      if @repo.nil?
        status 404
        return "Repo doesn't exist"
      end

      if !path.start_with?(@repo.directory)
        status 403
        return "Access denied"
      end

      params = JSON.parse(request.body.read)

      author = {
        :email => params["commit_user_email"],
        :name => params["commit_user_name"],
        :time => Time.now
      }
      commit_message = params["commit_message"] || "Commit via CapitalGit"

      resp = @repo.write(path, params["value"].force_encoding("UTF-8"), {
            :author => author,
            :message => commit_message
          }
        )

      return resp.to_json
    end

    delete '/:repo/*' do |repo, path|

      @repo = @@repos[params[:repo]]
      if @repo.nil?
        status 404
        return "Repo doesn't exist"
      end

      if !path.start_with?(@repo.directory)
        status 403
        return "Access denied"
      end

      author = {
        :email => params["commit_user_email"],
        :name => params["commit_user_name"],
        :time => Time.now
      }
      commit_message = params["commit_message"] || "Delete via CapitalGit"

      resp = @repo.delete(path, {
            :author => author,
            :message => commit_message
          }
        )

      return resp.to_json
    end

  end
end