module CapitalGit
  class Database

    # object with
    # connection string
    # for example git@github.com
    def initialize(options={})
      @logger = CapitalGit.logger
      
      self.local_path = options[:local_path] ||
                    File.expand_path(File.join("../..", "tmp"), File.dirname(__FILE__))
      # TODO: should this default to something more unique?
      # like using Dir.mktmpdir or something and make sure it works across platforms

      self.credentials = options[:credentials] if options[:credentials].is_a? Hash
      self.committer = options[:committer] if options[:committer].is_a? Hash
      self.server = options[:server] if options[:server]
    end

    attr_accessor :server

    def connect url, options={}
      if @server && (url[0,@server.length] != @server)
        raise "Server #{@server} does not match repository url #{url}"
      end

      @repository = CapitalGit::LocalRepository.new(self, url, options)
      @repository
    end

    attr_reader :repository

    def local_path=(local_path)
      FileUtils.mkdir_p(local_path)
      @logger.debug("Setting database local_path to #{local_path}")
      @local_path = local_path
    end
    attr_reader :local_path

    # TODO: other forms of credentials
    # github key
    # user/pass
    def credentials=(credential)
      publickey_path = keypath(credential[:publickey] || credential["publickey"])
      privatekey_path = keypath(credential[:privatekey] || credential["privatekey"])
      @logger.debug("Keys at #{publickey_path} and #{privatekey_path} and base at #{CapitalGit.base_keypath}")
      @credentials = Rugged::Credentials::SshKey.new({
        :username => credential[:username] || credential["username"],
        :publickey => publickey_path,
        :privatekey => privatekey_path,
        :passphrase => credential[:passphrase] || credential["passphrase"] || nil
      })
    end
    attr_reader :credentials

    # Object with options describing the current user
    # who commits should be attributed to
    # :email => "testuser@github.com",
    # :name => 'Test Author',
    # :time => Time.now
    def committer=(committer_info)
      @committer ||= {}
      @committer[:email] = committer_info[:email] || committer_info["email"]
      @committer[:name] = committer_info[:name] || committer_info["name"]
    end
    def committer
      return nil if @committer.nil?
      return {
        :email => @committer[:email] || nil,
        :name => @committer[:name] || nil,
        :time => Time.now
      }
    end


    # clear up existing clones, so they can be gotten fresh
    def cleanup
      FileUtils.remove_entry_secure(local_path)
    end

    private

    def keypath path
      @logger.debug("Looking for key #{path}")
      if !path.include?("/")
        File.expand_path(File.join("config/keys", path), CapitalGit.base_keypath)
      elsif path[0] == "/"
        path
      else
        File.expand_path(path, CapitalGit.base_keypath)
      end
    end

  end
end
