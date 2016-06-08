require 'rugged'

module CapitalGit
  class LocalRepository

    class Local
      def initialize(parent, name, options={})
        @parent = parent
        @name = name

        @logger = CapitalGit.logger

        @directory = options[:directory] || options["directory"] || ""
      end

      attr_reader :name, :directory

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

      def committer
        @parent.database.committer
      end

      def local_path
        File.join(@parent.database.local_path, @name)
      end

      def branches
        # the branches BranchCollection contains remote branches,
        # while the .branch? method only returns true for local branches
        repository.branches.select {|b| b.branch? }.map do |b|
          {
            :name => b.name,
            :commit => format_commit(b.target),
            :head? => b.head?
          }
        end
      end

      ###
      # read / write methods on local repo
      ###

      def list(options={})

        return [] if repository.empty?

        target = _get_commit(options)

        items = []
        target.tree.walk_blobs do |root,entry|
          if root[0,@directory.length] == @directory
            if root.length > 0
              path = File.join(root, entry[:name])
            else
              path = entry[:name]
            end
            items << {:entry => format_entry(entry), :path => path}
          end
        end

        items
      end

      def log(options={})
        limit = options[:limit] || 10


        return [] if repository.empty?

        target = _get_commit(options)

        walker = Rugged::Walker.new(repository)
        walker.push(target.oid)
        walker.sorting(Rugged::SORT_DATE)
        walker.push(target)
        walker.map do |commit|
          format_commit(commit)
        end.compact.first(limit)
      end

      # read the contents of a file
      def read(key, options={})

        return nil if repository.empty?

        commit = _get_commit(options)

        resp = {}

        if !commit.nil?
          index = Rugged::Index.new
          index.read_tree(commit.tree)
          entry = index[key]
          if !entry.nil?
            blob = repository.read(entry[:oid])
            resp[:value] = blob.data.force_encoding('UTF-8')
            resp[:entry] = format_entry(entry)
            walker = Rugged::Walker.new(repository)
            walker.push(commit.oid)
            walker.sorting(Rugged::SORT_DATE)
            walker.push(commit)
            resp[:commits] = walker.map do |commit|
              if commit.diff(paths: [key]).size > 0
                format_commit(commit)
              else
                nil
              end
            end.compact.first(10)
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
      def read_all options={mode: :flat}

        if repository.empty?
          return options[:mode] == :tree ? {} : []
        end

        target = _get_commit(options)
        return nil if target.nil?

        if options[:mode] == :tree
          items = {}
          target.tree.walk(:preorder) do |root,entry|
            if entry[:type] == :blob
              blob = repository.read(entry[:oid])
              if root.length > 0
                path = File.join(root, entry[:name])

                # if root = "subdir/subdir2/"
                # then this bit does items["subdir"]["subdir2"][entry[:name]] = ...
                path_keys = root.split("/")
                path_keys.inject(items, :fetch)[entry[:name]] = {:path => path, :value => blob.data.force_encoding('UTF-8')}
              else
                items[entry[:name]] = {:path => entry[:name], :value => blob.data.force_encoding('UTF-8')}
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
        else # flat
          items = []

          index = Rugged::Index.new
          index.read_tree(target.tree)
          items = index.map {|entry| {:path => entry[:path], :value => repository.read(entry[:oid]).data.force_encoding('UTF-8')} }
        end

        items
      end

      def diff(commit_sha, commit_sha2=nil, options={})

        if !commit_sha2.nil? 
          # diff between :commit_sha and :next_commit_sha
          left = repository.lookup(commit_sha)
          right = repository.lookup(commit_sha2)
        else 
          # passed one arg, diff between HEAD & :commit_sha 
          left = repository.head.target
          right = repository.lookup(commit_sha)
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
      # or latest on :commit_sha =>
      def show(commit_sha = nil, options={branch: nil})

        # find latest or specific commit
        if !options[:branch].nil? 
          commit = _get_commit(options)
          return nil if commit.nil?
        elsif !commit_sha.nil?
          commit = _get_commit(commit_sha)
          return nil if commit.nil?
        else
          commit = repository.head.target
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

        format_commit(commit).merge(:changes => changes)
      end

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
            ref = repository.references["refs/heads/#{options[:branch]}"]
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

        return _create_commit(ref, new_tree, options)
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
            ref = repository.references["refs/heads/#{options[:branch]}"]
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

        return _create_commit(ref, new_tree, options)
      end


      # delete a specific file
      def delete(key, options={})
        return false if repository.empty?

        if options[:branch]
          ref = repository.references["refs/heads/#{options[:branch]}"]
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

        return _create_commit(ref, new_tree, options)
      end

      private

      # https://git-scm.com/book/en/v2/Git-Internals-Git-References
      # http://grimoire.ca/git/theory-and-practice/refs-and-names

      def format_entry(entry)
        if entry.has_key?(:path)
          entry[:name] = entry[:path].split("/").last
        end
        entry.select {|key, value| [:name, :oid].include? key }
      end

      def format_commit(commit)
        {
          :oid => commit.oid,
          :message => commit.message,
          :author => commit.author,
          :committer => commit.committer,
          :time => commit.time
        }
      end


      # returns a commit object based on a passed
      # - options hash specifying :branch or :sha
      # - string branch name
      # - string commit sha
      # - if an options hash without either :branch or :sha, or neither hash nor string is passed
      #   return the default, repository.head
      # - if the requested object can't be found, return nil
      def _get_commit to_resolve=nil
        if to_resolve.is_a? Hash
          if to_resolve[:branch]
            ref = repository.branches[to_resolve[:branch]]
            return nil if ref.nil?
            return ref.target
          elsif to_resolve[:sha]
            begin
              commit = repository.lookup(to_resolve[:sha])
              return nil if !commit.is_a?(Rugged::Commit)
              return commit
            rescue Rugged::OdbError
              return nil
            end
          else
            return repository.head.target
          end
        elsif to_resolve.is_a? String
          ref = repository.branches[to_resolve]
          return ref.target if !ref.nil?
          begin
            commit = repository.lookup(to_resolve)
            return nil if !commit.is_a?(Rugged::Commit)
            return commit
          rescue Rugged::OdbError
            return nil
          end
        else
          return repository.head.target
        end
      end

      def _create_commit ref, new_tree, options = {}
        commit_options = {}
        commit_options[:tree] = new_tree
        commit_options[:author] = options[:author] || committer
        commit_options[:committer] = committer || options[:author]
        commit_options[:message] = options[:message] || ""
        commit_options[:parents] = repository.empty? ? [] : [ ref.target ].compact

        commit_oid = Rugged::Commit.create(repository, commit_options)

        if ref.is_a? Rugged::Reference
          ref = repository.references.update(ref, commit_oid)
        else
          ref = repository.references.create(ref, commit_oid)
        end
        if (!options[:branch]) || (options[:branch] == @parent.default_branch)
          repository.reset(commit_oid, :hard)
        end

        if !repository.bare?
          @parent.push!
        end

        if ref.target.oid == commit_oid
          return true
        else
          return false
        end
      end
    end


    # database is a CapitalGit::Database
    # url is the location of the remote git repo
    def initialize database, url, options={}
      @db = database
      @url = url
      @name = parse_name_from_url(@url)
      @default_branch = options[:default_branch] || options["default_branch"] # TODO: can we default to remote's default branch?
      @logger = CapitalGit.logger

      @local = Local.new(self, @name, options)
      pull!
    end

    attr_reader :name, :url, :default_branch

    PROXIED_HELPER_METHODS = %w{local_path}.map(&:to_sym)
    PROXIED_READ_METHODS = %w{branches list log read read_all diff show}.map(&:to_sym)
    PROXIED_WRITE_METHODS = %w{write write_many delete}.map(&:to_sym)

    def method_missing(method, *args, &block)
      # puts "method_missing #{method}"

      if PROXIED_HELPER_METHODS.include? method
        @local.send(method, *args, &block)
      elsif PROXIED_READ_METHODS.include? method
        pull!
        @local.send(method, *args, &block)
      elsif PROXIED_WRITE_METHODS.include? method
        @local.send(method, *args, &block)
      else
        # puts "method missing #{method}"
      end
    end

    ###
    # helper methods
    # shortcuts
    ###

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
      @local.repository
    end


    ###
    # methods for interacting with remote
    # manage lifecycle and relationship with server
    ###

    def sync &blk
      pull!
      blk.call(@local)
    end

    # stubbed test means that this version of pull! never gets called in test
    # so even if we did successfully overwrite or alias it
    # the test wouldn't know
    # need to stub something internal to it

    def pull!
      if repository.nil?
        @logger.info "Repository at #{@local.local_path} doesn't exist"
        return clone!
      else
        @logger.info "Fetching #{rugged_origin.name} into #{@local.local_path}"
        opts = {}
        opts[:credentials] = @db.credentials if @db.credentials
        opts[:update_tips] = lambda do |ref, old_oid, new_oid|
          @logger.info "Fetched #{ref}"
          if (ref.gsub("refs/remotes/#{rugged_origin.name}/","") == repository.head.name.gsub("refs/heads/",""))
            @logger.info "Updated #{repository.head.name} from #{old_oid} to #{new_oid}"
            repository.reset(new_oid, :hard)
          end
        end
        return rugged_origin.fetch("+refs/*:refs/*", opts)
      end
    end

    def push!
      if !repository.nil?
        @logger.info "Pushing #{@local.local_path} to #{rugged_origin.name}"
        opts = {}
        opts[:credentials] = @db.credentials if @db.credentials
        rugged_origin.push(repository.references.each_name.to_a, opts)
      end
    end

    private

    def rugged_origin
      repository.remotes['origin']
    end

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

      @logger.info "Cloning #{remote_url} (#{default_branch}) into #{@local.local_path}"
      Rugged::Repository.clone_at(remote_url, @local.local_path, opts)
      rugged_origin.fetch("+refs/*:refs/*", opts) # TODO: make this unnecessary?
    end

  end
end
