require 'rubygems'
require 'bundler/setup'
Bundler.require

require File.expand_path('./lib/capital_git', File.dirname(__FILE__))
require File.expand_path('./lib/capital_git/web_app', File.dirname(__FILE__))

run CapitalGit::WebApp
