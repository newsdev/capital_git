require 'rugged'
require 'securerandom'

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
        @parent.repository
      end

      def committer
        @parent.database.committer
      end

      def local_path
        File.join(@parent.database.local_path, @name)
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
        walker.sorting(Rugged::SORT_DATE|Rugged::SORT_TOPO)
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

      # https://git-scm.com/docs/git-diff
      # http://www.gnu.org/software/diffutils/manual/diffutils.html#Comparison
      # https://idnotfound.wordpress.com/2009/05/09/word-by-word-diffs-in-git/
      # https://www.kernel.org/pub/software/scm/git/docs/gitattributes.html
      # http://stackoverflow.com/questions/2013091/coloured-git-diff-to-html
      # https://gitlab.com/gitlab-org/gitlab_git/blob/master/lib/gitlab_git/encoding_helper.rb
      # https://diff2html.rtfpessoa.xyz/

      def diff(ref, ref2=nil, options={paths: nil})

        if !ref2.nil? 
          left = _get_commit(ref)
          right = _get_commit(ref2)
        else 
          # passed one arg, diff between HEAD & :ref 
          left = _get_commit(ref)
          right = repository.head.target
        end 

        diff_opts = {}
        if options[:paths] 
          diff_opts = {:paths => options[:paths]}
        end

        diff = repository.diff(left, right, diff_opts) 
        diff.find_similar! # calculate which are renames instead of delete/adds

        # changes is each file's patch
        changes = _get_changes(diff)


        {
          :commits => [left.oid, right.oid],
          :files_changed => diff.stat[0],
          :additions => diff.stat[1],
          :deletions => diff.stat[2],
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
          parent_commit = commit.parents[0]
          diff = parent_commit.diff(commit)
        else
          diff = Rugged::Tree.diff(repository,nil,commit)
        end
        diff.find_similar! # calculate which are renames instead of delete/adds

        changes = _get_changes(diff)

        format_commit(commit).merge(:diff => {
          # :stats => diff.stat,
          :files_changed => diff.stat[0],
          :additions => diff.stat[1],
          :deletions => diff.stat[2],
          :changes => changes
          })
      end

      def branches options={base: nil, paths: nil}
        select_block = proc do |b|
          _filter_branch(b, options)
        end

        if options[:base].nil?
          # the branches BranchCollection contains remote branches,
          # while the .branch? method only returns true for local branches
          return repository.branches.select(&select_block).map do |b|
            {
              :name => b.name,
              :head? => b.head?,
              :commit => format_commit(b.target)
            }
          end
        else
          base_commit = repository.branches[options[:base]]

          diff_opts = {}
          if options[:paths] 
            diff_opts = {:paths => options[:paths]}
          end

          # attempt to return how different each branch is from `options[:base]`
          return repository.branches.select(&select_block).map do |b|
            commit = b.target

            diff = repository.diff(base_commit.target, commit, diff_opts)
            changes = _get_changes(diff)
            {
              :name => b.name,
              :head? => b.head?,
              :base? => base_commit == commit,
              :commit => format_commit(b.target),
              :diff => {
                :files_changed => diff.stat[0],
                :additions => diff.stat[1],
                :deletions => diff.stat[2],
                :changes => changes
              }
            }
          end
        end
      end

      ##
      # create a branch with a uniquely generated name
      #
      def create_branch(options={})
        random_string = SecureRandom.hex # looks too much like an object id
        branch_name = "capitalgit-#{random_string}"
        base = repository.head.target.oid
        ref = repository.branches.create(branch_name, base)
        # ref # format branch ref
        return {
          :name => ref.name,
          :head? => ref.head?,
          :commit => format_commit(ref.target)
        }
      end

      # either a branch object
      # or a string
      def delete_branch(branch, options={})
        if branch.is_a? Hash
          branch = branch[:name] || branch['name'] || nil
        end
        repository.branches.delete(branch)
      end


      # TODO:
      # do we want a method that shows the individual commits between merge_base and merge_head?


      def merge_preview(branch, options={})
        if branch.is_a? Hash
          branch = branch[:name] || branch['name'] || nil
        end
        base = lambda { return repository.head }

        merge_head = repository.branches[branch].target.oid
        merge_base = repository.merge_base(base.call.target, merge_head)

        return diff(merge_base, merge_head, options)
      end

      # return commit object on success
      # alternate merge object on conflict
      # false on other failure
      # 
      # a calling app would want to...
      # update all files with head
      # update a revision log
      # show conflicts to be merged
      # show a diff

      # TODO: allow a no-ff option to override merge_analysis fastforward
      # so that merges that represent "approving" changes are explicit.
      # maybe if options has 'author' that always forces no-ff?

      def merge_branch(branch, options={})
        if branch.is_a? Hash
          branch = branch[:name] || branch['name'] || nil
        end

        base = lambda { return repository.head }

        other_branch = repository.branches[branch]
        branch_commit = other_branch.target
        # head_commit = repository.head.target
        head_commit = base.call.target


        # only works on HEAD
        # http://www.rubydoc.info/gems/rugged/Rugged/Repository#merge_analysis-instance_method
        # :normal, :up_to_date, :fastforward, :unborn
        merge_analysis = repository.merge_analysis(branch_commit)

        if merge_analysis.include?(:up_to_date)
          # no merge needed
          return format_commit(base.call.target)
        elsif merge_analysis.include?(:fastforward)
          # repository.checkout_tree(other_branch.target) # unnecessary
          repository.reset(other_branch.target_id, :hard)
          # TK: for non-head reference updates, use this
          # repository.references.update(base_branch, other_branch.target_id)

          if !repository.bare?
            @parent.push!
          end
          if base.call.target.oid == other_branch.target.oid
            return format_commit(base.call.target)
          else
            return false
          end
        elsif merge_analysis.include?(:normal)
          # puts "attempt automerge"
          old_tree = head_commit.tree.oid

          # possible rugged bug
          # # if renames true is passed, the index gets all screwed up
          # merged_index = repository.merge_commits(head_commit, branch_commit, {renames: true})
          merged_index = repository.merge_commits(head_commit, branch_commit)
          # merged_index = head_commit.tree.merge(branch_commit.tree)
          # puts "MERGED: conflicts: #{merged_index.conflicts?}"
          # merged_index.each {|entry| puts entry.inspect }

          if !merged_index.conflicts?
            # automerge succeeded =)
            new_tree = merged_index.write_tree(repository)
            opts = options.merge({parents: [head_commit.oid, branch_commit.oid]})
            opts[:branch] = options[:head] if options[:head]
            if _create_commit(base.call, new_tree, opts)
              return format_commit(base.call.target)
            end
          else
            # automerge failed =(
            # puts "CONFLICTS!"
            # merged_index.each {|entry| puts entry.inspect }
            # stage indexes
            # http://stackoverflow.com/questions/4084921/what-does-the-git-index-contain-exactly
            # https://git-scm.com/book/en/v2/Git-Tools-Advanced-Merging
            # might also want to see git log between head and merge_head
            return {
              :success => false,
              :orig_head => format_commit(head_commit),
              :merge_head => format_commit(branch_commit),
              :merge_base => format_commit(repository.lookup(repository.merge_base(branch_commit, head_commit))),
              :conflicts => merged_index.conflicts.map do |conflict|
                {
                  :path => conflict[:ancestor][:path],
                  :merge_file => merged_index.merge_file(conflict[:ancestor][:path], {
                      :style => :standard
                    })[:data],
                  :ancestor => {
                    :path => conflict[:ancestor][:path],
                    :value => repository.read(conflict[:ancestor][:oid]).data.force_encoding('UTF-8')
                  },
                  :ours => {
                    :path => conflict[:ours][:path],
                    :value => repository.read(conflict[:ours][:oid]).data.force_encoding('UTF-8')
                  },
                  :theirs => {
                    :path => conflict[:theirs][:path],
                    :value => repository.read(conflict[:theirs][:oid]).data.force_encoding('UTF-8')
                  }
                }
              end
            }

            # TODO:
            # in addition to the conflicts
            # should we just send the whole index... or any files that have a diff with merge_base
            # so the UI can display what merged cleanly?
          end
        elsif merge_analysis.include?(:unborn)
          repository.reset(other_branch.target_id, :hard)
          if !repository.bare?
            @parent.push!
          end
          return format_commit(base.call.target)
        else
          raise "Failed merge_analysis. Don't know what to do. #{merge_analysis}"
        end
      end

      # an explicit force merge to resolve conflicts
      # where the contents of files are specified
      # along with the parent commit ids
      def write_merge_branch files, branch, orig_head, merge_head, options={}
        return [false, "No files"] if files.length == 0
        if branch.is_a? Hash
          branch = branch[:name] || branch['name'] || nil
        end
        base = lambda { return repository.head }

        branch_commit = repository.branches[branch].target
        head_commit = base.call.target

        if (branch_commit.oid != merge_head) && (head_commit.oid != orig_head)
          # TK: heads no longer match, they've changed while you were resolving conflicts
          # for now dump the resolved conflict and just return an error
          # but maybe in the future, commit this as a new branch, then try and merge again?
          # and return more conflicts?
          # maybe instead:
          #    write just to the branch?
          #    attempt to automerge?
          #    either succeed or return more conflicts?

          return [false, "HEAD and MERGE_HEAD no longer match what was resolved"]
        end

        merged_index = repository.merge_commits(head_commit, branch_commit)

        files.each do |file|
          updated_oid = repository.write(file[:value], :blob)
          merged_index.update(:path => file[:path], :oid => updated_oid, :mode => 0100644, :stage => 0)
          merged_index.conflict_remove(file[:path])
        end
        if merged_index.conflicts?
          # puts merged_index.each {|entry| puts entry.inspect }
          return [false, "Not all conflicts resolved"] # there are still conflicts!
          # TK: return those conflicts, formatted same as with merge_branch
        end

        if !options[:message]
          options[:message] = "Resolved conflicts in #{files.map {|f| f[:path]}.join(' ')}"
        end

        new_tree = merged_index.write_tree(repository)
        opts = options.merge({parents: [head_commit.oid, branch_commit.oid]})
        opts[:branch] = options[:head] if options[:head]
        if commit_oid = _create_commit(base.call, new_tree, opts)
          return [format_commit(repository.lookup(commit_oid)), nil]
        else
          return [false, "Failed to create commit"]
        end
      end

      # TODO how atomic can we make a write? so that it's not considered written
      # until something has been pushed to the remote and persisted?
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

        if commit_oid = _create_commit(ref, new_tree, options)
          return format_commit(repository.lookup(commit_oid))
        else
          return false
        end
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
          index.update(:path => file[:path], :oid => updated_oid, :mode => 0100644)
        end
        new_tree = index.write_tree(repository)

        if commit_oid = _create_commit(ref, new_tree, options)
          return format_commit(repository.lookup(commit_oid))
        else
          return false
        end
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

        if commit_oid = _create_commit(ref, new_tree, options)
          return format_commit(repository.lookup(commit_oid))
        else
          return false
        end
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
          :commit => commit.oid,
          # :parents => commit.parents.map {|p| p.oid} # TODO: should we show parents or something? to indicate merge_commits?
          :message => commit.message,
          :author => commit.author,
          :committer => commit.committer,
          :time => commit.time
        }
      end


      def _filter_branch(branch, filter_opts={})
        if (filter_opts[:author_email] || filter_opts[:author_name]) && branch.branch?
          # check all commits differing between branch and base
          # to see if any of those commits have one by either author email or name
          if filter_opts[:base]
            base = repository.branches[options[:base]]
          else
            base = repository.head
          end

          if branch.target.author[:email] == filter_opts[:author_email] ||
              branch.target.author[:name] == filter_opts[:author_name]
            return true
          end

          merge_base = repository.merge_base(branch.target, base.target)
          match = false
          
          # take this array up until merge_base.oid
          branch.target.parents.each do |commit|
            break if commit.oid == merge_base
            if commit.author[:email] == filter_opts[:author_email] ||
                commit.author[:name] == filter_opts[:author_name]
              match = true
              break
            end
          end

          return match
        else
          return branch.branch?
        end
      end

      # returns a commit object based on a passed
      # - options hash specifying :branch or :sha
      # - string branch name
      # - string commit sha
      # - if an options hash without either :branch or :sha, or neither hash nor string is passed
      #   return the default, repository.head
      # - if the requested object can't be found, return nil
      def _get_commit to_resolve=nil
        if to_resolve.is_a?(Rugged::Commit)
          return to_resolve
        elsif to_resolve.is_a? Hash
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
        commit_options[:message] = Rugged.prettify_message(options[:message] || "")
        if options[:parents].nil?
          commit_options[:parents] = repository.empty? ? [] : [ ref.target ].compact
        else
          commit_options[:parents] = options[:parents]
        end

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
          # return true
          return commit_oid
        else
          return false
        end
      end

      # change summary without line-by-line patch
      # diff.each_delta
      # dlt = diff.each_delta.first
      # new file
      # @repo.repository.read(dlt.new_file[:oid]).data.force_encoding("UTF-8")

      # changed_paths = diff.each_delta.map {|d| [d.old_file[:path], d.new_file[:path]]}.flatten.uniq

      # diff.stat
      # [ files/additions/deletions ]

      # TK?: allow a version of changes keyed off of path
      # instead of change status

      def _get_changes diff
        diff.each_patch.reduce({}) do |memo, patch|

          # patch has lines
          # patch.lines
          # patch.each_hunk
          # http://www.rubydoc.info/gems/rugged/Rugged/Patch
          # p.stat [ additions/deletions ]

          dlt = patch.delta
          if !memo.has_key? dlt.status
            memo[dlt.status] = []
          end
          memo[dlt.status] << {
            :old_path => dlt.old_file[:path],
            :new_path => dlt.new_file[:path],
            :patch => patch.to_s.force_encoding('UTF-8'),
            :additions => patch.additions,
            :deletions => patch.deletions,
          }
          memo
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
    end

    attr_reader :name, :url, :default_branch

    PROXIED_HELPER_METHODS = %w{local_path}.map(&:to_sym)
    PROXIED_READ_METHODS = %w{branches list log read read_all diff show merge_preview}.map(&:to_sym)
    PROXIED_WRITE_METHODS = %w{write write_many delete create_branch delete_branch merge_branch write_merge_branch}.map(&:to_sym)

    def method_missing(method, *args, &block)
      # puts "method_missing #{method}"
      set_head = lambda do
        if !args.last.nil? && args.last.is_a?(Hash) && args.last[:head]
          repository.head = repository.branches[args.last[:head]].canonical_name
          repository.checkout_head(:strategy => :force)
        elsif !@default_branch.nil?
          repository.head = repository.branches[@default_branch].canonical_name
          repository.checkout_head(:strategy => :force)
        end
      end

      if PROXIED_HELPER_METHODS.include? method
        set_head.call
        @local.send(method, *args, &block)
      elsif PROXIED_READ_METHODS.include? method
        if @repository.nil?
          repository # this clones/pulls the repo and defines @repository
        else
          pull!
        end
        set_head.call
        @local.send(method, *args, &block)
      elsif PROXIED_WRITE_METHODS.include? method
        set_head.call
        @local.send(method, *args, &block)
      else
        super(method, *args, &block)
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
      if @repository.nil?
        begin
          @repository = Rugged::Repository.new(@local.local_path)
          pull!
        rescue
          @logger.info "Repository at #{@local.local_path} doesn't exist, will try to clone..."
          clone!
        end
      end
      @repository
    end

    ###
    # methods for interacting with remote
    # manage lifecycle and relationship with server
    ###

    def sync &blk
      if @repository.nil?
        repository
      else
        pull!
      end
      blk.call(@local)
    end

    # stubbed test means that this version of pull! never gets called in test
    # so even if we did successfully overwrite or alias it
    # the test wouldn't know
    # need to stub something internal to it

    def pull!
      @logger.info "Fetching #{rugged_origin.name} into #{@local.local_path}"
      opts = {}
      opts[:credentials] = @db.credentials if @db.credentials
      opts[:update_tips] = lambda do |ref, old_oid, new_oid|
        @logger.info "Fetched #{ref}"
        if (ref.gsub("refs/remotes/#{rugged_origin.name}/","") == @repository.head.name.gsub("refs/heads/",""))
          @logger.info "Updated #{@repository.head.name} from #{old_oid} to #{new_oid}"
          @repository.reset(new_oid, :hard)
        end
      end
      return rugged_origin.fetch("+refs/*:refs/*", opts)
    end

    def push!
      if !@repository.nil?
        @logger.info "Pushing #{@local.local_path} to #{rugged_origin.name}"
        opts = {}
        opts[:credentials] = @db.credentials if @db.credentials
        rugged_origin.push(@repository.references.select {|r| r.branch? }.map {|r| r.name }, opts)
      end
    end

    def clone!
      opts = {}
      opts[:checkout_branch] = default_branch if default_branch
      opts[:credentials] = @db.credentials if @db.credentials

      @logger.info "Cloning #{remote_url} (#{default_branch}) into #{@local.local_path}"
      Rugged::Repository.clone_at(remote_url, @local.local_path, opts)
      @repository = Rugged::Repository.new(@local.local_path)
      return rugged_origin.fetch("+refs/*:refs/*", opts) # TODO: make this unnecessary?
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

  end
end
