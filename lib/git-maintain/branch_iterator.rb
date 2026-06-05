# Main module for git-maintain repository maintenance tool.
module GitMaintain

    # Iterator class. List all the branch specific actions and trigger  that action on all relevant branches
    class BranchIterator < Common

        EXTENDED_CLASS = GitMaintain::getExtendedClass(Branch)

        # List of all available maintenance actions.
        [:ACTION_LIST, :NO_FETCH_ACTIONS, :NO_CHECKOUT_ACTIONS,
         :ALL_BRANCHES_ACTIONS, :ACTION_HELP].each() do |field|
            const_set(field, EXTENDED_CLASS.const_get(field))
        end


        # Configure action-specific command line options.
        #
        # @param action [Symbol] Selected action name
        # @param optsParser [OptionParser] The OptionParser instance to configure
        # @param opts [Hash] The options hash to populate
        def self.set_opts(action, optsParser, opts)
            Branch.set_opts(action, optsParser, opts)
            if EXTENDED_CLASS != Branch && EXTENDED_CLASS.respond_to?(:set_opts)
                EXTENDED_CLASS.set_opts(action, optsParser, opts)
            end
        end

        # Sanity check and normalize the parsed options for the given action.
        #
        # @param opts [Hash] Options hash to validate and configure
        # @raise [InvalidArgumentError] If options are invalid or conflicting
        def self.check_opts(opts)
            Branch.check_opts(opts)
            if EXTENDED_CLASS != Branch && EXTENDED_CLASS.respond_to?(:check_opts)
                EXTENDED_CLASS.check_opts(opts)
            end
        end

        # Initialize the BranchIterator instance
        def initialize()
            @repo   = Repo::load()
            @ci     = CI::load(@repo)
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
            opts[:repo] = @repo
            opts[:ci] = @ci

            if NO_FETCH_ACTIONS.index(action) == nil && opts[:fetch] != false then
                log(:INFO, "Fetching stable repo")
                @repo.stableUpdate(opts[:fetch])
            end

            branches = getBranchList(opts, action)

            if opts[:watch] == false
                # One shot run
                runOnBranches(opts, action, branches)
                log(:INFO, "Done working on selected branches")
                return
            end

            # Watch style action
            loop do
                # Timestamp on top, 'watch' style
                system("clear; date")

                runOnBranches(opts, action, branches)

                sleep(opts[:watch])
                @ci.emptyCache()
            end
            # No need for a log message here, the only exit condition
            # is a Ctr-C that trigger an exception
        end


        # List the branches the iterator should loop on
        # This can either be manually specified, or filtered by user or some specific command
        #
        # @param opts [Hash] Options hash
        # @param action [Symbol] Action name to execute
        # @return [Array<Branch>] Array of relevant branches
        def getBranchList(opts, action)
            # Direct branch selection
            if opts[:manual_branch] != nil then
                return [ Branch::load(@repo, opts[:manual_branch], @ci, opts[:br_suff]) ]
            end

            unfilteredList = nil
            if ALL_BRANCHES_ACTIONS.index(action) != nil then
                unfilteredList = @repo.getStableBranchList()
            else
                unfilteredList = @repo.getBranchList(opts[:br_suff])
            end

            return unfilteredList.map(){|br|
                    branch = Branch::load(@repo, br, @ci, opts[:br_suff])
                    case branch.is_targetted?(opts)
                    when :too_old
                        log(:VERBOSE, "Skipping older v#{branch.version}")
                        next
                    when :no_match
                        log(:VERBOSE, "Skipping v#{branch.version} not matching" +
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
                    log(:INFO, "Working on #{branch.verbose_name}")
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
