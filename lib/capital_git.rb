require "capital_git/version"
require 'logger'

module CapitalGit

  def self.logger
    @logger ||= Logger.new(STDOUT)
    @logger
  end
  def self.logger=(logger)
    @logger = logger
  end

  def self.env_name
    return Rails.env if defined?(Rails) && Rails.respond_to?(:env)
    return Sinatra::Base.environment.to_s if defined?(Sinatra)
    ENV["RACK_ENV"] || ENV["CAPITAL_GIT_ENV"] || raise("No environment defined")
  end

  def self.base_keypath
    return Rails.root if defined?(Rails) && Rails.respond_to?(:root)
    return Sinatra::Base.root.to_s if defined?(Sinatra)
    ENV["CAPITAL_GIT_KEYPATH"] || File.dirname(__FILE__)
  end

  @@repositories = {}
  @@databases = {}

  # handle repositories and servers
  # defined in a config file
  def self.load! path_to_config, environment = nil
    environment = self.env_name if environment.nil?

    @@config = YAML::load(File.read(path_to_config))[environment]
    self.load_config! @@config
  end

  def self.load_config! config
    self.cleanup!
    @@repositories = {}
    @@databases = {}

    config.each do |config_section|
      database = CapitalGit::Database.new
      if config_section['local_path']
        database.local_path = config_section['local_path']
      end

      if config_section['credentials']
        database.credentials = config_section['credentials']
      end
      if config_section['committer']
        database.committer = config_section['committer']
      end

      if config_section.has_key? "name" 
        @@repositories[config_section['name']] = database.connect(config_section['url'])
      elsif config_section.has_key? "server"
        if config_section['server']
          database.server = config_section['server']
        end
        @@databases[config_section['server']] = database
      end
    end
  end

  def self.repository name
    @@repositories[name]
  end

  def self.connect url, options={}, database_options={}
    @@databases.each do |servername, database|
      if url[0,servername.length] == servername
        return database.connect(url, options)
      end
    end

    self.logger.warn("Attempting to connect to a repository that's not defined in configuration.")

    database = CapitalGit::Database.new(database_options)
    database.connect(url, options)
  end

  # purge local clones
  def self.cleanup!
    @@databases.each do |d|
      d.cleanup
    end
    @@repositories.each do |r|
      r.database.cleanup
    end
  end

end

require 'capital_git/database'
require 'capital_git/local_repository'
