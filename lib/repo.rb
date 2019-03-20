module GitMaintain
    class Repo
        @@VALID_REPO = "github"
        @@STABLE_REPO = "stable"
        @@SUBMIT_BINARY="git-release"

        ACTION_LIST = [
            :list_branches,
            # Internal commands for completion
            :list_suffixes, :submit_release
        ]
        ACTION_HELP = [
            "* submit_release: Push the to stable and create the release packages",
        ]

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

            if path == nil
                @path = Dir.pwd()
            end

            @valid_repo = runGit("config maintain.valid-repo 2> /dev/null").chomp()
            @valid_repo = @@VALID_REPO if @valid_repo == ""
            @stable_repo = runGit("config maintain.stable-repo 2>/dev/null").chomp()
            @stable_repo = @@STABLE_REPO if @stable_repo == ""

            @remote_valid=runGit("remote -v | egrep '^#{@valid_repo}' | grep fetch |
                                awk '{ print $2}' | sed -e 's/.*://' -e 's/\\.git//'")
            @remote_stable=runGit("remote -v | egrep '^#{@stable_repo}' | grep fetch |
                                      awk '{ print $2}' | sed -e 's/.*://' -e 's/\\.git//'")

            @branch_format_raw = runGit("config maintain.branch-format 2> /dev/null").chomp()
            @branch_format = Regexp.new(/#{@branch_format_raw}/)
            @stable_branch_format = runGit("config maintain.stable-branch-format 2> /dev/null").chomp()
            @stable_base_format = runGit("config maintain.stable-base-format 2> /dev/null").chomp()

            @stable_base_patterns=
                runGit("config --get-regexp   stable-base | egrep '^stable-base\.' | "+
                       "sed -e 's/stable-base\.//' -e 's/---/\\//g'").split("\n").inject({}){ |m, x|
                y=x.split(" ");
                m[y[0]] = y[1]
                m
            }
        end
        attr_reader :path, :remote_valid, :remote_stable, :valid_repo, :stable_repo

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
        def runGitImap(cmd)
            return `export GIT_ASKPASS=$(dirname $(dirname $(which git)))/lib/git-core/git-gui--askpass;
                  if [ ! -f $GIT_ASKPASS ]; then
                  	export GIT_ASKPASS=$(dirname $(which git))/git-gui--askpass;
                  fi;
                  if [ ! -f $GIT_ASKPASS ]; then
                  	export GIT_ASKPASS=/usr/lib/ssh/ssh-askpass;
                  fi; git --work-tree=#{@path} imap-send #{cmd}`
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

        def stableUpdate()
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

        def submitReleases(opts)
            remote_tags=runGit("ls-remote --tags #{@stable_repo} |
                                 egrep 'refs/tags/v[0-9.]*$'").split("\n").map(){
                |x| x.gsub(/.*refs\/tags\//, '')
            }
            local_tags =runGit("tag -l | egrep '^v[0-9.]*$'").split("\n")

            new_tags = local_tags - remote_tags
            if new_tags.empty? then
                log(:INFO,  "All tags are already submitted.")
                return
            end

            log(:WARNING, "This will officially release these tags: #{new_tags.join(", ")}")
            rep = GitMaintain::confirm(opts, "release them")
            if rep != 'y' then
                raise "Aborting.."
            end

            if @NOTIFY_RELEASE != false
                mail_path=`mktemp`.chomp()
                mail = File.open(mail_path, "w+")
                mail.puts "From " + runGit("rev-parse HEAD") + " " + `date`.chomp()
                mail.puts "From: " + runGit("config user.name") +
                          " <" + runGit("config user.email") +">"
                mail.puts "To: " + runGit("config patch.target")
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
                                   (new_tags[0 .. -2].join(", ") + " and " + new_tags[-1] + " have ") :
                                   (new_tags.join(" ") + " has ")) +
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
                mail.puts "It's available at the normal places:"
                mail.puts ""
                mail.puts "git://github.com/#{@remote_stable}"
                mail.puts "https://github.com/#{@remote_stable}/releases"
                mail.close()

                puts runGitImap("< #{mail_path}; rm -f #{mail_path}")
            end

            log(:WARNING, "Last chance to cancel before submitting")
            rep= GitMaintain::confirm(opts, "submit these releases")
            if rep != 'y' then
                raise "Aborting.."
            end
            puts `#{@@SUBMIT_BINARY}`
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
            submitReleases(opts)
        end

        def find_alts(commit)
            alts=[]

            subj=runGit("log -1 --pretty='%s' #{commit}")
            return alts if $? != 0

            branches = getStableBranchList().map(){|v| @@STABLE_REPO + "/" + versionToStableBranch(v)}
            p branches
            runGit("log -F --grep \"$#{subj}\" --format=\"%H\" #{branches.join(" ")}").
                split("\n").each(){|c|
                next if c == commit
                cursubj=runGit("log -1 --pretty='%s' #{c}")
                alts << c if subj == cursubj
            }

            return alts
        end
    end
end
