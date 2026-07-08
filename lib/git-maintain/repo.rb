require 'octokit'
require 'io/console'

# Main module for git-maintain repository maintenance tool.
module GitMaintain
    # Class representing a git repository being maintained by git-maintain.
    # Handles parsing and caching configuration, querying branches/tags, and executing git commands.
    class Repo < Common
        # Default name of the validation/upstream repository.
        @@VALID_REPO = "github"
        # Default name of the stable release repository.
        @@STABLE_REPO = "stable"
        # Default path to the release package submission helper command.
        @@SUBMIT_BINARY="git-release"

        # List of available actions for Repo class.
        ACTION_LIST = [
            :list_branches,
            :summary,
            # Internal commands for completion
            :list_suffixes, :submit_release
        ]
        # Description map of actions for CLI help output.
        ACTION_HELP = {
            :submit_release => "Push the tags to 'stable' remote and create the release packages",
            :summary => "Displays a summary of the configuration and the branches git-maintain sees"
        }

        # Factory method to load an instance of the Repo class or its repository-specific subclass.
        #
        # @param path [String] Repository directory path (defaults to current working directory)
        # @return [Repo] The loaded Repo instance (or subclass)
        # @raise [GitMaintainError] If class loading fails
        def self.load()
            (repo_path, repo_name) = GitMaintain::getRepoInfos()
            return GitMaintain::loadClass(Repo, repo_name, repo_path)
        end

        # Validate parsed options for repository-level actions.
        #
        # @param opts [Hash] Options hash to validate
        # @raise [GitMaintainError] If options are invalid or conflicting
        def self.check_opts(opts)
            if opts[:action] == :submit_release then
                if opts[:br_suff] != "master" then
                    raise GitMaintainError.new("Action #{opts[:action]} can only be done on 'master' suffixed branches")
                end
            end
        end

        # Initialize the Repo instance, parsing git configurations and detecting remotes/formats.
        #
        # @param path [String, nil] Repository directory path (defaults to current working directory)
        # @raise [GitMaintainError] If configuration format or values are invalid
        def initialize(path)
            GitMaintain::checkDirectConstructor(self.class)

            @path = path
            @branch_list=nil
            @stable_branches=nil
            @suffix_list=nil
            @config_cache={}

            if path == nil
                @path = Dir.pwd()
            end
            @name = File.basename(@path)

            @valid_repo = getGitConfig("maintain.valid-repo")
            @valid_repo = @@VALID_REPO if @valid_repo == ""
            @stable_repo = getGitConfig("maintain.stable-repo")
            @stable_repo = @@STABLE_REPO if @stable_repo == ""

            @remote_valid=runGit("remote -v | grep -E '^#{@valid_repo}' | grep fetch |
                                awk '{ print $2}' | sed -e 's/.*://' -e 's/\\.git//'")
            @remote_stable=runGit("remote -v | grep -E '^#{@stable_repo}' | grep fetch |
                                      awk '{ print $2}' | sed -e 's/.*://' -e 's/\\.git//'")

            @auto_fetch = getGitConfig("maintain.autofetch")
            case @auto_fetch
            when ""
                @auto_fetch = nil
            when "true", "yes", "on"
                @auto_fetch = true
            when "false", "no", "off"
                @auto_fetch = false
            else
                raise GitMaintainError.new("Invalid value '#{@auto_fetch}' in git config for maintain.autofetch")
            end

            @branch_format_raw = getGitConfig("maintain.branch-format")
            @branch_format = Regexp.new(@branch_format_raw)
            @stable_branch_format = getGitConfig("maintain.stable-branch-format")
            @stable_base_format = getGitConfig("maintain.stable-base-format")

            @stable_base_patterns=
                runGit("config --get-regexp   stable-base | grep -E '^stable-base\.' | "+
                       "sed -e 's/stable-base\.//' -e 's/---/\\//g'").split("\n").inject({}){ |m, x|
                y=x.split(" ");
                m[y[0]] = y[1]
                m
            }

            @mail_format = getGitConfig("maintain.mail-format")
            if @mail_format == "" then
                @mail_format = :imap_send
            else
                # Check that the format is valid
                case @mail_format
                when "imap_send", "send_email"
                else
                    raise GitMaintainError.new("Invalid mail-format #{@mail_format}")
                end

                @mail_format = @mail_format.to_sym()
            end
        end
        attr_reader :path, :name, :remote_valid, :remote_stable, :valid_repo, :stable_repo



        # Check if the specified git reference exists.
        #
        # @param ref [String] Git reference to verify (e.g. 'HEAD' or 'origin/master')
        # @return [String] Resolved SHA-1 string of the reference
        # @raise [NoRefError] If the reference does not exist
        def ref_exist?(ref)
            begin
                return runGit("rev-parse --verify --quiet '#{ref}'")
            rescue RunError
                raise(NoRefError.new(ref))
            end
        end

        # Run a git imap-send command setting GIT_ASKPASS environment variables.
        #
        # @param cmd [String] The command arguments
        # @return [String] Output of the command execution
        def runGitImap(cmd)
            return `export GIT_ASKPASS=$(dirname $(dirname $(which git)))/lib/git-core/git-gui--askpass;
                  if [ ! -f $GIT_ASKPASS ]; then
                  	export GIT_ASKPASS=$(dirname $(which git))/git-gui--askpass;
                  fi;
                  if [ ! -f $GIT_ASKPASS ]; then
                  	export GIT_ASKPASS=/usr/lib/ssh/ssh-askpass;
                  fi; git --work-tree=#{@path} imap-send #{cmd}`
        end

        # Retrieve a git configuration value, with caching.
        #
        # @param entry [String] Config key name (e.g., 'user.name')
        # @return [String] Cached or fetched config value string
        # @raise [RunError] If running git config fails unexpectedly
        def getGitConfig(entry)
            return @config_cache[entry] ||= runGit("config #{entry} 2> /dev/null", {}, false).chomp()
        end

        # Spawn an interactive subshell (bash), wrapping error conditions into a GitMaintainError.
        #
        # @param env [String] Optional environment variables string to prepend
        # @raise [GitMaintainError] If the shell exits with a non-zero code and is cancelled by the user
        def runBash(env="")
            begin
                runSystem(env + " bash")
            rescue RunError
                log(:ERROR, "Shell exited with code #{$?}. Exiting")
                raise GitMaintainError.new("Cancelled by user")
            end
            log(:INFO, "Continuing...")

        end

        # Get the single-line headline/oneline description of a commit SHA.
        #
        # @param sha [String] Commit SHA
        # @return [String] Single-line description (oneline)
        # @raise [RunError] If git command execution fails
        def getCommitHeadline(sha)
            return runGit("show --format=oneline --no-patch --no-decorate #{sha}")
        end

        # Get the commit subject text.
        #
        # @param sha [String] Commit SHA
        # @return [String] The commit subject string
        # @raise [RunError] If git command execution fails
        def getCommitSubj(sha)
            return runGit("log -1 --pretty=\"%s\" #{sha}")
        end

        # Fetch stable updates if auto-fetching is enabled.
        #
        # @param fetch [Boolean, nil] Override to bypass or force fetch configuration
        # @raise [RunError] If git fetch execution fails
        def stableUpdate(fetch=nil)
            fetch = @auto_fetch if fetch == nil
            return if fetch == false
            log(:VERBOSE, "Fetching stable updates...")
            runGit("fetch #{@stable_repo}")
        end

        # List all local branches matching the configured stable suffix name.
        #
        # @param br_suff [String] Branch suffix (e.g. 'master')
        # @return [Array<String>] List of matching branch version strings (e.g., ['1.0'])
        # @raise [RunError] If git branch execution fails
        def getBranchList(br_suff)
            return @branch_list if @branch_list != nil

            @branch_list=runGit("branch").split("\n").map(){|x|
                x=~ Regexp.new("#{@branch_format_raw}/#{br_suff}$") ?
                    $1 : nil
            }.compact().uniq()

            return @branch_list
        end

        # List all remote stable branches from the stable remote.
        #
        # @return [Array<String>] List of remote stable branch version strings
        # @raise [RunError] If git branch execution fails
        def getStableBranchList()
            return @stable_branches if @stable_branches != nil

            @stable_branches=runGit("branch -a").split("\n").map(){|x|
                x=~ Regexp.new("remotes/#{@@STABLE_REPO}/#{@stable_branch_format.gsub(/\\1/, '([0-9]+)')}$") ?
                    $1 : nil
            }.compact().uniq()

            return @stable_branches
        end

        # Get all local branch suffix values.
        #
        # @return [Array<String>] List of local branch suffixes
        # @raise [RunError] If git branch execution fails
        def getSuffixList()
            return @suffix_list if @suffix_list != nil

            @suffix_list = runGit("branch").split("\n").map(){|x|
                x=~ @branch_format ?
                    Regexp.new("^\\*?\\s*#{@branch_format_raw}/([a-zA-Z0-9_-]+)\\s*$").match(x)[-1] :
                    nil
            }.compact().uniq()

            return @suffix_list
        end

        # Find local release tags that have not yet been pushed to the remote stable repository.
        #
        # @param opts [Hash] Options hash
        # @return [Array<String>] List of unreleased version tags (e.g. ['v1.0.1'])
        # @raise [RunError] If running git ls-remote or git tag fails
        def getUnreleasedTags(opts)
            remote_tags=runGit("ls-remote --tags #{@stable_repo} |
                                 grep -E 'refs/tags/v[0-9.]*$'").split("\n").map(){
                |x| x.gsub(/.*refs\/tags\//, '')
            }
            local_tags =runGit("tag -l | grep -E '^v[0-9.]*$'").split("\n")

            new_tags = local_tags - remote_tags
            return new_tags
        end

        # Generate and transmit or save a release announcement email.
        #
        # @param opts [Hash] Options hash
        # @param new_tags [Array<String>] List of newly released tags
        # @raise [RunError] If running git show or other execution commands fails
        def genReleaseNotif(opts, new_tags)
            return if @NOTIFY_RELEASE == false

            mail_path=`mktemp`.chomp()
            mail = File.open(mail_path, "w+")
            mail.puts "From " + runGit("rev-parse HEAD") + " " + `date`.chomp()
            mail.puts "From: " + getGitConfig("user.name") +
                      " <" + getGitConfig("user.email") +">"
            mail.puts "To: " + getGitConfig("patch.target")
            mail.puts "Date: " + `date -R`.chomp()

            if new_tags.length > 4 then
                mail.puts "Subject: [ANNOUNCE] " + File.basename(@path) + ": new stable releases"
                mail.puts ""
                mail.puts "These version were tagged/released:\n * " +
                          new_tags.join("\n * ")
                mail.puts ""
            else
                mail.puts "Subject: [ANNOUNCE] " + File.basename(@path) + " " +
                          (new_tags.length > 1 ?
                               (new_tags[0 .. -2].join(", ") + " and " + new_tags[-1] + " have") :
                               (new_tags.join(" ") + " has")) +
                          " been tagged/released"
                mail.puts ""
            end
            mail.puts "It's available at the normal places:"
            mail.puts ""
            mail.puts "git://github.com/#{@remote_stable}"
            mail.puts "https://github.com/#{@remote_stable}/releases"
            mail.puts ""
            mail.puts "---"
            mail.puts ""
            mail.puts "Here's the information from the tags:"
            new_tags.sort().each(){|tag|
                mail.puts `git show #{tag} --no-decorate -q | awk '!p;/^-----END PGP SIGNATURE-----/{p=1}'`
                mail.puts ""
            }
            mail.close()

            case @mail_format
            when :imap_send
                puts runGitImap("< #{mail_path}")
            when :send_email
                run("cp #{mail_path} announce-release.eml")
                log(:INFO, "Generated annoucement email in #{@path}/announce-release.eml")
            end
            run("rm -f #{mail_path}")
        end

        # Submit release tags by delegating to `createRelease`.
        #
        # @param opts [Hash] Options hash
        # @param new_tags [Array<String>] List of release tags to submit
        # @raise [GitMaintainError] If submitting release fails
        def submitReleases(opts, new_tags)
            new_tags.each(){|tag|
                createRelease(opts, tag)
            }
        end

        # Create a release for the specified tag on GitHub.
        # Pushes the tag to the remote stable repository and optionally calls GitHub release API.
        #
        # @param opts [Hash] Options hash
        # @param tag [String] Release tag name (e.g. 'v1.0.1')
        # @param github_rel [Boolean] True to create a GitHub release via API
        # @raise [GitMaintainError] If git pushing or API release creation fails
        def createRelease(opts, tag, github_rel=true)
            log(:INFO, "Creating a release for #{tag}")
	    runGit("push #{@stable_repo} refs/tags/#{tag}")

            if github_rel == true then
 		msg = runGit("tag -l -n1000 '#{tag}'") + "\n"

		# Ye ghods is is a horrific format to parse
		name, body = msg.split("\n", 2)
		name = name.gsub(/^#{tag}/, '').strip
		body = body.split("\n").map { |l| l.sub(/^    /, '') }.join("\n")
		api.create_release(@remote_stable, tag, :name => name, :body => body)
            end
        end

        # Map a version number and suffix to a local branch name.
        #
        # @param version [String] Version string (e.g., '1.0')
        # @param suff [String] Suffix string
        # @return [String] Local branch name (e.g., 'stable/1.0/master')
        def versionToLocalBranch(version, suff)
            return @branch_format_raw.gsub(/\\\//, '/').
                       gsub(/\(.*\)/, version) + "/#{suff}"
        end

        # Map a version number to a stable branch name.
        #
        # @param version [String] Version string
        # @return [String] Stable branch name
        def versionToStableBranch(version)
            return version.gsub(/^(.*)$/, @stable_branch_format)
        end

        # Resolve the stable base commit/reference for a given branch.
        #
        # @param branch [String] Local branch name
        # @return [String] Resolvable stable base reference
        # @raise [GitMaintainError] If no stable base can be resolved for the branch
        def findStableBase(branch)
            base=nil
            if branch =~ @branch_format then
                base = branch.gsub(Regexp.new("^\\*?\\s*#{@branch_format_raw}/.*$"), @stable_base_format)
            end

            @stable_base_patterns.each(){|pattern, b|
                if branch =~ /#{pattern}\// || branch =~ /#{pattern}$/
                    base = b
                    break
                end
            }
            raise GitMaintainError.new("Could not a find a stable base for branch #{branch}") if base == nil
            return base
        end

        # Print the local stable branches list to standard output.
        #
        # @param opts [Hash] Options hash
        # @raise [RunError] If running git branch fails
        def list_branches(opts)
            puts getBranchList(opts[:br_suff])
        end

        # Print all detected branch suffixes to standard output.
        #
        # @param opts [Hash] Options hash
        # @raise [RunError] If running git branch fails
        def list_suffixes(opts)
            puts getSuffixList()
        end

        # Find and submit any unreleased tags, generating announcements and creating GitHub releases.
        #
        # @param opts [Hash] Options hash
        # @raise [GitMaintainError] If the release submission is aborted or fails
        def submit_release(opts)
            new_tags = getUnreleasedTags(opts)
            if new_tags.empty? then
                log(:INFO,  "All tags are already submitted.")
                return
            end

            log(:WARNING, "This will officially release these tags: #{new_tags.join(", ")}")
            rep = confirm(opts, "release them", true)
            if rep != 'y' then
                raise GitMaintainError.new("Aborting..")
            end

            if @NOTIFY_RELEASE != false
                genReleaseNotif(opts, new_tags)
            end

            log(:WARNING, "Last chance to cancel before submitting")
            rep= confirm(opts, "submit these releases", true)
            if rep != 'y' then
                raise GitMaintainError.new("Aborting..")
            end
            submitReleases(opts, new_tags)
        end

        # Print a diagnostic summary of the repository configuration and detected local/upstream branches.
        #
        # @param opts [Hash] Options hash
        # @raise [RunError] If running git commands fails
        def summary(opts)
            log(:INFO, "Configuration summary:")
            if self.class != GitMaintain::Repo then
                log(:INFO, "Using custom repo class: #{self.class.to_s()}")
            end
            log(:INFO, "Stable remote: #{@stable_repo}")
            log(:INFO, "Validation remote: #{@valid_repo}")
            log(:INFO, "")
            log(:INFO, "Branch config:")
            log(:INFO, "Local branch format: /#{@branch_format_raw}/")
            log(:INFO, "Remote stable branch format: #{@stable_branch_format}")
            log(:INFO, "Remote stable base format: #{@stable_base_format}")

            if @stable_base_patterns.length > 0 then
                log(:INFO, "")
                log(:INFO, "Stable base rules:")
                @stable_base_patterns.each(){|name, base|
                    log(:INFO, "\t#{name} -> #{base}")
                }
            end
            brList = getBranchList(opts[:br_suff])
            brStList = getStableBranchList()

            if brList.length > 0 then
                log(:INFO, "")
                log(:INFO, "Local branches:")
                brList.each(){|br|
                    branch = Branch.load(self, br, nil, opts[:br_suff])
                    localBr = branch.local_branch
                    stableBr = @@STABLE_REPO + "/" + branch.remote_branch
                    stableBase = branch.stable_base
                    begin
                        ref_exist?(stableBr)
                    rescue NoRefError
                        stableBr = "<MISSING>"
                    end
                    log(:INFO, "\t#{localBr} -> #{stableBr} (#{stableBase})")
                    brStList.delete(br)
                }
            end

            if brStList.length > 0 then
                log(:INFO, "")
                log(:INFO, "Upstream branches:")
                brStList.each(){|br|
                    branch = Branch.load(self, br, nil, opts[:branch_suff])
                    stableBr = @@STABLE_REPO + "/" + branch.remote_branch
                    stableBase = branch.stable_base
                    log(:INFO, "\t<MISSING> -> #{stableBr} (#{stableBase})")
                }
            end
        end

        # Search remote stable branches for alternative commit SHAs with the same commit subject.
        #
        # @param commit [String] Original commit SHA
        # @return [Array<String>] List of alternative commit SHAs with identical subject
        # @raise [RunError] If running git commands fails
        def find_alts(commit)
            alts=[]

            begin
                subj=runGit("log -1 --pretty='%s' #{commit}")
            rescue RunError
                return []
            end

            branches = getStableBranchList().map(){|v| @@STABLE_REPO + "/" + versionToStableBranch(v)}

            runGit("log -F --grep \"$#{subj}\" --format=\"%H\" #{branches.join(" ")}").
                split("\n").each(){|c|
                next if c == commit
                cursubj=runGit("log -1 --pretty='%s' #{c}")
                alts << c if subj == cursubj
            }

            return alts
        end

        # Get or initialize the Octokit GitHub API client.
        #
        # @return [Octokit::Client] The initialized API client instance
        def api
            @api ||= Octokit::Client.new(:access_token => token, :auto_paginate => true)
        end

        # Get or fetch the cached GitHub OAuth API token.
        #
        # @return [String] The API token string
        def token
            @token ||= begin
                           # We cannot use the 'defaults' functionality of git_config here,
                           # because get_new_token would be evaluated before git_config ran
                           tok = getGitConfig("maintain.api-token")
                           tok.to_s() == "" ? get_new_token : tok
                       end
        end

        # Interactively prompt the user for GitHub credentials to create and save a new OAuth token.
        # Supports two-factor authentication (OneTimePasswordRequired).
        #
        # @return [String] The newly generated API token
        # @raise [Octokit::Unauthorized] If username/password is incorrect
        def get_new_token
            puts "Requesting a new OAuth token from Github..."
            print "Github username: "
            user = $stdin.gets.chomp
            print "Github password: "
            pass = $stdin.noecho(&:gets).chomp
            puts

            api = Octokit::Client.new(:login => user, :password => pass)

            begin
                res = api.create_authorization(:scopes => [:repo], :note => "git-maintain")
            rescue Octokit::Unauthorized
                puts "Username or password incorrect.  Please try again."
                return get_new_token
            rescue Octokit::OneTimePasswordRequired
                print "Github OTP: "
                otp = $stdin.noecho(&:gets).chomp
                res = api.create_authorization(:scopes => [:repo], :note => "git-maintain",
                                               :headers => {"X-GitHub-OTP" => otp})
            end

            token = res[:token]
            runGit("config --global maintain.api-token '#{token}'")

            # Now reopen with the token so OTP does not bother us
            @api=nil
            token
        end
    end
end
