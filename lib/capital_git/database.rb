module CapitalGit
  class Database

    # object with
    # connection string
    # for example git@github.com
    def initialize(connection_str, options={})
      @connection_str = connection_str
      if @connection_str.include?("@") and @connection_str[-1] != ":"
        @connection_str += ":"
      elsif @connection_str[0] == "/" and @connection_str[-1] != "/"
        @connection_str += "/"
      end

      self.local_path = options[:local_path] ||
                    File.expand_path(File.join("../..", "tmp"), File.dirname(__FILE__))
      self.credentials = options[:credentials] if options[:credentials].is_a? Hash
      self.credentials = options[:committer] if options[:committer].is_a? Hash

      @repositories = {}
    end

    attr_reader :connection_str
    attr_reader :repositories
    alias_method :repos, :repositories

    def connect name, options={}
      @repositories[name] = CapitalGit::LocalRepository.new(self, name, options)
      @repositories[name]
    end


    def credentials=(credential)
      # puts File.expand_path(File.join("../../config/keys", credential["privatekey"]), File.dirname(__FILE__))
      @credentials = Rugged::Credentials::SshKey.new({
        :username => credential[:username] || credential["username"],
        :publickey => keypath(credential[:publickey] || credential["publickey"]),
        :privatekey => keypath(credential[:privatekey] || credential["privatekey"]),
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

    def local_path=(local_path)
      FileUtils.mkdir_p(local_path)
      @local_path = local_path
    end
    attr_reader :local_path

    private

    def keypath name
      File.expand_path(File.join("../../config/keys", name), File.dirname(__FILE__))
    end

  end
end
