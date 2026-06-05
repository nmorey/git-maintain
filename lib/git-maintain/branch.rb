# Main module for git-maintain repository maintenance tool.
module GitMaintain

    # Class representing a single stable branch and actions that can be performed on it.
    class Branch < Common
        # List of all available maintenance actions.
        ACTION_LIST = [
            :cp, :steal, :list,
            :merge, :pull, :push, :monitor,
            :release, :reset, :create, :delete
        ]
        # Actions that do not require updating the remote repository first.
        NO_FETCH_ACTIONS = [
            :cp, :merge, :monitor, :release, :delete
        ]
        # Actions that do not require checking out the local branch before running.
        NO_CHECKOUT_ACTIONS = [
            :create, :delete, :list, :push, :monitor
        ]
        # Actions that run on all branches, regardless of target versions.
        ALL_BRANCHES_ACTIONS = [
            :create
        ]
        # Description map of actions for CLI help output.
        ACTION_HELP = {
            :cp => "Backport commits and eventually push them to github",
            :create => "Create missing local branches from all the stable branches",
            :delete => "Delete all local branches using the suffix",
            :steal => "Steal commit from upstream that fixes commit in the branch or were tagged as stable",
            :list => "List commit present in the branch but not in the stable branch",
            :merge => "Merge branch with suffix specified in -m <suff> into the main branch",
            :push => "Push branches to github for validation",
            :pull => "Rebase branches on top of the upstream one",
            :monitor => "Check the CI state of all branches",
            :release => "Create new release on all concerned branches",
            :reset => "Reset branch against upstream",
        }
        # Configure action-specific command line options.
        #
        # @param action [Symbol] Selected action name
        # @param optsParser [OptionParser] The OptionParser instance to configure
        # @param opts [Hash] The options hash to populate
        def self.set_opts(action, optsParser, opts)
            opts[:base_ver] = 0
            opts[:version] = []
            opts[:commits] = []
            opts[:do_merge] = false
            opts[:push_force] = false
            opts[:no_ci] = false
            opts[:steal_base] = nil
            opts[:check_only] = false
            opts[:fetch] = nil
            opts[:watch] = false
            opts[:delete_remote] = false
            opts[:no_edit] = false
            opts[:stable] = false

            optsParser.on("-v", "--base-version [MIN_VER]", Integer, "Older release to consider.") {
                |val| opts[:base_ver] = val}
            optsParser.on("-V", "--version [regexp]", Regexp, "Regexp to filter versions.") {
                |val| opts[:version] << val}

            if  ALL_BRANCHES_ACTIONS.index(action) == nil &&
                action != :merge &&
                action != :delete then
                optsParser.on("-B", "--manual-branch <branch name>", "Work on a specific (non-stable) branch.") {
                    |val| opts[:manual_branch] = val}
            end

            if NO_FETCH_ACTIONS.index(action) == nil
                optsParser.on("--[no-]fetch", "Enable/Disable fetch of stable repo.") {
                    |val| opts[:fetch] = val}
            end

            case action
            when :cp
                optsParser.banner += "-c <sha1> [-c <sha1> ...]"
                optsParser.on("-c", "--sha1 [SHA1]", String, "Commit to cherry-pick. Can be used multiple time.") {
                    |val| opts[:commits] << val}
            when :delete
                optsParser.on("--remote", "Delete the remote staging branch instead of the local ones.") {
                    |val| opts[:delete_remote] = true}
            when :list
                optsParser.on("--stable", "List unreleased commits in the upstream stable branch.") {
                    opts[:stable] = true }
            when :merge
                optsParser.banner += "-m <suffix>"
                optsParser.on("-m", "--merge [SUFFIX]", "Merge branch with suffix.") {
                    |val| opts[:do_merge] = val}
            when :monitor
                optsParser.on("-w", "--watch <PERIOD>", Integer,
                              "Watch and refresh CI status every <PERIOD>.") {
                    |val| opts[:watch] = val}
                optsParser.on("--stable", "Check CI status on stable repo.") {
                    opts[:stable] = true }
            when :pull
                optsParser.on("--stable", "List unreleased commits in the upstream stable branch.") {
                    opts[:stable] = true }
            when :push
                optsParser.banner += "[-f]"
                optsParser.on("-f", "--force", "Add --force to git push (for 'push' action).") {
                    opts[:push_force] = true}
                optsParser.on("--stable", "Push to stable repo.") {
                    opts[:stable] = true }
                optsParser.banner += "[-T]"
                optsParser.on("-T", "--no-ci", "Ignore CI build status and push anyway.") {
                    opts[:no_ci] = true}
                optsParser.on("-c", "--check", "Check if there is something to be pushed.") {
                    opts[:check_only] = true}
            when :release
                optsParser.on("--no-edit", "Do not edit release commit nor tag.") {
                    opts[:no_edit] = true }
            when :steal
                optsParser.banner += "[-a][-b <HEAD>]"
                optsParser.on("-a", "--all", "Check all commits from master. "+
                                             "By default only new commits (since last successful run) are considered.") {
                    |val| opts[:steal_base] = :all}
                optsParser.on("-b", "--base <HEAD>", "Check all commits from this commit. "+
                                                     "By default only new commits (since last successful run) are considered.") {
                    |val| opts[:steal_base] = val}
            end
        end

        # Sanity check and normalize the parsed options for the given action.
        #
        # @param opts [Hash] Options hash to validate and configure
        # @raise [InvalidArgumentError] If options are invalid or conflicting
        def self.check_opts(opts)
            if opts[:action] == :release then
                if opts[:br_suff] != "master" then
                    raise InvalidArgumentError.new("Action #{opts[:action]} can only be done on 'master' suffixed branches")
                end
            end
            if opts[:action] == :delete && opts[:delete_remote] != true then
                if opts[:br_suff] == "master" then
                    raise InvalidArgumentError.new("Action #{opts[:action]} can NOT be done on 'master' suffixed branches")
                end
            end
            if opts[:action] == :push
                if opts[:stable] == true && opts[:push_force] == true then
                    raise InvalidArgumentError.new("Action push  can NOT be use both --stable and --force")
                end
            end
            opts[:version] = [ /.*/ ] if opts[:version].length == 0
        end

        # Factory method to load an instance of the Branch class or its repository-specific subclass.
        #
        # @param repo [Repo] The Repo instance
        # @param version [String] The branch version (e.g., '1.0')
        # @param ci [CI] The CI instance
        # @param branch_suff [String] Suffix of the branch (e.g., 'master')
        # @return [Branch] The loaded Branch instance (or subclass)
        # @raise [GitMaintainError] If class loading fails
        def self.load(repo, version, ci, branch_suff)
            repo_name = File.basename(repo.path)
            return GitMaintain::loadClass(Branch, repo_name, repo, version, ci, branch_suff)
        end

        protected
        # Print the diff between two branches and prompt for confirmation.
        #
        # @param opts [Hash] Options hash
        # @param br1 [String] First branch/ref
        # @param br2 [String] Second branch/ref
        # @param action_msg [String] Action message to prompt (e.g. 'submit')
        # @return [String] User prompt response ('y' or 'n')
        # @raise [RunError] If running git log fails
        def checkLog(opts, br1, br2, action_msg)
            puts "Diff between #{br1} and #{br2}"
            puts `git log --format=oneline #{br1} ^#{br2}`
            return "n" if action_msg.to_s() == ""
            rep = confirm(opts, "#{action_msg} this branch")
            return rep
        end

        # Print the diff/log between two branches.
        #
        # @param opts [Hash] Options hash
        # @param br1 [String] First branch/ref
        # @param br2 [String] Second branch/ref
        # @raise [RunError] If running git log fails
        def showLog(opts, br1, br2)
            log(:INFO, "Diff between #{br1} and #{br2}")
            puts `git log --format=oneline #{br1} ^#{br2}`
        end

        public
        # Initialize a new Branch instance, resolving local/remote branches, head references, and stable base.
        #
        # @param repo [Repo] The Repo instance
        # @param version [String] Suffix version (e.g. '1.0') or branch name
        # @param ci [CI] The CI instance
        # @param branch_suff [String] Branch suffix (e.g. 'master')
        # @raise [NoRefError] If resolving git references fails
        def initialize(repo, version, ci, branch_suff)
            GitMaintain::checkDirectConstructor(self.class)

            @path          = repo.path
            @repo          = repo
            @ci            = ci
            @version       = version
            @branch_suff   = branch_suff

            if version =~ /^[0-9]+$/
                @local_branch  = @repo.versionToLocalBranch(@version, @branch_suff)
                @remote_branch = @repo.versionToStableBranch(@version)
                @branch_type = :std
                @verbose_name = "v"+version
            else
                @remote_branch = @local_branch = version
                @branch_type = :user_specified
                @verbose_name = version
            end

            @head          = @repo.ref_exist?(@local_branch)
            @valid_ref     = "#{@repo.valid_repo}/#{@local_branch}"
            @remote_ref    = "#{@repo.stable_repo}/#{@remote_branch}"
            @stable_head   =
                begin
                    @repo.ref_exist?(@remote_ref)
                rescue
                    nil
                end
            case @branch_type
            when :std
                @stable_base   = @repo.findStableBase(@local_branch)
            when :user_specified
                @stable_base   = @remote_ref
            end
        end
        attr_reader :version, :local_branch, :head, :remote_branch, :valid_ref, :remote_ref, :stable_head,
                    :verbose_name, :exists, :stable_base


        # Check if the branch matches specified target version options.
        #
        # @param opts [Hash] Options hash with version/base filters
        # @return [Boolean, Symbol] `true` if targeted, `:too_old` or `:no_match` otherwise
        def is_targetted?(opts)
            return true if @branch_type == :user_specified
            if @version.to_i < opts[:base_ver] then
                return :too_old
            end
            opts[:version].each() {|regexp|
                return true if @version =~ regexp
            }
            return :no_match
        end

        # Checkout the git repository to this branch's local branch.
        #
        # @raise [RunError] If git checkout execution fails
        def checkout()
            runGitInteractive("checkout -q #{@local_branch}")
        end

        # Backport/cherry-pick the given array of commits into this branch.
        #
        # @param opts [Hash] Options hash containing `:commits` to pick
        # @raise [CPAbort] If cherry-pick is aborted by the user
        def cp(opts)
            opts[:commits].each(){|commit|
                prev_head=runGit("rev-parse HEAD")
                log(:INFO, "Applying #{@repo.getCommitHeadline(commit)}")
                begin
                    runGitInteractive("cherry-pick #{commit}")
                rescue RunError
                    begin
                        cp_fix(opts, commit)
                    rescue CPSkip => e
                        log(:INFO, e.message)
                    rescue CPAbort => e
                        log(:INFO, "Cherry-pick aborted by user.")
                        raise e
                    end
		end
                new_head=runGit("rev-parse HEAD")
                # Do not make commit pretty if it was not applied
                if new_head != prev_head
		    make_pretty(commit)
                end
            }
        end

        # Steal upstream commits that are not present in this branch.
        # Uses `steal_all` and marks the last successful run with a git tag if successful.
        #
        # @param opts [Hash] Options hash
        # @raise [RunError] If git tags/execution fails
        def steal(opts)
            base_ref=@stable_base

            # If we are not force checking everything,
            # try to start from the last tag we steal upto
            case opts[:steal_base]
            when nil
                begin
                    sha = runGit("rev-parse 'git-maintain/steal/last/#{@stable_base}' 2>&1")
                    base_ref=sha
                    log(:VERBOSE, "Starting from last successfull run:")
                    log(:VERBOSE, @repo.getCommitHeadline(base_ref))
                rescue RunError
                    # No matching tag found. Not an issue
                end
            when :all
                base_ref=@stable_base
            else
                begin
                    sha = runGit("rev-parse #{opts[:steal_base]} 2>&1")
                    base_ref=sha
                    log(:VERBOSE, "Starting from base:")
                    log(:VERBOSE, @repo.getCommitHeadline(base_ref))
                rescue RunError
                    crit("Could not find specified base '#{opts[:steal_base]}'")
                end
            end

            master_sha=runGit("rev-parse origin/master")

            begin
                steal_all(opts, "#{base_ref}..#{master_sha}", true)

                # We picked all the commits (or nothing happened)
                # Mark the current master as the last checked point so we
                # can just steal from this point on the next run
                runGit("tag -f 'git-maintain/steal/last/#{@stable_base}' origin/master")
                log(:VERBOSE, "Marking new last successfull run at:")
                log(:VERBOSE, @repo.getCommitHeadline(master_sha))
            rescue CPSkip
                # Ignore the error
            end
        end

        # List all unreleased stable commits or commits in this branch but not in stable.
        #
        # @param opts [Hash] Options hash
        # @raise [RunError] If running git commands fails
        def list(opts)
            log(:INFO, "Working on #{@verbose_name}")
            if opts[:stable] == true then
                # List commits in the stable_branch that are no in the latest release
                showLog(opts, @remote_ref, runGit("describe --abbrev=0 #{@local_branch}"))
            else
                # List commits in the branch that are no in the stable branch
                showLog(opts, @local_branch, @remote_ref)
            end
        end

        # Merge the specified merge branch into this branch.
        #
        # @param opts [Hash] Options hash containing `:do_merge` branch name
        # @raise [RunError] If running git merge or system commands fails
        def merge(opts)
            merge_branch = @repo.versionToLocalBranch(@version, opts[:do_merge])

            # Make sure branch exists
            begin
                hash_to_merge = @repo.ref_exist?(merge_branch)
            rescue NoRefError
                log(:INFO, "Branch #{merge_branch} does not exists. Skipping...")
                return
            end

            # See if there is anything worth merging
            merge_base_hash = runGit("merge-base #{merge_branch} #{@local_branch}")
            if merge_base_hash == hash_to_merge then
                log(:INFO, "Branch #{merge_branch} has no commit that needs to be merged")
                return
            end

            rep = checkLog(opts, merge_branch, @local_branch, "merge")
            if rep == "y" then
                begin
                    runGitInteractive("merge #{merge_branch}")
                rescue RunError
                    log(:WARNING, "Merge failure. Starting bash for manual fixes. Exit shell to continue")
		    runBash("PS1_WARNING='MERGING'")
		end
            else
                log(:INFO, "Skipping merge")
                return
            end
        end

        # Pull/rebase the current branch against the upstream stable or validation reference.
        #
        # @param opts [Hash] Options hash
        # @raise [NoRefError] If checking remote ref existence fails with unexpected ref errors
        # @raise [RunError] If rebasing fails
        def pull(opts)
            remoteRef = opts[:stable] == true ? @remote_ref : @valid_ref

            # Make sure branch exists
            begin
                @repo.ref_exist?(remoteRef)
            rescue NoRefError
                log(:INFO, "Branch #{remoteRef} does not exists. Skipping...")
                return
            end
            runGitInteractive("rebase #{remoteRef}")

        end
        # Push the branch to the validation or stable repository.
        # Saves the push specs to `opts[:push_branches]` accumulator array.
        #
        # @param opts [Hash] Options hash containing configuration and the accumulator array
        # @raise [GitMaintainError] If CI checks fail or other git/CI errors occur
        def push(opts)
            remoteRef = opts[:stable] == true ? @remote_ref : @valid_ref

            # Check both where we want to push and the final remote_ref
            # We may have destroyed the validation branch but if we already merged
            # in the final repo, no need to worry about it.
            if same_sha?(@local_branch, remoteRef) ||
               same_sha?(@local_branch, @remote_ref) then
                log(:INFO, "Nothing to push on #{@local_branch}")
                return
            end

            # For stable branches, we need to check for CI
            if opts[:stable] == true &&
               (opts[:no_ci] != true && @NO_CI != true) &&
               @ci.checkValidState(self, @head) != true then
                log(:WARNING, "Build is not passed on CI. Skipping push to stable")
                return
            end

            if opts[:check_only] == true then
                checkLog(opts, @local_branch, @remote_ref, "")
                return
            end

            # For validation/CI push, let's go and push already
            if opts[:stable] != true
                opts[:push_branches] ||= []
                opts[:push_branches] << "#{@local_branch}:#{@local_branch}"
                return
            end

            # For stable, we need to confirm with the user that he really wants to push
            rep = checkLog(opts, @local_branch, @remote_ref, "submit")
            if rep == "y" then
                opts[:push_branches] ||= []
                opts[:push_branches] << "#{@local_branch}:#{@remote_branch}"
            else
                log(:INFO, "Skipping push to stable")
                return
            end
        end

        # Run the epilogue for the push action, executing the accumulated pushes.
        #
        # @param opts [Hash] Options hash containing configuration and accumulated branch specs in `opts[:push_branches]`
        # @param branches [Array] Ignored branch list from map send (we use accumulator in `opts[:push_branches]`)
        # @raise [RunError] If git push execution fails
        def push_epilogue(opts, branches)
            push_list = opts[:push_branches] || []
            return if push_list.length == 0

            repo = (opts[:stable] == true) ? opts[:repo].stable_repo : opts[:repo].valid_repo
            opts[:repo].runGit("push #{opts[:push_force] == true ? "-f" : ""} "+
                               "#{repo} #{push_list.join(" ")}")
        end

        # Monitor the build status on CI for the branch.
        # Displays the current status (e.g. success, started, errored) and handles prompt to show logs.
        #
        # @param opts [Hash] Options hash
        # @raise [GitMaintainError] If querying CI state or fetching logs fails
        def monitor(opts)
            ts = st = head = nil
            suff=""
            if opts[:stable] == true then
                st = @ci.getStableState(self, @stable_head)
                ts = @ci.getStableTS(self, @stable_head) if st == "started"
            else
                st = @ci.getValidState(self, @head)
                ts = @ci.getValidTS(self, @head) if st == "started"
            end

            case st
            when "started"
                suff= " at #{ts}"
            end
            log(:INFO, "Status for v#{@version}: " + st + suff)
            if @ci.isErrored(self, st) && opts[:watch] == false
                rep = "y"
                suff=""
                while rep == "y"
                    rep = confirm(opts, "see the build log#{suff}")
                    if rep == "y" then
                        log = @ci.getValidLog(self, @head)
                        tmp = `mktemp`.chomp()
                        tmpfile = File.open(tmp, "w+")
                        tmpfile.puts(log)
                        tmpfile.close()
                        system("less -r #{tmp}")
                        `rm -f #{tmp}`
                    end
                    suff=" again"
                end
            end
        end

        # Reset the branch to the upstream stable reference (warning: hard reset).
        #
        # @param opts [Hash] Options hash
        # @raise [RunError] If running git commands fails
        def reset(opts)
            if same_sha?(@local_branch, @remote_ref) then
                log(:INFO, "Nothing to reset")
                return
            end

            rep = checkLog(opts, @local_branch, @remote_ref, "reset")
            if rep == "y" then
                runGit("reset --hard #{@remote_ref}")
            else
                log(:INFO, "Skipping reset")
                return
            end
        end

        # Create a release on the current branch (dummy/unsupported method for the base Branch class).
        #
        # @param opts [Hash] Options hash
        def release(opts)
            log(:ERROR,"#No release command available for this repo")
        end

        # Create the missing local branch tracking the upstream remote stable reference.
        #
        # @param opts [Hash] Options hash
        # @raise [RunError] If git branch creation fails
        def create(opts)
            return if @head != ""
            log(:INFO, "Creating missing #{@local_branch} from #{@remote_ref}")
            runGit("branch #{@local_branch} #{@remote_ref}")
        end

        # Delete the branch (locally or remotely).
        # Saves the deletion specs to `opts[:delete_branches]` accumulator array.
        #
        # @param opts [Hash] Options hash containing configuration and the accumulator array
        # @raise [NoRefError] If checking remote ref existence fails with unexpected ref errors
        def delete(opts)
            if opts[:delete_remote] == true then
                begin
                    @repo.ref_exist?("#{@repo.valid_repo}/#{@local_branch}")
                rescue NoRefError
                    log(:DEBUG, "Skipping non existing remote branch #{@local_branch}.")
                    return
                end
                msg = "delete remote branch #{@repo.valid_repo}/#{@local_branch}"
            else
                msg = "delete branch #{@local_branch}"
            end
            rep = confirm(opts, msg)
            if rep == "y" then
                opts[:delete_branches] ||= []
                opts[:delete_branches] << @local_branch
            else
                log(:INFO, "Skipping deletion")
                return
            end
        end

        # Run the epilogue for the delete action, executing the accumulated deletions.
        #
        # @param opts [Hash] Options hash containing configuration and accumulated branch specs in `opts[:delete_branches]`
        # @param branches [Array] Ignored branch list from map send (we use accumulator in `opts[:delete_branches]`)
        # @raise [RunError] If git branch deletion fails
        def delete_epilogue(opts, branches)
            delete_list = opts[:delete_branches] || []
            return if delete_list.length == 0
            puts "Deleting #{opts[:delete_remote] == true ? "remote" : "local"} branches: #{delete_list.join(" ")}"
            rep = confirm(opts, "continue", true)
            if rep != "y" then
                log(:INFO, "Cancelling")
                return
            end
            if opts[:delete_remote] == true then
                opts[:repo].runGit("push #{opts[:repo].valid_repo} #{delete_list.map(){|x| ":" + x}.join(" ")}")
            else
                opts[:repo].runGit("branch -D  #{delete_list.join(" ")}")
            end
        end

        private
        # Add the given commit to the git notes blacklist for the current branch.
        #
        # @param commit [String] The commit SHA to blacklist
        # @raise [RunError] If running git notes fails
        def add_blacklist(commit)
  	    runGit("notes append -m \"#{@local_branch}\" #{commit}")
        end

        def is_blacklisted?(commit)
            begin
                runGit("notes show #{commit} 2> /dev/null").split("\n").each(){|br|
                    return true if br == @local_branch
                }
            rescue
            end
            return false
        end

        # Rewrite the commit message of the HEAD commit to reference the upstream commit.
        # Adds an "[ Upstream commit <SHA> ]" label.
        #
        # @param orig_commit [String] Original upstream commit SHA or reference
        # @param commit [String] Override commit SHA to display in the label
        # @raise [RunError] If running git commands fails
        def make_pretty(orig_commit, commit="")
            orig_sha=runGit("rev-parse #{orig_commit}")
            msg_commit = (commit.to_s() == "") ? orig_sha : commit

            msg_path=`mktemp`.chomp()
            msg_file = File.open(msg_path, "w+")
	    msg_file.puts runGit("log -1 --format=\"%s%n%n[ Upstream commit #{msg_commit} ]%n%n%b\" #{orig_commit}")
            msg_file.close()
	    runGit("commit -s --amend -F #{msg_path}")
            `rm -f #{msg_path}`
        end

        def is_in_tree?(commit, src_commit=commit)
            fullhash=nil
            begin
	        fullhash=@repo.ref_exist?(commit)
            rescue NoRefError
	        # This might happen if someone pointed to a commit that doesn't exist in our
	        # tree.
                log(:WARNING, "Commit #{src_commit} points to a SHA #{commit} not in tree")
		return false
	    end

	    # Hope for the best, same commit is/isn't in the current branch
	    if runGit("merge-base #{fullhash} HEAD") == fullhash then
		return true
	    end

	    # Grab the subject, since commit sha1 is different between branches we
	    # have to look it up based on subject.
	    subj=@repo.getCommitSubj(commit)

	    # Try and find if there's a commit with given subject the hard way
	    runGit("log --pretty=\"%H\" -F --grep \"#{subj.gsub("\"", '\\"')}\" "+
                         "#{@stable_base}..HEAD").split("\n").each(){|cmt|
                cursubj=runGit("log -1 --format=\"%s\" #{cmt}")
                if cursubj = subj then
	            return true
		end
	    }
	    return false
        end

        def is_relevant?(commit)
	    # Let's grab the commit that this commit fixes (if exists (based on the "Fixes:" tag)).
	    fixescmt=runGit("log -1 #{commit} | grep -i \"fixes:\" | head -n 1 | "+
                                  "sed -e 's/^[ \\t]*//' | cut -f 2 -d ':' | "+
                                  "sed -e 's/^[ \\t]*//' -e 's/\\([0-9a-f]\\+\\)(/\\1 (/' | cut -f 1 -d ' '")

	    # If this commit fixes anything, but the broken commit isn't in our branch we don't
	    # need this commit either.
	    if fixescmt != "" then
		if is_in_tree?(fixescmt, commit) then
                    return true
                else
                    return false
                end
            end

	    if runGit("show #{commit} | grep -i 'stable@' | wc -l") == "0" then
		return false
	    end

	    # Let's see if there's a version tag in this commit
	    full=runGit("show #{commit} | grep -i 'stable@'").gsub(/.* #?/, "")

	    # Sanity check our extraction
            if full =~ /stable/ then
                return false
            end

            full = runGit("rev-parse #{full}^{commit}")

	    # Make sure our branch contains this version
	    if runGit("merge-base #{@head} #{full}") == full then
		return true
	    end

	    # Tag is not in history, ignore
	    return false
        end

        # Cherry-pick a single commit, trying other stable alternatives if it fails.
        #
        # @param commit [String] Commit SHA to cherry-pick
        # @raise [CherryPickErrorException] If cherry-picking the commit (and its alternatives) fails
        def pick_one(commit)
            cpCmd="cherry-pick --strategy=recursive -Xpatience -x"
            runGitInteractive("#{cpCmd} #{commit} &> /dev/null", {}, false)
	    return if $? == 0

            if runGit("status -uno --porcelain | wc -l") == "0" then
		runGit("reset --hard")
                raise CherryPickErrorException.new("Failed to cherry pick commit #{commit}", commit)
	    end
	    runGit("reset --hard")

	    # That didn't work? Let's try that with every variation of the commit
	    # in other stable trees.
            @repo.find_alts(commit).each(){|alt_commit|
		runGitInteractive("#{cpCmd} #{alt_commit} &> /dev/null", {}, false)
		if $? == 0 then
		    return
		end
		runGit("reset --hard")
            }

	    # Still no? Let's go back to the original commit and hand it off to
	    # the user.
	    runGitInteractive("#{cpCmd} #{commit} &> /dev/null", {}, false)
            raise CherryPickErrorException.new("Failed to cherry pick commit #{commit}", commit)
        end

        # Handle user interaction to fix cherry-pick conflicts via an interactive shell.
        #
        # @param opts [Hash] Options hash
        # @param commit [String] Commit SHA with conflicts
        # @raise [CPAbort] If cherry-pick is aborted by the user
        # @raise [CPSkip] If the user skips this commit
        def cp_fix(opts, commit)
            runGitInteractive("diff")
            log( :INFO, "Entering subshell to fix conflicts. Exit when done")
            runSystem("PS1_WARNING='CP FIX' bash", false)
            rep = confirm(opts, "continue with scp [y(es), n(o), s(kip)]?", true, ["y", "n", "s"])
            case rep
            when "n"
                runGitInteractive("cherry-pick --abort")
                raise(CPAbort)
            when "s"
                runGitInteractive("cherry-pick --abort")
                e = CPSkip.new(commit.to_s())
                log(:INFO, e.to_s())
                raise(e)
            end
        end

        # Steal/cherry-pick a single commit from upstream, asking for confirmation if needed.
        #
        # @param opts [Hash] Options hash
        # @param commit [String] Commit SHA to cherry-pick
        # @param mainline [Boolean] Whether to treat this as a mainline cherry-pick (skips mapping checks)
        # @raise [CPSkip] If the user chooses to skip this commit
        # @raise [CPAbort] If the user chooses to abort cherry-picking
        def steal_one(opts, commit, mainline=false)
	    msg=''
            orig_cmt=commit

            if mainline == false then
		subj=@repo.getCommitSubj(commit)
                subj.gsub!(/"/, '\"')
		# Let's grab the mainline commit id, this is useful if the version tag
		# doesn't exist in the commit we're looking at but exists upstream.
		orig_cmt=runGit("log --no-merges --format=\"%H\" -F --grep \"#{subj}\" " +
                                      "#{@stable_base}..origin/master | tail -n1")

                if orig_cmt == "" then
                    log(:WARNING, "Could not find commit #{commit} in mainline")
                end
            end
            # If the commit doesn't apply for us, skip it
	    if is_relevant?(orig_cmt) != true
                return
	    end

            log(:VERBOSE, "Found relevant commit #{@repo.getCommitHeadline(commit)}")
	    if is_in_tree?(orig_cmt) == true
		# Commit is already in the stable branch, skip
                log(:VERBOSE, "Commit is already in tree")
                return
	    end

	    # Check if it's not blacklisted by a git-notes
	    if is_blacklisted?(orig_cmt) == true then
		# Commit is blacklisted
		log(:INFO, "Skipping 'blacklisted' commit " +
                           @repo.getCommitHeadline(orig_cmt))
                return
	    end

	    commit_desc = @repo.getCommitHeadline(commit)
            rep = "t"
            while rep != "y"
                rep = confirm(opts, "pick commit '#{commit_desc}' up ([y]es, [n]o, [b]lacklist)",
                              false, ["y", "n", "?", "b"])

                case rep
                when "y"
                    break
                when "n"
                    raise CPSkip.new(commit)
                when "b"
		    log(:INFO, "Blacklisting this commit for the current branch")
		    add_blacklist(commit)
		    raise CPSkip.new(commit)
                when "?"
                    runGitInteractive("show #{commit}", {}, false)
                end
            end

            prev_head=runGit("rev-parse HEAD")
            begin
		pick_one(commit)
            rescue CherryPickErrorException
                cp_fix(opts, commit)
            end
            new_head=runGit("rev-parse HEAD")

	    # If we didn't find the commit upstream then this must be a custom commit
	    # in the given tree - make sure the user checks this commit.
	    if orig_cmt == "" then
		msg="Custom"
		orig_cmt=runGit("rev-parse HEAD")
		log(:WARNING, "Custom commit, please double-check!")
		runBash("PS1_WARNING='CHECK'")
	    end
            if new_head != prev_head
		make_pretty(orig_cmt, msg)
            end
            return
        end

        # Steal/cherry-pick all upstream commits in the given revision range.
        #
        # @param opts [Hash] Options hash
        # @param range [String] Git revision range (e.g., 'base..HEAD')
        # @param mainline [Boolean] Whether to treat commits as mainline cherry-picks
        # @raise [CPSkip] If any cherry-pick of a patch is skipped by the user
        # @raise [CPAbort] If cherry-pick is aborted by the user
        def steal_all(opts, range, mainline = false)
            skipped = []
 	    runGit("log --no-merges --format=\"%H\" #{range} | tac").split("\n").each(){|commit|
                begin
                    steal_one(opts, commit, mainline)
                rescue CPSkip => e
                    log(:INFO, e.message)
                    skipped << commit
                rescue CPAbort => e
                    log(:INFO, "Cherry-pick aborted by user.")
                    raise e
                end
            }
            if skipped.length > 0
                raise CPSkip.new(skipped.join(" "))
            end
            return
        end

        def same_sha?(ref1, ref2)
            begin
                c1=@repo.ref_exist?(ref1)
                c2=@repo.ref_exist?(ref2)
                return c1 == c2
            rescue
                return false
            end
        end


        # Add files and commit them to the release branch.
        #
        # @param opts [Hash] Options hash
        # @param filelist [Array<String>] List of file paths to add
        # @param commit_path [String, nil] Path to a file containing the commit message
        # @param commit_msg [String, nil] Direct commit message text
        # @raise [MissingArgumentError] If both commit_msg and commit_path are nil
        # @raise [GitMaintainError] If the git commit fails
        def release_do_add_commit(opts, filelist, commit_path, commit_msg=nil)
            edit_flag = ""
            edit_flag = "--edit" if opts[:no_edit] == false

            raise MissingArgumentError.new("commit message/path") if commit_path == nil && commit_msg == nil
            commit_flag=""
            if commit_msg != nil
                commit_flag = "-m '#{commit_msg}'"
            else
                commit_flag = "-F '#{commit_path}'"
            end

            # Add and commit
            begin
                runGit("add  " + filelist.join(" "))
                runGitInteractive("commit #{commit_flag} --verbose #{edit_flag} --signoff")
            rescue RunError
                raise GitMaintainError.new("Failed to commit on branch #{@local_branch}")
            end
        end

        # Create a signed annotated release tag.
        #
        # @param opts [Hash] Options hash
        # @param version [String] The version string/tag name
        # @param tag_path [String] Path to file containing the tag message
        # @raise [GitMaintainError] If tagging fails
        def release_do_tag(opts, version, tag_path)
            edit_flag = ""
            edit_flag = "--edit" if opts[:no_edit] == false
            begin
                runGitInteractive("tag -a -s #{version} #{edit_flag} -F #{tag_path}")
            rescue RunError
                raise GitMaintainError.new("Failed to tag branch #{@local_branch}")
            end
        end

        # Add, commit, and tag files for a release.
        #
        # @param opts [Hash] Options hash
        # @param filelist [Array<String>] List of file paths to add and commit
        # @param version [String] The version string/tag name
        # @param message_path [String] Path to file containing the commit/tag message
        # @raise [GitMaintainError] If committing or tagging fails
        def release_do_add_commit_tag(opts, filelist, version, message_path)
            release_do_add_commit(opts, filelist, message_path)
            release_do_tag(opts, version, message_path)
        end

    end
end
