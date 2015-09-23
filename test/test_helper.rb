$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'capital_git'

CapitalGit.logger.level = Logger::ERROR

require 'minitest/autorun'
