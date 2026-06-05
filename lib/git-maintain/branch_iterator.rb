# Main module for git-maintain repository maintenance tool.
module GitMaintain

    # Iterator class. List all the branch specific actions and trigger  that action on all relevant branches
    class BranchIterator < Common
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

        # Initialize the BranchIterator instance
        def initialize()
            repo   = Repo::load()
            ci     = CI::load(repo)
        end

        # Define wrappers for all actions, each calling iterateAction
        ACTION_LIST.each do |action|
            define_method(action) do |opts|
                iterateAction(opts, action)
            end
        end

        private
        # Execute the specified action on the selected branch(es).
        # Loads the repo, targets branches, iterates through them, and runs any action epilogue.
        #
        # @param opts [Hash] Options hash
        # @param action [Symbol] Action name to execute
        # @raise [GitMaintainError] If executing the action fails
        def iterateAction(opts, action)
            repo   = Repo::load()
            ci = CI::load(repo)
            opts[:repo] = repo
            opts[:ci] = ci
            brClass = GitMaintain::getExtendedClass(Branch, repo.name)

            if NO_FETCH_ACTIONS.index(action) == nil && opts[:fetch] != false then
                GitMaintain::log(:INFO, "Fetching stable repo")
                repo.stableUpdate(opts[:fetch])
            end

            branches = getBranchList(opts, action, repo, ci)

            if opts[:watch] == false
                # One shot run
                runOnBranches(opts, action, branches)
                GitMaintain::log(:INFO, "Done working on selected branches")
                return
            end

            # Watch style action
            loop do
                # Timestamp on top, 'watch' style
                system("clear; date")

                runOnBranches(opts, action, branches)

                sleep(opts[:watch])
                ci.emptyCache()
            end
            # No need for a log message here, the only exit condition
            # is a Ctr-C that trigger an exception
        end


        # List the branches the iterator should loop on
        # This can either be manually specified, or filtered by user or some specific command
        #
        # @param opts [Hash] Options hash
        # @param action [Symbol] Action name to execute
        # @param repo [Repo] The Repo instance
        # @param ci [CI] The CI instance
        # @return [Array<Branch>] Array of relevant branches
        def getBranchList(opts, action, repo, ci)
            # Direct branch selection
            if opts[:manual_branch] != nil then
                return [ Branch::load(repo, opts[:manual_branch], ci, opts[:br_suff]) ]
            end

            unfilteredList = nil
            if ALL_BRANCHES_ACTIONS.index(action) != nil then
                unfilteredList = repo.getStableBranchList()
            else
                unfilteredList = repo.getBranchList(opts[:br_suff])
            end

            return unfilteredList.map(){|br|
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
        end

        def runOnBranches(opts, action, branches)
            res=[]

            # Iterate concerned on all branches
            branches.each(){|branch|
                if NO_CHECKOUT_ACTIONS.index(action) == nil  then
                    GitMaintain::log(:INFO, "Working on #{branch.verbose_name}")
                    branch.checkout()
                end
                res << branch.send(action, opts)
            }

            # Run epilogue (if it exists)
            # Use the first branch to run it so we have an existing Object
            if branches[0].respond_to?((action.to_s() + "_epilogue").to_sym())
                branches[0].public_send(action.to_s() + "_epilogue", opts, res)
            end
        end
    end
end
