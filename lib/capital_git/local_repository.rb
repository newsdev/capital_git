require 'rugged'

module CapitalGit
  class LocalRepository

    # database is a CapitalGit::Database
    # url is the location of the remote git repo
    def initialize database, url, options={}
      @db = database
      @url = url
      @directory = options["directory"] || ""
      @default_branch = options[:default_branch] # TODO: can we default to remote's default branch?

      @name = parse_name_from_url(@url)

      @logger = CapitalGit.logger

      if repository.nil?
        @logger.info "Repository at #{local_path} doesn't exist"
        clone!
      else
        pull!
      end
    end

    attr_reader :name, :url, :default_branch, :directory

    def local_path
      # File.expand_path(File.join("../..", "tmp", @name), File.dirname(__FILE__))
      File.join(@db.local_path, @name)
    end

    def remote_url
      @url
    end

    def database
      @db
    end

    def committer=(commiter_info)
      @db.commiter = commiter_info
    end

    def committer
      @db.committer
    end

    def repository
      if @repository.nil?
        begin
          @repository = Rugged::Repository.new(local_path)
        rescue
          @logger.info "Failed to create repository from #{local_path}"
          @repository = nil
        end
      end
      @repository
    end


    def sync
      pull!
      yield(self)
    end

    def list(options={})
      pull!

      return [] if repository.empty?

      if options[:branch]
        ref = reference(options[:branch])
      else
        ref = repository.head
      end

      items = []
      ref.target.tree.walk_blobs do |root,entry|
        if root[0,@directory.length] == @directory
          if root.length > 0
            path = File.join(root, entry[:name])
          else
            path = entry[:name]
          end
          items << {:entry => entry, :path => path}
        end
      end

      items
    end

    def log(options={})
      limit = options[:limit] || 10

      pull!

      return [] if repository.empty?

      if options[:branch]
        ref = reference(options[:branch])
      else
        ref = repository.head
      end

      walker = Rugged::Walker.new(repository)
      walker.push(ref.target.oid)
      walker.sorting(Rugged::SORT_DATE)
      walker.push(ref.target)
      walker.map do |commit|
        {
          :message => commit.message,
          :author => commit.author,
          :time => commit.time,
          :oid => commit.oid
        }
      end.compact.first(limit)
    end

    # read the contents of a file
    def read(key, options={})
      pull!

      return nil if repository.empty?

      begin
        if options[:branch]
          commit = reference(options[:branch]).nil? ? nil : reference(options[:branch]).target
          return nil if !commit
        elsif options[:sha]
          commit = repository.lookup(options[:sha])
        else
          commit = repository.head.target
        end
      rescue Rugged::OdbError
        commit = nil
      end

      resp = {}

      if !commit.nil?
        commit.tree.walk_blobs do |root,entry|
          if (root.empty? && (entry[:name] == key)) or 
              ((root[0,@directory.length] == @directory) && (File.join(root, entry[:name]) == key))
            blob = repository.read(entry[:oid])
            resp[:value] = blob.data.force_encoding('UTF-8')
            resp[:entry] = entry
            walker = Rugged::Walker.new(repository)
            walker.push(commit.oid)
            walker.sorting(Rugged::SORT_DATE)
            walker.push(commit)
            resp[:commits] = walker.map do |commit|
              if commit.diff(paths: [key]).size > 0
                {
                  :message => commit.message,
                  :author => commit.author,
                  :time => commit.time,
                  :oid => commit.oid
                }
              else
                nil
              end
            end.compact.first(10)
          end
        end
      end

      if resp.empty?
        return nil
      else
        return resp
      end
    end

    # return a current snapshot of all files with no metadata or history
    # :mode => :flat yields a flat array
    # :mode => :tree yields a nested tree
    def read_all options={:mode => :flat}
      pull!

      if repository.empty?
        return options[:mode] == :tree ? {} : []
      end

      if options[:branch]
        ref = reference(options[:branch])
        return nil if !ref
      else
        ref = repository.head
      end

      # TODO: replace this tree walking silliness with index.read_tree(ref.target.tree)
      # and optionally index.add_all to pick up un-committed local changes to the repo
      #     but to work-with uncommmitted... should probably change so we don't clone a local

      if options[:mode] == :tree
        items = {}
        ref.target.tree.walk(:preorder) do |root,entry|
          if entry[:type] == :blob
            blob = repository.read(entry[:oid])
            if root.length > 0
              path = File.join(root, entry[:name])

              # if root = "subdir/subdir2/"
              # then this bit does items["subdir"]["subdir2"][entry[:name]] = ...
              path_keys = root.split("/")
              path_keys.inject(items, :fetch)[entry[:name]] = {:path => path, :value => blob.data.force_encoding('UTF-8')}
            else
              path = entry[:name]
              items[entry[:name]] = {:path => path, :value => blob.data.force_encoding('UTF-8')}
            end
          elsif entry[:type] == :tree
            if root.length > 0
              path_keys = root.split("/")
              path_keys.inject(items, :fetch)[entry[:name]] = {}
            else
              items[entry[:name]] = {}
            end
          end
        end
      else
        items = []
        ref.target.tree.walk_blobs do |root,entry|
          if root.length > 0
            path = File.join(root, entry[:name])
          else
            path = entry[:name]
          end
          blob = repository.read(entry[:oid])
          items << {:path => path, :value => blob.data.force_encoding('UTF-8')}
        end
      end

      items
    end

    # TODO detect when nothing changed and don't commit if so
    # TODO how atomic can we make a write? so that it's not considered written
    # until something has been pushed to the remote and persisted?
    # TODO: maybe a :create_from option to specify which we are branching from?
    def write(key, value, options={})
      updated_oid = repository.write(value, :blob)
      index = repository.index

      if repository.empty?
        new_branch = options[:branch] || "master"
        ref = "refs/heads/#{new_branch}"
      else
        if options[:branch]
          ref = reference(options[:branch])
          if !ref
            ref = repository.references.create("refs/heads/#{options[:branch]}", repository.head.target.oid)
          end
        else
          ref = repository.head
        end

        tree = ref.target.tree
        index.read_tree(tree)
      end

      index.update(:path => key, :oid => updated_oid, :mode => 0100644)
      new_tree = index.write_tree(repository)

      # if nothing changed, don't commit
      if !repository.empty? && (tree.oid == new_tree)
        return false
      end

      return commit(ref, new_tree, options)
    end

    # files is an array of
    # {:path => "path/to/file", :value => "blob contents\nof file\n"}
    def write_many(files, options={})
      return false if files.length == 0
      index = repository.index

      if repository.empty?
        new_branch = options[:branch] || "master"
        ref = "refs/heads/#{new_branch}"
      else
        if options[:branch]
          ref = reference(options[:branch])
          if !ref
            ref = repository.references.create("refs/heads/#{options[:branch]}", repository.head.target.oid)
          end
        else
          ref = repository.head
        end

        tree = ref.target.tree
        index.read_tree(tree)
      end

      files.each do |file|
        updated_oid = repository.write(file[:value], :blob)
        # index.read_tree(ref.target.tree)
        index.update(:path => file[:path], :oid => updated_oid, :mode => 0100644)
      end
      new_tree = index.write_tree(repository)

      return commit(ref, new_tree, options)
    end


    # delete a specific file
    def delete(key, options={})
      return false if repository.empty?

      if options[:branch]
        ref = reference(options[:branch])
        if !ref
          ref = repository.references.create("refs/heads/#{options[:branch]}", repository.head.target.oid)
        end
      elsif repository.empty?
        return false
      else
        ref = repository.head
      end

      tree = ref.target.tree

      # new_tree = update_tree(repository, tree, key, nil)
      index = repository.index
      index.read_tree(ref.target.tree)
      begin
        index.remove(key)
        new_tree = index.write_tree(repository)
      rescue Rugged::IndexError
        @logger.info("Attempted delete of non-existent file at #{key} — ignoring.")
        return false
      end

      # if nothing changed, don't commit
      if tree.oid == new_tree
        return false
      end

      return commit(ref, new_tree, options)
    end

    # delete everything under a directory
    def clear(key, options={})
      raise "Not implemented"
    end

    def diff(commit, commit2=nil, options={})
      pull!

      if !commit2.nil? 
        # diff between :commit and :next_commit
        left = repository.lookup(commit)
        right = repository.lookup(commit2)
      else 
        # passed one arg, diff between HEAD & :commit 
        left = repository.head.target
        right = repository.lookup(commit)
      end 

      diff_opts = {}
      if options[:paths] 
        diff_opts = {:paths => options[:paths]}
      end

      diff = repository.diff(left, right, diff_opts) 
      diff.find_similar! # calculate which are renames instead of delete/adds

      changes = diff.each_patch.reduce({}) do |memo, patch|
        dlt = patch.delta
        if !memo.has_key? dlt.status
          memo[dlt.status] = []
        end
        memo[dlt.status] << {
          :old_path => dlt.old_file[:path],
          :new_path => dlt.new_file[:path],
          :patch => patch.to_s.force_encoding('UTF-8')
        }
        memo
      end

      {
        :left => left.oid,
        :right => right.oid, 
        :changes => changes
      }
    end

    # show diffs for everything that changed in the latest commit on head
    # or latest on :branch => 
    # or latest on :sha =>
    def show(sha = nil, branch: nil)
      pull!

      # find latest or specific commit
      if !branch.nil? 
        ref = reference(branch)
        return nil if !ref
        commit = ref.target
      elsif !sha.nil?
        commit = repository.lookup(sha) 
      else
        ref = repository.head
        commit = ref.target
      end

      if !commit.parents[0].nil?
        diff = commit.parents[0].diff(commit)
      else
        diff = Rugged::Tree.diff(repository,nil,commit)
      end
      diff.find_similar! # calculate which are renames instead of delete/adds

      # diff.each_delta
      # dlt = diff.each_delta.first
      # @repo.repository.read(dlt.new_file[:oid]).data.force_encoding("UTF-8")

      # # patch from diff
      # patch = diff.each_patch.first

      # # patch from dlt
      # Rugged::Patch.from_strings(
      #     @repo.repository.read(dlt.new_file[:oid]).data.force_encoding("UTF-8"),
      #     @repo.repository.read(dlt.new_file[:oid]).data.force_encoding("UTF-8")
      #   )

      # patch.hunks.first.lines

      # changed_paths = diff.each_delta.map {|d| [d.old_file[:path], d.new_file[:path]]}.flatten.uniq

      changes = diff.each_patch.reduce({}) do |memo, patch|
        dlt = patch.delta
        if !memo.has_key? dlt.status
          memo[dlt.status] = []
        end
        memo[dlt.status] << {
          :old_path => dlt.old_file[:path],
          :new_path => dlt.new_file[:path],
          :patch => patch.to_s
        }
        memo
      end

      {
        :oid => commit.oid,
        :message => commit.message,
        :author => commit.author,
        :time => commit.time,
        :changes => changes
      }
    end


    # methods for interacting with remote
    # TODO:
    # lots of things call pull!
    # maybe too many
    # should we find some way to de-dupe those pulls if they happen really close in time?

    def pull!
      if repository.nil?
        @logger.info "Repository at #{local_path} doesn't exist"
        return clone!
      else
        @logger.info "Fetching #{rugged_origin.name} into #{local_path}"
        opts = {}
        opts[:credentials] = @db.credentials if @db.credentials
        opts[:update_tips] = lambda do |ref, old_oid, new_oid|
          @logger.info "Fetched #{ref}"
          if (ref.gsub("refs/remotes/#{rugged_origin.name}/","") == repository.head.name.gsub("refs/heads/",""))
            @logger.info "Updated #{repository.head.name} from #{old_oid} to #{new_oid}"
            repository.reset(new_oid, :hard)
          end
        end
        rugged_origin.fetch("+refs/*:refs/*", opts)
        # rugged_origin.fetch(opts)
      end
    end

    def push!
      if !repository.nil?
        @logger.info "Pushing #{local_path} to #{rugged_origin.name}"
        opts = {}
        opts[:credentials] = @db.credentials if @db.credentials
        rugged_origin.push(repository.references.each_name.to_a, opts)
      end
    end

    private

    # https://git-scm.com/book/en/v2/Git-Internals-Git-References
    # http://grimoire.ca/git/theory-and-practice/refs-and-names

    def reference(name)
      repository.references["refs/heads/#{name}"]
    end

    def rugged_origin
      repository.remotes['origin']
    end

    private

    def parse_name_from_url url
      if url.include? ":"
        name = url.split(":").last
      else
        parts = url.split("/")
        name = parts.last
      end
      name.gsub(/\.git$/,"")
    end

    def clone!
      opts = {}
      opts[:checkout_branch] = default_branch if default_branch
      opts[:credentials] = @db.credentials if @db.credentials

      @logger.info "Cloning #{remote_url} (#{default_branch}) into #{local_path}"
      Rugged::Repository.clone_at(remote_url, local_path, opts)
      rugged_origin.fetch("+refs/*:refs/*", opts) # TODO: make this unnecessary?
    end

    def commit ref, new_tree, options = {}
      commit_options = {}
      commit_options[:tree] = new_tree
      commit_options[:author] = options[:author] || @db.committer
      commit_options[:committer] = @db.committer || options[:author]
      commit_options[:message] = options[:message] || ""
      commit_options[:parents] = repository.empty? ? [] : [ ref.target ].compact

      commit_oid = Rugged::Commit.create(repository, commit_options)

      if ref.is_a? Rugged::Reference
        ref = repository.references.update(ref, commit_oid)
      else
        ref = repository.references.create(ref, commit_oid)
      end
      if (!options[:branch]) || (options[:branch] == default_branch)
        repository.reset(commit_oid, :hard)
      end

      if !repository.bare?
        push!
      end

      if ref.target.oid == commit_oid
        return true
      else
        return false
      end
    end

    # http://stackoverflow.com/questions/24493392/check-what-files-are-staged-in-git-with-rugged-ruby
    # http://www.rubydoc.info/gems/rugged/Rugged/Repository#status-instance_method
    # @repo.repository.status {|file, status_data| puts file}
    # this outputs something for each changed file or untracked file. like `git status`

    # http://www.rubydoc.info/gems/rugged/Rugged/Index#add_all-instance_method
    # http://www.rubydoc.info/gems/rugged/Rugged/Index#update_all-instance_method
    # index.add_all
    # index.update_all
    # @repo.repository.lookup(index['README'][:oid]).content
    # this picks up changes, but doesn't seem to pick up new files



    #### leaving for reference
    #### no longer needed - using Rugged::Index methods instead
    # recursively updates a tree.
    # returns the oid of the new tree
    # blob_oid is either an object id to the file blob
    # or if nil, that path is removed from the tree    
    # def update_tree repo, tree, path, blob_oid
    #   segments = path.split("/")
    #   segment = segments.shift
    #   if tree
    #     builder = Rugged::Tree::Builder.new(repo, tree)
    #   else
    #     builder = Rugged::Tree::Builder.new(repo)
    #   end
    #   if segments.length > 0
    #     rest = segments.join("/")
    #     if builder[segment]
    #       # puts '1', segment, rest
    #       original_tree = repo.lookup(builder[segment][:oid])
          

    #       # Throws error instead of returning false, but that's a rugged bug
    #       # fixed in https://github.com/libgit2/rugged/pull/521
    #       # can do this instead of explicitly testing for existence of segment
    #       builder.remove(segment) 

    #       new_tree = update_tree(repo, original_tree, rest, blob_oid)
    #       builder << { :type => :tree, :name => segment, :oid => new_tree, :filemode => 0040000 }
    #       return builder.write
    #     else
    #       # puts '2', segment, rest
    #       new_tree = update_tree(repo, nil, rest, blob_oid)
    #       builder << { :type => :tree, :name => segment, :oid => new_tree, :filemode => 0040000 }
    #       return builder.write
    #     end
    #   else
    #     if builder[segment]
    #       builder.remove(segment) # Throws error instead of returning false, but that's a rugged bug
    #       # TODO: after https://github.com/libgit2/rugged/pull/521 is released, can remove conditional check
    #     end
    #     if !blob_oid.nil?
    #       builder << { :type => :blob, :name => segment, :oid => blob_oid, :filemode => 0100644 }
    #     end
    #     return builder.write
    #   end
    # end

  end
end
