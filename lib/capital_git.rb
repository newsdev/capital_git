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


end

require 'capital_git/database'
require 'capital_git/local_repository'
