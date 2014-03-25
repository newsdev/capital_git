class LocalRepository

  def initialize info, options=nil
    @info = info
    if !options.nil? && !options[:logger].blank?
      @logger = Logger.new(options[:logger])
    else
      @logger = Logger.new(STDOUT)
    end
  end

  def slug
    @info["slug"]
  end

  def local_path
    File.expand_path(File.join("..", "tmp", @info["slug"]), File.dirname(__FILE__))
  end

  def remote_url
    @info["path"]
  end

  def checkout_branch
    @info["checkout_branch"] || nil
  end

  def dir
    @info["dir"] || nil
  end

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

  def set_credentials credential
    @credentials = Rugged::Credentials::SshKey.new({
      :username => credential["username"],
      :publickey => File.expand_path(File.join("../config/keys", credential["publickey"]), File.dirname(__FILE__)),
      :privatekey => File.expand_path(File.join("../config/keys", credential["privatekey"]), File.dirname(__FILE__)),
      :passphrase => credential["passphrase"] || nil
    })
  end

  def credentials
    if !@credentials
      if @info["credentials"]
        set_credentials(@info["credentials"])
      else
        @credentials = nil
      end
    end
    @credentials
  end

  def clone!
    opts = {}
    opts[:checkout_branch] = checkout_branch if checkout_branch
    opts[:credentials] = credentials if credentials

    @logger.info "Cloning #{remote_url} (#{checkout_branch}) into #{local_path}"
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
      opts[:credentials] = credentials if credentials
      opts[:update_tips] = lambda do |ref, old_oid, new_oid|
        @logger.info "Updated #{ref} from #{old_oid} to #{new_oid}"
        repository.reset(new_oid, :hard)
      end
      remote.fetch(opts)
    end
  end

  def push!
    if !repository.nil?
      remote = repository.remotes.find {|r| r.name == "origin"}
      @logger.info "Pushing #{local_path} to #{remote.name}"
      opts = {}
      opts[:credentials] = credentials if credentials
      remote.push([repository.head.name], opts)
    end
  end

end
