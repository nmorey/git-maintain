require 'octokit'
require 'io/console'

module GitMaintain
    class Repo
        @@VALID_REPO = "github"
        @@STABLE_REPO = "stable"
        @@SUBMIT_BINARY="git-release"

        ACTION_LIST = [
            :list_branches,
            :summary,
            # Internal commands for completion
            :list_suffixes, :submit_release
        ]
        ACTION_HELP = {
            :submit_release => "Push the tags to 'stable' remote and create the release packages",
            :summary => "Displays a summary of the configuration and the branches git-maintain sees"
        }

        def self.load(path=".")
            dir = Dir.pwd()
            repo_name = File.basename(dir)
            return GitMaintain::loadClass(Repo, repo_name, dir)
        end

        def self.check_opts(opts)
            if opts[:action] == :submit_release then
                if opts[:br_suff] != "master" then
                    raise "Action #{opts[:action]} can only be done on 'master' suffixed branches"
                end
            end
        end

        def self.execAction(opts, action)
            repo   = Repo::load()

            if action == :submit_release then
                repo.stableUpdate()
            end
            repo.send(action, opts)
        end

        def initialize(path=nil)
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

            @remote_valid=runGit("remote -v | egrep '^#{@valid_repo}' | grep fetch |
                                awk '{ print $2}' | sed -e 's/.*://' -e 's/\\.git//'")
            @remote_stable=runGit("remote -v | egrep '^#{@stable_repo}' | grep fetch |
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
                raise("Invalid value '#{@auto_fetch}' in git config for maintain.autofetch")
            end

            @branch_format_raw = getGitConfig("maintain.branch-format")
            @branch_format = Regexp.new(/#{@branch_format_raw}/)
            @stable_branch_format = getGitConfig("maintain.stable-branch-format")
            @stable_base_format = getGitConfig("maintain.stable-base-format")

            @stable_base_patterns=
                runGit("config --get-regexp   stable-base | egrep '^stable-base\.' | "+
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
                    raise("Invalid mail-format #{@mail_format}")
                end

                @mail_format = @mail_format.to_sym()
            end
        end
        attr_reader :path, :name, :remote_valid, :remote_stable, :valid_repo, :stable_repo

        def log(lvl, str)
            GitMaintain::log(lvl, str)
        end

        def run(cmd)
            return `cd #{@path} && #{cmd}`
        end
        def runSystem(cmd)
            return system("cd #{@path} && #{cmd}")
        end

        def runGit(cmd)
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running git command '#{cmd}'")
            return `git --work-tree=#{@path} #{cmd}`.chomp()
        end
        def runGitInteractive(cmd)
            log(:DEBUG, "Called from #{caller[1]}")
            log(:DEBUG, "Running interactive git command '#{cmd}'")
            return system("git --work-tree=#{@path} #{cmd}")
        end

        def runGitImap(cmd)
            return `export GIT_ASKPASS=$(dirname $(dirname $(which git)))/lib/git-core/git-gui--askpass;
                  if [ ! -f $GIT_ASKPASS ]; then
                  	export GIT_ASKPASS=$(dirname $(which git))/git-gui--askpass;
                  fi;
                  if [ ! -f $GIT_ASKPASS ]; then
                  	export GIT_ASKPASS=/usr/lib/ssh/ssh-askpass;
                  fi; git --work-tree=#{@path} imap-send #{cmd}`
        end
        def getGitConfig(entry)
            return @config_cache[entry] ||= runGit("config #{entry} 2> /dev/null").chomp()
        end

        def runBash()
            runSystem("bash")
            if $? == 0 then
                log(:INFO, "Continuing...")
            else
                log(:ERROR, "Shell exited with code #{$?}. Exiting")
                raise("Cancelled by user")
            end
        end

        def getCommitHeadline(sha)
            return runGit("show --format=oneline --no-patch --no-decorate #{sha}")
        end
        def getCommitSubj(sha)
            return runGit("log -1 --pretty=\"%s\" #{sha}")
        end

        def stableUpdate(fetch=nil)
            fetch = @auto_fetch if fetch == nil
            return if fetch == false
            log(:VERBOSE, "Fetching stable updates...")
            runGit("fetch #{@stable_repo}")
        end
        def getBranchList(br_suff)
            return @branch_list if @branch_list != nil

            @branch_list=runGit("branch").split("\n").map(){|x|
                x=~ /#{@branch_format_raw}\/#{br_suff}$/ ? 
                    $1 : nil
            }.compact().uniq()

            return @branch_list
        end

        def getStableBranchList()
            return @stable_branches if @stable_branches != nil

            @stable_branches=runGit("branch -a").split("\n").map(){|x|
                x=~ /remotes\/#{@@STABLE_REPO}\/#{@stable_branch_format.gsub(/\\1/, '([0-9]+)')}$/ ?
                    $1 : nil
            }.compact().uniq()

            return @stable_branches
        end

        def getSuffixList()
            return @suffix_list if @suffix_list != nil

            @suffix_list = runGit("branch").split("\n").map(){|x|
                x=~ @branch_format ? 
                    /^\*?\s*#{@branch_format_raw}\/([a-zA-Z0-9_-]+)\s*$/.match(x)[-1] :
                    nil
            }.compact().uniq()

            return @suffix_list
        end

        def getUnreleasedTags(opts)
            remote_tags=runGit("ls-remote --tags #{@stable_repo} |
                                 egrep 'refs/tags/v[0-9.]*$'").split("\n").map(){
                |x| x.gsub(/.*refs\/tags\//, '')
            }
            local_tags =runGit("tag -l | egrep '^v[0-9.]*$'").split("\n")

            new_tags = local_tags - remote_tags
            return new_tags
        end
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
        def submitReleases(opts, new_tags)
            new_tags.each(){|tag|
                createRelease(opts, tag)
            }
        end

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

        def versionToLocalBranch(version, suff)
            return @branch_format_raw.gsub(/\\\//, '/').
                gsub(/\(.*\)/, version) + "/#{suff}"
        end

        def versionToStableBranch(version)
            return version.gsub(/^(.*)$/, @stable_branch_format)
        end

        def findStableBase(branch)
            base=nil
            if branch =~ @branch_format then
                base = branch.gsub(/^\*?\s*#{@branch_format_raw}\/.*$/, @stable_base_format)
            end

            @stable_base_patterns.each(){|pattern, b|
                if branch =~ /#{pattern}\// || branch =~ /#{pattern}$/
                    base = b
                    break
                end
            }
            raise("Could not a find a stable base for branch #{branch}") if base == nil
            return base
        end

        def list_branches(opts)
            puts getBranchList(opts[:br_suff])
        end
        def list_suffixes(opts)
            puts getSuffixList()
        end
        def submit_release(opts)
            new_tags = getUnreleasedTags(opts)
            if new_tags.empty? then
                log(:INFO,  "All tags are already submitted.")
                return
            end

            log(:WARNING, "This will officially release these tags: #{new_tags.join(", ")}")
            rep = GitMaintain::confirm(opts, "release them", true)
            if rep != 'y' then
                raise "Aborting.."
            end

            if @NOTIFY_RELEASE != false
                genReleaseNotif(opts, new_tags)
            end

            log(:WARNING, "Last chance to cancel before submitting")
            rep= GitMaintain::confirm(opts, "submit these releases", true)
            if rep != 'y' then
                raise "Aborting.."
            end
            submitReleases(opts, new_tags)
        end
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
                     branch = Branch.load(self, br, nil, opts[:branch_suff])
                     localBr = branch.local_branch
                     stableBr = @@STABLE_REPO + "/" + branch.remote_branch
                     stableBase = branch.stable_base
                     runGit("rev-parse --verify --quiet #{stableBr}")
                     stableBr = "<MISSING>" if $? != 0 
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
        def find_alts(commit)
            alts=[]

            subj=runGit("log -1 --pretty='%s' #{commit}")
            return alts if $? != 0

            branches = getStableBranchList().map(){|v| @@STABLE_REPO + "/" + versionToStableBranch(v)}

            runGit("log -F --grep \"$#{subj}\" --format=\"%H\" #{branches.join(" ")}").
                split("\n").each(){|c|
                next if c == commit
                cursubj=runGit("log -1 --pretty='%s' #{c}")
                alts << c if subj == cursubj
            }

            return alts
        end

        #
        # Github API stuff
        #
	    def api
		    @api ||= Octokit::Client.new(:access_token => token, :auto_paginate => true)
	    end

	    def token
		    @token ||= begin
			               # We cannot use the 'defaults' functionality of git_config here,
			               # because get_new_token would be evaluated before git_config ran
			               tok = getGitConfig("maintain.api-token")
                           tok.to_s() == "" ? get_new_token : tok
		               end
	    end
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
