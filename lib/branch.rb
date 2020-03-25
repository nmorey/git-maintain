module GitMaintain

    class CherryPickErrorException < StandardError
        def initialize(str, commit)
            @commit = commit
            super(str)
        end
        attr_reader :commit
    end

    class Branch
        ACTION_LIST = [
            :cp, :steal, :list, :list_stable,
            :merge, :push, :monitor,
            :push_stable, :monitor_stable,
            :release, :reset, :create, :delete
        ]
        NO_FETCH_ACTIONS = [
            :cp, :merge, :monitor, :release, :delete
        ]
        NO_CHECKOUT_ACTIONS = [
            :create, :delete, :list, :list_stable, :push, :monitor, :monitor_stable
        ]
        ALL_BRANCHES_ACTIONS = [
            :create
        ]
        ACTION_HELP = [
            "* cp: Backport commits and eventually push them to github",
            "* create: Create missing local branches from all the stable branches",
            "* delete: Delete all local branches using the suffix",
            "* steal: Steal commit from upstream that fixes commit in the branch or were tagged as stable",
            "* list: List commit present in the branch but not in the stable branch",
            "* list_stable: List commit present in the stable branch but not in the latest associated relase",
            "* merge: Merge branch with suffix specified in -m <suff> into the main branch",
            "* push: Push branches to github for validation",
            "* monitor: Check the CI state of all branches",
            "* push_stable: Push to stable repo",
            "* monitor_stable: Check the CI state of all stable branches",
            "* release: Create new release on all concerned branches",
            "* reset: Reset branch against upstream",
        ]

        def self.load(repo, version, ci, branch_suff)
            repo_name = File.basename(repo.path)
            return GitMaintain::loadClass(Branch, repo_name, repo, version, ci, branch_suff)
        end

        def self.set_opts(action, optsParser, opts)
            opts[:base_ver] = 0
            opts[:version] = []
            opts[:commits] = []
            opts[:do_merge] = false
            opts[:push_force] = false
            opts[:no_ci] = false
            opts[:all] = false
            opts[:check_only] = false
            opts[:fetch] = nil
            opts[:watch] = false
            opts[:delete_remote] = false

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
            when :merge
                optsParser.banner += "-m <suffix>"
                optsParser.on("-m", "--merge [SUFFIX]", "Merge branch with suffix.") {
                    |val| opts[:do_merge] = val}
            when :monitor, :monitor_stable
                optsParser.on("-w", "--watch <PERIOD>", Integer,
                              "Watch and refresh CI status every <PERIOD>.") {
                    |val| opts[:watch] = val}
            when :push
                optsParser.banner += "[-f]"
                optsParser.on("-f", "--force", "Add --force to git push (for 'push' action).") {
                    |val| opts[:push_force] = val}
            when :push_stable
                optsParser.banner += "[-T]"
                optsParser.on("-T", "--no-ci", "Ignore CI build status and push anyway.") {
                    |val| opts[:no_ci] = true}
                optsParser.on("-c", "--check", "Check if there is something to be pushed.") {
                    |val| opts[:check_only] = true}
            when :steal
                optsParser.banner += "[-a]"
                optsParser.on("-a", "--all", "Check all commits from master. "+
                                               "By default only new commits (since last successful run) are considered.") {
                    |val| opts[:all] = true}
            end
        end

        def self.check_opts(opts)
            if opts[:action] == :push_stable ||
               opts[:action] == :release then
                if opts[:br_suff] != "master" then
                    raise "Action #{opts[:action]} can only be done on 'master' suffixed branches"
                end
            end
            if opts[:action] == :delete && opts[:delete_remote] != true then
                if opts[:br_suff] == "master" then
                    raise "Action #{opts[:action]} can NOT be done on 'master' suffixed branches"
                end
            end
            opts[:version] = [ /.*/ ] if opts[:version].length == 0
        end

        def self.execAction(opts, action)
            repo   = Repo::load()
            ci = CI::load(repo)
            opts[:repo] = repo
            opts[:ci] = ci
            brClass = GitMaintain::getClass(self, repo.name)

            if NO_FETCH_ACTIONS.index(action) == nil && opts[:fetch] != false then
                GitMaintain::log(:INFO, "Fetching stable repo")
                repo.stableUpdate(opts[:fetch])
            end

            branchList=[]
            if opts[:manual_branch] == nil then
                unfilteredList = nil
                if ALL_BRANCHES_ACTIONS.index(action) != nil then
                    unfilteredList = repo.getStableBranchList()
                else
                    unfilteredList = repo.getBranchList(opts[:br_suff])
                end
                branchList = unfilteredList.map(){|br|
                    branch = Branch::load(repo, br, ci, opts[:br_suff])
                    case branch.is_targetted?(opts)
                    when :too_old
                        GitMaintain::log(:VERBOSE, "Skipping older v#{branch.version}")
                        next
                    when :no_match
                        GitMaintain::log(:VERBOSE, "Skipping v#{branch.version} not matching" +
                                                   opts[:version].to_s())
                        next
                    end
                    branch
                }.compact()
            else
                branchList = [ Branch::load(repo, opts[:manual_branch], ci, opts[:br_suff]) ]
            end

            loop do
                system("clear; date") if opts[:watch] != false

                res=[]

                # Iterate concerned on all branches
                branchList.each(){|branch|
                    if NO_CHECKOUT_ACTIONS.index(action) == nil  then
                        GitMaintain::log(:INFO, "Working on #{branch.verbose_name}")
                        branch.checkout()
                    end
                    res << branch.send(action, opts)
                }

                # Run epilogue (if it exists)
                begin
                    brClass.send(action.to_s() + "_epilogue", opts, res)
                rescue NoMethodError => e
                end

                break if opts[:watch] == false
                sleep(opts[:watch])
                ci.emptyCache()
            end
        end

        def initialize(repo, version, ci, branch_suff)
            GitMaintain::checkDirectConstructor(self.class)

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

            @head          = @repo.runGit("rev-parse --verify --quiet #{@local_branch}")
            @remote_ref    = "#{@repo.stable_repo}/#{@remote_branch}"
            @stable_head   = @repo.runGit("rev-parse --verify --quiet #{@remote_ref}")
            case @branch_type
            when :std
                @stable_base   = @repo.findStableBase(@local_branch)
            when :user_specified
                @stable_base   = @remote_ref
            end
        end
        attr_reader :version, :local_branch, :head, :remote_branch, :remote_ref, :stable_head,
                    :verbose_name, :exists, :stable_base

        def log(lvl, str)
            GitMaintain::log(lvl, str)
        end

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

        # Checkout the repo to the given branch
        def checkout()
            print @repo.runGit("checkout -q #{@local_branch}")
            if $? != 0 then
                raise "Error: Failed to checkout the branch"
            end
        end

        # Cherry pick an array of commits
        def cp(opts)
            opts[:commits].each(){|commit|
                prev_head=@repo.runGit("rev-parse HEAD")
                log(:INFO, "Applying #{@repo.getCommitHeadline(commit)}")
                @repo.runGitInteractive("cherry-pick #{commit}")
                if $? != 0 then
                    log(:WARNING, "Cherry pick failure. Starting bash for manual fixes. Exit shell to continue")
			        @repo.runBash()
		        end
                new_head=@repo.runGit("rev-parse HEAD")
                # Do not make commit pretty if it was not applied
                if new_head != prev_head
		            make_pretty(commit)
                end
            }
        end

        # Steal upstream commits that are not in the branch
        def steal(opts)
            base_ref=@stable_base

            # If we are not force checking everything,
            # try to start from the last tag we steal upto
            if opts[:all] != true then
                sha = @repo.runGit("rev-parse 'git-maintain/steal/last/#{@stable_base}' 2>&1")
                if $? == 0 then
                    base_ref=sha
                    log(:VERBOSE, "Starting from last successfull run:")
                    log(:VERBOSE, @repo.getCommitHeadline(base_ref))
                end
            end

            master_sha=@repo.runGit("rev-parse origin/master")
            res = steal_all(opts, "#{base_ref}..#{master_sha}", true)

            # If we picked all the commits (or nothing happened)
            # Mark the current master as the last checked point so we
            # can just steal from this point on the next run
            if res == true then
                @repo.runGit("tag -f 'git-maintain/steal/last/#{@stable_base}' origin/master")
                log(:VERBOSE, "Marking new last successfull run at:")
                log(:VERBOSE, @repo.getCommitHeadline(master_sha))
            end
        end

        # List commits in the branch that are no in the stable branch
        def list(opts)
            GitMaintain::log(:INFO, "Working on #{@verbose_name}")
            GitMaintain::showLog(opts, @local_branch, @remote_ref)
        end

        # List commits in the stable_branch that are no in the latest release
        def list_stable(opts)
            GitMaintain::log(:INFO, "Working on #{@verbose_name}")
            GitMaintain::showLog(opts, @remote_ref, @repo.runGit("describe --abbrev=0 #{@local_branch}"))
        end

        # Merge merge_branch into this one
        def merge(opts)
            merge_branch = @repo.versionToLocalBranch(@version, opts[:do_merge])

            # Make sure branch exists
            hash_to_merge = @repo.runGit("rev-parse --verify --quiet #{merge_branch}")
            if $? != 0 then
                log(:INFO, "Branch #{merge_branch} does not exists. Skipping...")
                return
            end

            # See if there is anything worth merging
            merge_base_hash = @repo.runGit("merge-base #{merge_branch} #{@local_branch}")
            if merge_base_hash == hash_to_merge then
                log(:INFO, "Branch #{merge_branch} has no commit that needs to be merged")
                return
            end

            rep = GitMaintain::checkLog(opts, merge_branch, @local_branch, "merge")
            if rep == "y" then
                @repo.runGitInteractive("merge #{merge_branch}")
                if $? != 0 then
                    log(:WARNING, "Merge failure. Starting bash for manual fixes. Exit shell to continue")
			        @repo.runBash()
		        end
            else
                log(:INFO, "Skipping merge")
                return
            end 
        end

        # Push the branch to the validation repo
        def push(opts)
            if same_sha?(@local_branch, @repo.valid_repo + "/" + @local_branch) ||
               same_sha?(@local_branch, @remote_ref) then
                log(:INFO, "Nothing to push on #{@local_branch}")
                return
            end
            return "#{@local_branch}:#{@local_branch}"
        end

        def self.push_epilogue(opts, branches)
            # Compact to remove empty entries
            branches.compact!()

            return if branches.length == 0

            opts[:repo].runGit("push #{opts[:push_force] == true ? "-f" : ""} "+
                               "#{opts[:repo].valid_repo} #{branches.join(" ")}")
        end

        # Monitor the build status on CI
        def monitor(opts)
            st = @ci.getValidState(self, @head)
            suff=""
            case st
            when "started"
                suff= " started at #{@ci.getValidTS(self, @head)}"
            end
            log(:INFO, "Status for v#{@version}: " + st + suff)
            if @ci.isErrored(self, st) && opts[:watch] == false
                rep = "y"
                suff=""
                while rep == "y"
                    rep = GitMaintain::confirm(opts, "see the build log#{suff}")
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

        # Push branch to the stable repo
        def push_stable(opts)
            if (opts[:no_ci] != true && @NO_CI != true) &&
               @ci.checkValidState(self, @head) != true then
                log(:WARNING, "Build is not passed on CI. Skipping push to stable")
                return
            end

            if same_sha?(@local_branch, @remote_ref) then
                log(:INFO, "Stable is already up-to-date")
                return
            end

            if opts[:check_only] == true then
                GitMaintain::checkLog(opts, @local_branch, @remote_ref, "")
                return
            end

            rep = GitMaintain::checkLog(opts, @local_branch, @remote_ref, "submit")
            if rep == "y" then
                return "#{@local_branch}:#{@remote_branch}"
            else
                log(:INFO, "Skipping push to stable")
                return
            end
        end


        def self.push_stable_epilogue(opts, branches)
            # Compact to remove empty entries
            branches.compact!()

            return if branches.length == 0
            opts[:repo].runGit("push #{opts[:repo].stable_repo} #{branches.join(" ")}")
        end
         # Monitor the build status of the stable branch on CI
        def monitor_stable(opts)
            st = @ci.getStableState(self, @stable_head)
            suff=""
            case st
            when "started"
                suff= " started at #{@ci.getStableTS(self, @stable_head)}"
            end
            log(:INFO, "Status for v#{@version}: " + st + suff)
        end

        # Reset the branch to the upstream stable one
        def reset(opts)
            if same_sha?(@local_branch, @remote_ref) then
                log(:INFO, "Nothing to reset")
                return
            end

            rep = GitMaintain::checkLog(opts, @local_branch, @remote_ref, "reset")
            if rep == "y" then
                @repo.runGit("reset --hard #{@remote_ref}")
            else
                log(:INFO, "Skipping reset")
                return
            end
        end

        def release(opts)
            log(:ERROR,"#No release command available for this repo")
        end

        def create(opts)
            return if @head != ""
            log(:INFO, "Creating missing #{@local_branch} from #{@remote_ref}")
            @repo.runGit("branch #{@local_branch} #{@remote_ref}")
        end

        def delete(opts)
            if opts[:delete_remote] == true then
                @repo.runGit("rev-parse --verify --quiet #{@repo.valid_repo}/#{@local_branch}")
                if $? != 0 then
                    log(:DEBUG, "Skipping non existing remote braqnch #{@local_branch}.")
                    return
                end
                msg = "delete remote branch #{@repo.valid_repo}/#{@local_branch}"
            else
                msg = "delete branch #{@local_branch}"
            end
            rep = GitMaintain::confirm(opts, msg)
            if rep == "y" then
                return @local_branch
            else
                log(:INFO, "Skipping deletion")
                return
            end
        end
        def self.delete_epilogue(opts, branches)
            # Compact to remove empty entries
            branches.compact!()

            return if branches.length == 0
            puts "Deleting #{opts[:delete_remote] == true ? "remote" : "local"} branches: #{branches.join(" ")}"
            rep = GitMaintain::confirm(opts, "continue")
            if rep != "y" then
                log(:INFO, "Cancelling")
                return
            end
            if opts[:delete_remote] == true then
                opts[:repo].runGit("push #{opts[:repo].valid_repo} #{branches.map(){|x| ":" + x}.join(" ")}")
            else
                opts[:repo].runGit("branch -D  #{branches.join(" ")}")
            end
        end

        private
        def add_blacklist(commit)
  	        @repo.runGit("notes append -m \"#{@local_branch}\" #{commit}")
        end

        def is_blacklisted?(commit)
            @repo.runGit("notes show #{commit} 2> /dev/null").split("\n").each(){|br|
                return true if br == @local_branch
            }
            return false
        end

        def make_pretty(orig_commit, commit="")
            orig_sha=@repo.runGit("rev-parse #{orig_commit}")
            msg_commit = (commit.to_s() == "") ? orig_sha : commit

            msg_path=`mktemp`.chomp()
            msg_file = File.open(msg_path, "w+")
	        msg_file.puts @repo.runGit("log -1 --format=\"%s%n%n[ Upstream commit #{msg_commit} ]%n%n%b\" #{orig_commit}")
            msg_file.close()
	        @repo.runGit("commit -s --amend -F #{msg_path}")
            `rm -f #{msg_path}`
        end

        def is_in_tree?(commit, src_commit=commit)
	        fullhash=@repo.runGit("rev-parse --verify --quiet #{commit}")
	        # This might happen if someone pointed to a commit that doesn't exist in our
	        # tree.
	        if $? != 0 then
                log(:WARNING, "Commit #{src_commit} points to a SHA #{commit} not in tree")
		        return false
	        end

	        # Hope for the best, same commit is/isn't in the current branch
	        if @repo.runGit("merge-base #{fullhash} HEAD") == fullhash then
		        return true
	        end

	        # Grab the subject, since commit sha1 is different between branches we
	        # have to look it up based on subject.
	        subj=@repo.getCommitSubj(commit)
	        if $? != 0 then
		        return false
	        end

	        # Try and find if there's a commit with given subject the hard way
	        @repo.runGit("log --pretty=\"%H\" -F --grep \"#{subj.gsub("\"", '\\"')}\" "+
                         "#{@stable_base}..HEAD").split("\n").each(){|cmt|
                cursubj=@repo.runGit("log -1 --format=\"%s\" #{cmt}")
                if cursubj = subj then
	                return true
		        end
	        }
	        return false
        end

        def is_relevant?(commit)
	        # Let's grab the commit that this commit fixes (if exists (based on the "Fixes:" tag)).
	        fixescmt=@repo.runGit("log -1 #{commit} | grep -i \"fixes:\" | head -n 1 | "+
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

	        if @repo.runGit("show #{commit} | grep -i 'stable@' | wc -l") == "0" then
		        return false
	        end

	        # Let's see if there's a version tag in this commit
	        full=@repo.runGit("show #{commit} | grep -i 'stable@'").gsub(/.* #?/, "")

	        # Sanity check our extraction
            if full =~ /stable/ then
                return false
            end

            full = @repo.runGit("rev-parse #{full}^{commit}")

	        # Make sure our branch contains this version
	        if @repo.runGit("merge-base #{@head} #{full}") == full then
		        return true
	        end

	        # Tag is not in history, ignore
	        return false
        end

        def pick_one(commit)
            @repo.runGitInteractive("cherry-pick --strategy=recursive -Xpatience -x #{commit} &> /dev/null")
	        return if  $? == 0
            if @repo.runGit("status -uno --porcelain | wc -l") == "0" then
			    @repo.runGit("reset --hard")
                raise CherryPickErrorException.new("Failed to cherry pick commit #{commit}", commit)
		    end
		    @repo.runGit("reset --hard")
		    # That didn't work? Let's try that with every variation of the commit
		    # in other stable trees.
            @repo.find_alts(commit).each(){|alt_commit|
			    @repo.runGitInteractive("cherry-pick --strategy=recursive -Xpatience -x #{alt_commit} &> /dev/null")
			    if $? == 0 then
				    return
			    end
			    @repo.runGit("reset --hard")
            }
		    # Still no? Let's go back to the original commit and hand it off to
		    # the user.
		    @repo.runGitInteractive("cherry-pick --strategy=recursive -Xpatience -x #{commit} &> /dev/null")
            raise CherryPickErrorException.new("Failed to cherry pick commit #{commit}", commit)
	        return false
        end

        def confirm_one(opts, commit)
 		    rep=""
		    do_cp=false
		    puts @repo.getCommitHeadline(commit)
		    while rep != "y" do
			    puts "Do you want to steal this commit ? (y/n/b/?)"
                if opts[:no] == true then
                    log(:INFO, "Auto-replying no due to --no option")
                    rep = 'n'
                    break
                else
                    rep = STDIN.gets.chomp()
                end
			    case rep
				when "n"
			        log(:INFO, "Skip this commit")
					break
				when "b"
					log(:INFO, "Blacklisting this commit for the current branch")
					add_blacklist(commit)
					break
				when "y"
					rep="y"
					do_cp=true
					break
				when "?"
					puts @repo.runGit("show #{commit}")
                else
					log(:ERROR, "Invalid answer $rep")
		            puts @repo.runGit("show --format=oneline --no-patch --no-decorate #{commit}")
                end
		    end
            return do_cp
        end

        def steal_one(opts, commit, mainline=false)
		    msg=''
            orig_cmt=commit

            if mainline == false then
		        subj=@repo.getCommitSubj(commit)
                subj.gsub!(/"/, '\"')
		        # Let's grab the mainline commit id, this is useful if the version tag
		        # doesn't exist in the commit we're looking at but exists upstream.
		        orig_cmt=@repo.runGit("log --no-merges --format=\"%H\" -F --grep \"#{subj}\" " +
                                      "#{@stable_base}..origin/master | tail -n1")

                if orig_cmt == "" then
                    log(:WARNING, "Could not find commit #{commit} in mainline")
                end
            end
            # If the commit doesn't apply for us, skip it
		    if is_relevant?(orig_cmt) != true
                return true
		    end

            log(:VERBOSE, "Found relevant commit #{@repo.getCommitHeadline(commit)}")
		    if is_in_tree?(orig_cmt) == true
		        # Commit is already in the stable branch, skip
                log(:VERBOSE, "Commit is already in tree")
                return true
		    end

		    # Check if it's not blacklisted by a git-notes
		    if is_blacklisted?(orig_cmt) == true then
		        # Commit is blacklisted
			    log(:INFO, "Skipping 'blacklisted' commit " +
                     @repo.getCommitHeadline(orig_cmt))
                return true
		    end

            do_cp = confirm_one(opts, orig_cmt)
            return false if do_cp != true

            prev_head=@repo.runGit("rev-parse HEAD")

            begin
		        pick_one(commit)
            rescue CherryPickErrorException => e
			    log(:WARNING, "Cherry pick failed. Fix, commit (or reset) and exit.")
			    @repo.runSystem("/bin/bash")
            end
            new_head=@repo.runGit("rev-parse HEAD")

		    # If we didn't find the commit upstream then this must be a custom commit
		    # in the given tree - make sure the user checks this commit.
		    if orig_cmt == "" then
			    msg="Custom"
			    orig_cmt=@repo.runGit("rev-parse HEAD")
			    log(:WARNING, "Custom commit, please double-check!")
			    @repo.runSystem("/bin/bash")
		    end
            if new_head != prev_head
		        make_pretty(orig_cmt, msg)
            end
        end

        def steal_all(opts, range, mainline = false)
            res = true
 	        @repo.runGit("log --no-merges --format=\"%H\" #{range} | tac").split("\n").each(){|commit|
                res &= steal_one(opts, commit, mainline)
            }
            return res
       end

        def same_sha?(ref1, ref2)
            c1=@repo.runGit("rev-parse --verify --quiet #{ref1}")
            c2=@repo.runGit("rev-parse --verify --quiet #{ref2}")
            return c1 == c2

        end
    end
end
