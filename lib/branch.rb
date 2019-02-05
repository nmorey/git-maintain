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
            :cp, :steal, :list, :merge,
            :push, :monitor,
            :push_stable, :monitor_stable,
            :release, :reset
        ]
        NO_FETCH_ACTIONS = [
            :cp, :merge, :monitor, :release
        ]
        NO_CHECKOUT_ACTIONS = [
            :list, :push, :monitor, :monitor_stable
        ]
        ACTION_HELP = [
            "* cp: Backport commits and eventually push them to github",
            "* steal: Steal commit from upstream that fixes commit in the branch or were tagged as stable",
            "* list: List commit present in the branch but not in the stable branch",
            "* merge: Merge branch with suffix specified in -m <suff> into the main branch",
            "* push: Push branches to github for validation",
            "* monitor: Check the travis state of all branches",
            "* push_stable: Push to stable repo",
            "* monitor_stable: Check the travis state of all stable branches",
            "* release: Create new release on all concerned branches",
            "* reset: Reset branch against upstream",
        ]

        def self.load(repo, version, travis, branch_suff)
            repo_name = File.basename(repo.path)
            return GitMaintain::loadClass(Branch, repo_name, repo, version, travis, branch_suff)
        end

        def self.set_opts(action, optsParser, opts)
            opts[:base_ver] = 0
            opts[:version] = /.*/
            opts[:commits] = []
            opts[:do_merge] = false
            opts[:push_force] = false
            opts[:no_travis] = false

            optsParser.on("-v", "--base-version [MIN_VER]", Integer, "Older release to consider.") {
                |val| opts[:base_ver] = val}
            optsParser.on("-V", "--version [regexp]", Regexp, "Regexp to filter versions.") {
                |val| opts[:version] = val}

            if action != :merge
                optsParser.on("-B", "--manual-branch <branch name>", "Work on a specific (non-stable) branch.") {
                    |val| opts[:manual_branch] = val}
            end
            case action
            when :cp
                optsParser.banner += "-c <sha1> [-c <sha1> ...]"
                optsParser.on("-c", "--sha1 [SHA1]", String, "Commit to cherry-pick. Can be used multiple time.") {
                    |val| opts[:commits] << val}
            when :merge
                optsParser.banner += "-m <suffix>"
                optsParser.on("-m", "--merge [SUFFIX]", "Merge branch with suffix.") {
                    |val| opts[:do_merge] = val}
            when :push
                optsParser.banner += "[-f]"
                optsParser.on("-f", "--force", "Add --force to git push (for 'push' action).") {
                    |val| opts[:push_force] = val}
            when :push_stable
                optsParser.banner += "[-T]"
                optsParser.on("-T", "--no-travis", "Ignore Travis build status and push anyway.") {
                    |val| opts[:no_travis] = true}
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
        end

        def self.execAction(opts, action)
            repo   = Repo::load()
            travis = TravisChecker::load(repo)

            if NO_FETCH_ACTIONS.index(action) == nil  then
                repo.stableUpdate()
            end

            branchList=[]
            if opts[:manual_branch] == nil then
                branchList = repo.getStableList(opts[:br_suff]).map(){|br|
                    branch = Branch::load(repo, br, travis, opts[:br_suff])
                    case branch.is_targetted?(opts)
                    when :too_old
                        puts "# Skipping older v#{branch.version}"
                        next
                    when :no_match
                        puts "# Skipping v#{branch.version} not matching #{opts[:version].to_s()}"
                        next
                    end
                    branch
                }.compact()
            else
                branchList = [ Branch::load(repo, opts[:manual_branch], travis, opts[:br_suff]) ]
            end
            branchList.each(){|branch|
                puts "###############################"
                puts "# Working on #{branch.verbose_name}"
                puts "###############################"

                if NO_CHECKOUT_ACTIONS.index(action) == nil  then
                    branch.checkout()
                end
                branch.send(action, opts)
            }
        end

        def initialize(repo, version, travis, branch_suff)
            GitMaintain::checkDirectConstructor(self.class)

            @repo          = repo
            @travis        = travis
            @version       = version
            @branch_suff   = branch_suff

            if version =~ /^[0-9]+$/
                @local_branch  = "dev/stable-v#{@version}/#{@branch_suff}"
                @remote_branch ="stable-v#{@version}"
                @branch_type = :std
                @verbose_name = "v"+version
            else
                @remote_branch = @local_branch = version
                @branch_type = :user_specified
                @verbose_name = version
            end

            @head          = @repo.runGit("rev-parse #{@local_branch}")
            @remote_ref    = "#{@repo.stable_repo}/#{@remote_branch}"
            @stable_head   = @repo.runGit("rev-parse #{@remote_ref}")
            @stable_base   = @repo.findStableBase(@local_branch)

        end
        attr_reader :version, :local_branch, :head, :remote_branch, :remote_ref, :stable_head, :verbose_name

        def is_targetted?(opts)
            return true if @branch_type == :user_specified
            if @version.to_i < opts[:base_ver] then
                return :too_old
            end
            if @version !~ opts[:version] then
                return :no_match
            end
            return true
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
                @repo.runGit("cherry-pick #{commit}")
                if $? != 0 then
                    puts "Cherry pick failure. Starting bash for manual fixes. Exit shell to continue"
			        @repo.runSystem("bash")
                    puts "Continuing..."
		        end
		        make_pretty(commit)
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
                    puts "# INFO: Starting from last successfull run:"
                    puts "# INFO: " + @repo.runGit("show --format=oneline #{base_ref}")
                end
            end

            master_sha=@repo.runGit("rev-parse origin/master")
            res = steal_all(opts, "#{base_ref}..#{master_sha}")

            # If we picked all the commits (or nothing happened)
            # Mark the current master as the last checked point so we
            # can just steal from this point on the next run
            if res == true then
                @repo.runGit("tag -f 'git-maintain/steal/last/#{@stable_base}' origin/master")
                puts "# INFO: Marking new last successfull run at:"
                puts "# INFO: " + @repo.runGit("show --format=oneline #{master_sha}")
         end
        end

        # List commits in the branch that are no in the stable branch
        def list(opts)
         GitMaintain::checkLog(opts, @local_branch, @remote_ref, nil)
        end

        # Merge merge_branch into this one
        def merge(opts)
            merge_branch = "dev/stable-v#{@version}/#{opts[:do_merge]}"
            rep = GitMaintain::checkLog(opts, merge_branch, @local_branch, "merge")
            if rep == "y" then
                @repo.runGit("merge #{merge_branch}")
                if $? != 0 then
                    puts "Merge failure. Starting bash for manual fixes. Exit shell to continue"
			        @repo.runSystem("bash")
                    puts "Continuing..."
		        end
            else
                puts "Skipping merge"
                return
            end 
        end

        # Push the branch to the validation repo
        def push(opts)
           @repo.runGit("push #{opts[:push_force] == true ? "-f" : ""} #{@repo.valid_repo} #{@local_branch}")
        end

        # Monitor the build status on Travis
        def monitor(opts)
            st = @travis.getValidState(head)
            puts "Status for v#{@version}: " + st
            if st == "failed"
                rep = "y"
                suff=""
                while rep == "y"
                    rep = GitMaintain::confirm(opts, "see the build log#{suff}")
                    if rep == "y" then
                        log = @travis.getValidLog(head)
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
            if (opts[:no_travis] != true && @NO_TRAVIS != true) &&
               @travis.checkValidState(@head) != true then
                puts "Build is not passed on travis. Skipping push to stable"
                return
            end
            rep = GitMaintain::checkLog(opts, @local_branch, @remote_ref, "submit")
            if rep == "y" then
                @repo.runGit("push #{@repo.stable_repo} #{@local_branch}:#{@remote_branch}")
            else
                puts "Skipping push to stable"
                return
            end
        end

         # Monitor the build status of the stable branch on Travis
        def monitor_stable(opts)
            puts "Status for v#{@version}: " + @travis.getStableState(@stable_head)
        end

        # Reset the branch to the upstream stable one
        def reset(opts)
            rep = GitMaintain::checkLog(opts, @local_branch, @remote_ref, "reset")
            if rep == "y" then
                @repo.runGit("reset --hard #{@remote_ref}")
            else
                puts "Skipping reset"
                return
            end
        end

        def release(opts)
            puts "#No release command available for this repo"
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
                puts "# WARNING: Commit #{src_commit} points to a SHA #{commit} not in tree"
		        return false
	        end

	        # Hope for the best, same commit is/isn't in the current branch
	        if @repo.runGit("merge-base #{fullhash} HEAD") == fullhash then
		        return true
	        end

	        # Grab the subject, since commit sha1 is different between branches we
	        # have to look it up based on subject.
	        subj=@repo.runGit("log -1 --pretty=\"%s\" #{commit}")
	        if $? != 0 then
		        return false
	        end

	        # Try and find if there's a commit with given subject the hard way
	        @repo.runGit("log --pretty=\"%H\" -F --grep \"#{subj}\" "+
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
	        full=@repo.runGit("show #{commit} | grep -i 'stable@'").gsub(/.* /, "")

	        # Sanity check our extraction
            if full =~ /stable/ then
                return false
            end

	        # Make sure our branch contains this version
	        if @repo.runGit("merge-base #{@head} #{full}") == full then
		        return true
	        end

	        # Tag is not in history, ignore
	        return false
        end

        def pick_one(commit)
            @repo.runGit("cherry-pick --strategy=recursive -Xpatience -x #{commit} &> /dev/null")
	        return if  $? == 0

		    if [ @repo.runGit("status -uno --porcelain | wc -l") != 0 ]; then
			    @repo.runGit("reset --hard")
			    return
		    end
		    @repo.runGit("reset --hard")
		    # That didn't work? Let's try that with every variation of the commit
		    # in other stable trees.
            find_alts(commit).each(){|alt_commit|
			    @repo.runCmd("cherry-pick --strategy=recursive -Xpatience -x #{alt_commit} &> /dev/null")
			    if $? == 0 then
				    return
			    end
			    @repo.runCmd("reset --hard")
            }
		    # Still no? Let's go back to the original commit and hand it off to
		    # the user.
		    @repo.runCmd("cherry-pick --strategy=recursive -Xpatience -x #{commit} &> /dev/null")
            raise CherryPickErrorException.new("Failed to cherry pick commit #{commit}", commit)
	        return false
        end

        def confirm_one(opts, commit)
 		    rep=""
		    do_cp=false
		    puts @repo.runGit("show --format=oneline --no-patch --no-decorate #{commit}")
		    while rep != "y" do
			    puts "Do you want to steal this commit ? (y/n/b/?)"
                if opts[:no] == true then
                    puts "Auto-replying no due to --no option"
                    rep = 'n'
                    break
                else
                    rep = STDIN.gets.chomp()
                end
			    case rep
				when "n"
			        puts "Skip this commit"
					break
				when "b"
					puts "Blacklisting this commit for the current branch"
					add_blacklist(commit)
					break
				when "y"
					rep="y"
					do_cp=true
					break
				when "?"
					puts @repo.runGit("show #{commit}")
                else
					STDERR.puts "Invalid answer $rep"
		            puts @repo.runGit("show --format=oneline --no-patch --no-decorate #{commit}")
                end
		    end
            return do_cp
        end

        def steal_one(opts, commit)
		    subj=@repo.runGit("log -1 --format=\"%s\" #{commit}")
            subj.gsub!(/"/, '\"')
		    msg=''

		    # Let's grab the mainline commit id, this is useful if the version tag
		    # doesn't exist in the commit we're looking at but exists upstream.
		    orig_cmt=@repo.runGit("log --no-merges --format=\"%H\" -F --grep \"#{subj}\" " +
            "#{@stable_base}..origin/master | tail -n1")

		    # If the commit doesn't apply for us, skip it
		    if is_relevant?(orig_cmt) != true
                return true
		    end

		    if is_in_tree?(orig_cmt) == true
		        # Commit is already in the stable branch, skip
                return true
		    end

		    # Check if it's not blacklisted by a git-notes
		    if is_blacklisted?(orig_cmt) == true then
		        # Commit is blacklisted
			    puts "Skipping 'blacklisted' commit " +
                     @repo.runGit("show --format=oneline --no-patch --no-decorate #{orig_cmt}")
                return true
		    end

            do_cp = confirm_one(opts, orig_cmt)
            return false if do_cp != true

            begin
		        pick_one(commit)
            rescue CherryPickErrorException => e
			    puts "Cherry pick failed. Fix, commit (or reset) and exit."
			    @repo.runSystem("/bin/bash")
                return false
            end

		    # If we didn't find the commit upstream then this must be a custom commit
		    # in the given tree - make sure the user checks this commit.
		    if orig_cmt == "" then
			    msg="Custom"
			    orig_cmt=@repo.runGit("rev-parse HEAD")
			    puts "Custom commit, please double-check!"
			    @repo.runSystem("/bin/bash")
		    end
		    make_pretty(orig_cmt, msg)
        end

        def steal_all(opts, range)
            res = true
 	        @repo.runGit("log --no-merges --format=\"%H\" #{range} | tac").split("\n").each(){|commit|
                res &= steal_one(opts, commit)
            }
            return res
       end
    end
end
