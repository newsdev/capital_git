require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task :default => :spec

task :environment do
  require File.expand_path(File.join(*%w[ config environment ]), File.dirname(__FILE__))
end

namespace :repos do

  desc "Does a `git pull` or `git clone` on all repos for the environment."
  task :clone => :environment do
    puts "#{CapitalGit.env} - cloning repos"
    
    CapitalGit.repos.each do |slug,repo|
      repo.pull!
    end
  end

  task :clean => :environment do
    CapitalGit.repos.each do |slug,repo|
      puts "Deleting repo at #{repo.local_path}"
      FileUtils.rm_rf(repo.local_path)
    end
  end
end

