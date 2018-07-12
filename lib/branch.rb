module Backport
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

        def self.check_opts(opts)
            if opts[:action] == :push_stable ||
               opts[:action] == :release then
                if opts[:br_suff] != "master" then
                    raise "Action #{opts[:action]} can only be done on 'master' suffixed branches"
                end
            end
        end

        def self.execAction(opts, action)
            repo   = Repo.new()
            travis = TravisChecker.new(repo)

            if NO_FETCH_ACTIONS.index(action) == nil  then
                repo.stableUpdate()
            end

            repo.getStableList(opts[:br_suff]).each(){|br|
                branch = Branch.new(repo, br, travis, opts[:br_suff])
                case branch.is_targetted?(opts)
                when :too_old
                    puts "Skipping older v#{branch.version}"
                    next
                when :no_match
                    puts "Skipping v#{branch.version} not matching #{opts[:version].to_s()}"
                    next
                end

                puts "############################"
                puts "Working on v#{branch.version}"
                puts "############################"

                if NO_CHECKOUT_ACTIONS.index(action) == nil  then
                    branch.checkout()
                end
                branch.send(action, opts)
            }
        end

        def initialize(repo, version, travis, branch_suff)
            @repo          = repo
            @version       = version
            @travis        = travis
            @branch_suff   = branch_suff

            @local_branch  = "dev/stable-v#{@version}/#{@branch_suff}"
            @head          = @repo.runGit("rev-parse #{@local_branch}")

            @remote_branch ="stable-v#{@version}"
            @remote_ref    = "#{Repo::STABLE_REPO}/#{@remote_branch}"
            @stable_head   = @repo.runGit("rev-parse #{@remote_ref}")
        end
        attr_reader :version, :local_branch, :head, :remote_branch, :remote_ref, :stable_head

        def is_targetted?(opts)
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
        def cherry_pick(opts)
            if opts[:commits].length > 0 then
                @repo.runGit("cherry-pick #{opts[:commits].join(" ")}")
                if $? != 0 then
                    puts "Cherry pick failure. Starting bash for manual fixes. Exit shell to continue"
			        @repo.runSystem("bash")
                    puts "Continuing..."
		        end
            end
        end

        # Steal upstream commits that are not in the branch
        def steal(opts)
            @repo.runSystem("git steal-commits")
        end

        # List commits in the branch that are no in the stable branch
        def list(opts)
         Backport::checkLog(opts, @local_branch, @remote_ref, nil)
        end

        # Merge merge_branch into this one
        def merge(opts)
            merge_branch = "dev/stable-v#{@version}/#{opts[:do_merge]}"
            rep = Backport::checkLog(opts, merge_branch, @local_branch, "merge")
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
           @repo.runGit("push #{opts[:push_force] == true ? "-f" : ""} #{Repo::VALID_REPO} #{@local_branch}")
        end

        # Monitor the build status on Travis
        def monitor(opts)
            st = @travis.getValidState(head)
            puts "Status for v#{@version}: " + st
            if st == "failed"
                rep = "y"
                suff=""
                while rep == "y"
                    rep = Backport::confirm(opts, "see the build log#{suff}")
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
            if @travis.checkValidState(@head) != true then
                puts "Build is not passed on travis. Skipping push to stable"
                return
            end
            rep = Backport::checkLog(opts, @local_branch, @remote_ref, "submit")
            if rep == "y" then
                @repo.runGit("push #{Repo::STABLE_REPO} #{@local_branch}:#{@remote_branch}")
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
            rep = Backport::checkLog(opts @local_branch, @remote_ref, "reset")
            if rep == "y" then
                @repo.runGit("reset --hard #{@remote_ref}")
            else
                puts "Skipping reset"
                return
            end
        end

        def release(opts)
            prev_ver=@repo.runGit("show HEAD:CMakeLists.txt  | egrep \"[sS][eE][tT]\\\\(PACKAGE_VERSION\"").
                         chomp().gsub(/[sS][eE][tT]\(PACKAGE_VERSION\s*"([0-9.]*)".*$/, '\1')
            ver_nums = prev_ver.split(".")
            new_ver =  (ver_nums[0 .. -2] + [ver_nums[-1].to_i() + 1 ]).join(".")
            git_prev_ver = "v" + (ver_nums[-1] == "0" ? ver_nums[0 .. -2].join(".") : prev_ver)

            puts "Preparing release #{prev_ver} => #{new_ver}"
            rep = Backport::checkLog(opts, @local_branch, git_prev_ver, "release")
            if rep != "y" then
                puts "Skipping release"
                return
            end

            # Prepare tag message
            tag_path=`mktemp`.chomp()
            puts tag_path
            tag_file = File.open(tag_path, "w+")
            tag_file.puts "rdma-core-#{new_ver}:"
            tag_file.puts ""
            tag_file.puts "Updates from version #{prev_ver}"
            tag_file.puts " * Backport fixes:"
            tag_file.puts `git log HEAD ^#{git_prev_ver} --format='   * %s'`
            tag_file.close()

            # Update version number in relevant files
            @repo.run("sed -i -e 's/\\(Version:[[:space:]]*\\)[0-9.]*/\\1#{new_ver}/g' redhat/rdma-core.spec suse/rdma-core.spec")
            @repo.run("sed -i -e 's/\\([sS][eE][tT](PACKAGE_VERSION[[:space:]]*\"\\)[0-9.]*\"/\\1#{new_ver}\"/g' CMakeLists.txt")

            @repo.run("cat <<EOF > debian/changelog.new
rdma-core (#{new_ver}-1) unstable; urgency=low

  * New upstream release.

 -- $(git config user.name) <$(git config user.email)>  $(date '+%a, %d %b %Y %T %z')

$(cat debian/changelog)
EOF
mv debian/changelog.new debian/changelog")

            # Add and commit
            @repo.runGit("add  redhat/rdma-core.spec suse/rdma-core.spec CMakeLists.txt debian/changelog")
            @repo.runGit("commit -m 'Bump to version #{new_ver}' --verbose --edit --signoff")
            if $? != 0 then
                raise("Failed to commit on branch #{local_branch}")
            end
            @repo.runGit("tag -a -s v#{new_ver} --edit -F #{tag_path}")
            if $? != 0 then
                raise("Failed to tag branch #{local_branch}")
            end
            `rm -f #{tag_path}`
        end
    end
end
