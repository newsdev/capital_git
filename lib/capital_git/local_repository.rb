require 'logger'
require 'rugged'

module CapitalGit
  class LocalRepository

    # format of info
    # {
    #   "slug": "activity-trackers-roundup",
    #   "path": "nytg@newsdev.ec2.nytimes.com:2014-02-12-activity-trackers-roundup.git",
    #   "dir": "data/",
    #   "checkout_branch": "develop",
    #   "credentials": {
    #     "username":"nytg",
    #     "publickey":"capitalgit.pub",
    #     "privatekey":"capitalgit",
    #     "passphrase":"capitalgit"
    #   }
    # }

    def initialize database, name, options={}
      @db = database
      @name = name
      @directory = options["directory"] || ""
      @default_branch = options[:default_branch] || "master" # TODO: can we default to remote's default branch?


      if options[:logger]
        @logger = Logger.new(options[:logger])
      else
        @logger = Logger.new(STDOUT)
      end

      if repository.nil?
        @logger.info "Repository at #{local_path} doesn't exist"
        clone!
      end
    end

    attr_reader :name
    alias_method :slug, :name

    def local_path
      File.expand_path(File.join("../..", "tmp", @name), File.dirname(__FILE__))
    end

    def remote_url
      "#{@db.connection_str}:#{@name}.git"
    end

    # def default_branch
    #   @default_branch
    # end
    attr_reader :default_branch, :directory

    # def dir
    #   @directory
    # end

    def repository
      if @repository.nil?
        begin
          @repository = Rugged::Repository.new(local_path)
        rescue
          @repository = nil
        end
      end
      @repository
    end

    # def set_credentials credential
    #   @credentials = Rugged::Credentials::SshKey.new({
    #     :username => credential["username"],
    #     :publickey => File.expand_path(File.join("../config/keys", credential["publickey"]), File.dirname(__FILE__)),
    #     :privatekey => File.expand_path(File.join("../config/keys", credential["privatekey"]), File.dirname(__FILE__)),
    #     :passphrase => credential["passphrase"] || nil
    #   })
    # end

    # def credentials
    #   if !@credentials
    #     if @info["credentials"]
    #       set_credentials(@info["credentials"])
    #     else
    #       @credentials = nil
    #     end
    #   end
    #   @credentials
    # end

    def clone!
      opts = {}
      opts[:checkout_branch] = default_branch if default_branch
      opts[:credentials] = @db.credentials if @db.credentials

      @logger.info "Cloning #{remote_url} (#{default_branch}) into #{local_path}"
      Rugged::Repository.clone_at(remote_url, local_path, opts)
    end

    def pull!
      if repository.nil?
        @logger.info "Repository at #{local_path} doesn't exist"
        return clone!
      else
        remote = repository.remotes.find {|r| r.name == "origin"}
        @logger.info "Fetching #{remote.name} into #{local_path}"
        opts = {}
        opts[:credentials] = @db.credentials if @db.credentials
        opts[:update_tips] = lambda do |ref, old_oid, new_oid|
          if (ref.gsub("refs/remotes/#{remote.name}/","") == default_branch)
            @logger.info "Updated #{ref} from #{old_oid} to #{new_oid}"
            repository.reset(new_oid, :hard)
          end
        end
        remote.fetch(opts)
      end
    end

    def push!
      if !repository.nil?
        remote = repository.remotes.find {|r| r.name == "origin"}
        @logger.info "Pushing #{local_path} to #{remote.name}"
        opts = {}
        opts[:credentials] = @db.credentials if @db.credentials
        remote.push([repository.head.name], opts)
      end
    end

    def list(options = {})
      pull!

      items = []
      repository.head.target.tree.walk_blobs do |root,entry|
        if root[0,@directory.length] == @directory
          path = File.join(root, entry[:name])
          items << {:entry => entry, :path => path}
        end
      end

      items
    end

    def log(options = {})
      limit = options[:limit] || 10

      pull!

      walker = Rugged::Walker.new(repository)
      walker.push(repository.head.target.oid)
      walker.sorting(Rugged::SORT_DATE)
      walker.push(repository.head.target)
      walker.map do |commit|
        {
          :message => commit.message,
          :author => commit.author,
          :time => commit.time,
          :oid => commit.oid
          # :tree_id => commit.tree_id,
        }
        # commit.to_hash
      end.compact.first(limit)
    end

    def read(key, options = nil)
      pull!

      resp = {}

      repository.head.target.tree.walk_blobs do |root,entry|
        puts root[0,@directory.length]
        if (root.empty? && (entry[:name] == key)) or 
            ((root[0,@directory.length] == @directory) && (File.join(root, entry[:name]) == key))
          blob = repository.read(entry[:oid])
          resp[:value] = blob.data.force_encoding('UTF-8')
          resp[:entry] = entry
          walker = Rugged::Walker.new(repository)
          walker.push(repository.head.target.oid)
          walker.sorting(Rugged::SORT_DATE)
          walker.push(repository.head.target)
          resp[:commits] = walker.map do |commit|
            if commit.parents.size == 1 && commit.diff(paths: [key]).size > 0
              {
                :message => commit.message,
                :author => commit.author
              }
            else
              nil
            end
          end.compact.first(10)
        end
      end

      resp
    end

    def write(key, value, options = nil)
    end

    def delete(key, options = nil)
    end

    def clear(options = nil)
    end


  end
end