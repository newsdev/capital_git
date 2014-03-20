task :environment do
  require File.expand_path(File.join(*%w[ config environment ]), File.dirname(__FILE__))
end

namespace :repos do

  desc "Does a `git pull` on all local repos."
  task :pull => :environment do
    puts "#{CapitalGit.env} - pull repos"
    
    # TODO: need a way to check for the local repo's existence and clone if not
    CapitalGit.repos.each do |slug,repo|
      repo.pull!
    end
  end

  desc "Clones all remote repos in the repos.yml config file to the local tmp/ directory"
  task :clone => :environment do
    puts "#{CapitalGit.env} - clone repos"
    
    CapitalGit.repos.each do |slug,repo|
      repo.clone!
    end
  end

  task :clean => :environment do
    CapitalGit.repos.each do |slug,repo|
      puts "Deleting repo at #{repo.local_path}"
      FileUtils.rm_rf(repo.local_path)
    end
  end
end
