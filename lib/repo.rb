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
            @stable_list=nil
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
            @stable_base_patterns=
                runGit("config --get-regexp   stable-base | egrep '^stable-base\.' | "+
                       "sed -e 's/stable-base\.//' -e 's/---/\\//g'").split("\n").inject({}){ |m, x|
                y=x.split(" ");
                m[y[0]] = y[1]
                m
                }
        end
        attr_reader :path, :remote_valid, :remote_stable, :valid_repo, :stable_repo

        def run(cmd)
            return `cd #{@path} && #{cmd}`
        end
        def runSystem(cmd)
            return system("cd #{@path} && #{cmd}")
        end
        def runGit(cmd)
            if ENV["DEBUG"].to_s() != "" then
                puts "Called from #{caller[1]}"
                puts "Running git command '#{cmd}'"
            end
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

        def stableUpdate()
            puts "# Fetching stable updates..."
            runGit("fetch #{@stable_repo}")
        end
        def getStableList(br_suff)
            return @stable_list if @stable_list != nil

            @stable_list=runGit("branch").split("\n").map(){|x|
                x=~ /dev\/stable-v[0-9]+\/#{br_suff}/ ?
                    x.gsub(/\*?\s*dev\/stable-v([0-9]+)\/#{br_suff}\s*$/, '\1') :
                    nil}.compact().uniq()

            return @stable_list
        end

        def getSuffixList()
            return @suffix_list if @suffix_list != nil

            @suffix_list = runGit("branch").split("\n").map(){|x|
                x=~ /dev\/stable-v[0-9]+\/[a-zA-Z0-9_-]+/ ?
                    x.gsub(/\*?\s*dev\/stable-v[0-9]+\/([a-zA-Z0-9_-]+)\s*$/, '\1') :
                    nil}.compact().uniq()

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
                puts "All tags are already submitted."
                return
            end

            puts "This will officially release these tags: #{new_tags.join(", ")}"
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
                mail.puts "Subject: [ANNOUNCE] " + File.basename(@path) + " " +
                          (new_tags.length > 1 ?
                               (new_tags[0 .. -2].join(", ") + " and " + new_tags[-1]) :
                               new_tags.join(" ")) +
                          " has been tagged/released"
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

            puts "Last chance to cancel before submitting"
            rep= GitMaintain::confirm(opts, "submit these releases")
            if rep != 'y' then
                raise "Aborting.."
            end
            puts `#{@@SUBMIT_BINARY}`
        end
        def findStableBase(branch)
            @stable_base_patterns.each(){|pattern, base|
                return base if branch =~ /#{pattern}\// || branch =~ /#{pattern}$/
            }
            raise("Could not a find a stable base for branch #{branch}")
        end

        def list_branches(opts)
            puts getStableList(opts[:br_suff])
        end
        def list_suffixes(opts)
            puts getSuffixList()
        end
        def submit_release(opts)
            submitReleases(opts)
        end
    end
end
