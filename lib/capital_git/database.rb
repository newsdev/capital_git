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

    def repositories
      @repositories
    end
    alias_method :repos, :repositories

    private

    def keypath name
      File.expand_path(File.join("../../config/keys", name), File.dirname(__FILE__))
    end

  end
end
