require 'rubygems'
require 'bundler/setup'
Bundler.require

Dir["./lib/*.rb"].each {|file| require file }
require './capital_git'
