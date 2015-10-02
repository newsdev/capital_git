module CapitalGit
  class Database

    # object with
    # connection string
    # for example git@github.com
    def initialize(options={})
      self.local_path = options[:local_path] ||
                    File.expand_path(File.join("../..", "tmp"), File.dirname(__FILE__))
      # TODO: this should default to something more unique
      # use Dir.mktmpdir or something and make sure it works across platforms

      self.credentials = options[:credentials] if options[:credentials].is_a? Hash
      self.committer = options[:committer] if options[:committer].is_a? Hash
      self.server = options[:server] if options[:server]

      @logger = CapitalGit.logger
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
        :username => credential[:username] || credential["username"], # TODO: this could be picked up from connection string
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
      {
        :email => @committer[:email],
        :name => @committer[:name],
        :time => Time.now
      }
    end


    # TODO:
    # when should this be called?
    # does it need to do anything else other than delete the dir?
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
      # if !name.include?("/")
      #   File.expand_path(File.join("../../config/keys", name), File.dirname(__FILE__))
      # elsif name[0] == "/"
      #   name
      # else
      #   # better way of finding keys.
      #   # ENV var?
      #   # Rails.root?
      #   # File.expand_path(name, File.dirname(__FILE__))
      # end
    end

  end
end
