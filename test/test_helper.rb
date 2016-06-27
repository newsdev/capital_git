$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'capital_git'
require 'time'

CapitalGit.logger.level = Logger::ERROR
ENV["RACK_ENV"] = "test"
ENV["CAPITAL_GIT_ENV"] = "test"

require 'minitest/autorun'

require 'capital_git/web_app'
require 'rack/test'

# http://stackoverflow.com/a/25340729
module Spy
  def self.on_instance_method(mod, method, &block)
    mod.class_eval do
      # Stash the old method
      old_method = instance_method(method)

      # Create a new proc that will call both our block and the old method
      proc = Proc.new do
        block.call if block
        old_method.bind(self).call
      end

      # Bind that proc to the original module
      define_method(method, proc)
    end
  end

  def self.on_class_method(mod, method, &block)
    mod.class_eval do
      # Stash the old method
      old_method = singleton_method(method)

      # Create a new proc that will call both our block and the old method
      proc = Proc.new do
        block.call if block
        old_method.call
      end

      # Bind that proc to the original module
      define_singleton_method(method, proc)
    end
  end
end
