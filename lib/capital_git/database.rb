module CapitalGit
  class Database

    # object with
    # connection string
    # for example git@github.com
    def initialize(connection_str)
      @connection_str = connection_str

      # when you encounter an unseen before hash
      # call a method to try and clone a new repo
      @repositories = Hash.new do |hash,key|        
        repo = CapitalGit::LocalRepository.new(self, key) # TODO: is this self the right instance of CapitalGit::Database ?

        hash[key] = repo
        repo
      end
    end

    attr_reader :connection_str

    def credentials=(credential)
      # puts File.expand_path(File.join("../../config/keys", credential["privatekey"]), File.dirname(__FILE__))
      @credentials = Rugged::Credentials::SshKey.new({
        :username => credential["username"],
        :publickey => File.expand_path(File.join("../../config/keys", credential["publickey"]), File.dirname(__FILE__)),
        :privatekey => File.expand_path(File.join("../../config/keys", credential["privatekey"]), File.dirname(__FILE__)),
        :passphrase => credential["passphrase"] || nil
      })
    end
    attr_reader :credentials

    # Object with options describing the current user
    # who commits should be attributed to
    # :email => "testuser@github.com",
    # :name => 'Test Author',
    # :time => Time.now
    def committer=(val)
      @committer = val
    end
    attr_reader :committer

    def repositories
      @repositories
    end
    alias_method :repos, :repositories

  end
end
