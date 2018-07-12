module GitMaintain
    class Repo
        VALID_REPO = "github"
        STABLE_REPO = "stable"
        SUBMIT_BINARY="/usr/bin/git-release.ruby2.5"

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
            custom = GitMaintain::getCustom(repo_name)
            if custom != nil then
                puts "# Detected custom classes for repo '#{repo_name}'" if ENV['DEBUG'] == 1
                return custom[:repo].new(dir)
            else
                return Repo.new(dir)
            end
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
            @path = path
            @stable_list=nil
            @stable_branches=nil
            @suffix_list=nil

            if path == nil
                @path = Dir.pwd()
            end
            @remote_valid=`git --work-tree=#{@path} remote -v | egrep '^#{VALID_REPO}' | grep fetch |
                                awk '{ print $2}' | sed -e 's/.*://' -e 's/\.git//'`.chomp()
            @remote_stable=`git --work-tree=#{@path} remote -v | egrep '^#{STABLE_REPO}' | grep fetch |
                                      awk '{ print $2}' | sed -e 's/.*://' -e 's/\.git//'`.chomp()
        end
        attr_reader :path, :remote_valid, :remote_stable

        def run(cmd)
            return `cd #{@path} && #{cmd}`
        end
        def runSystem(cmd)
            return system("cd #{@path} && #{cmd}")
        end
        def runGit(cmd)
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
            runGit("fetch #{STABLE_REPO}")
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

        def submitReleases()
            remote_tags=runGit("ls-remote --tags #{STABLE_REPO} |
                                 egrep 'refs/tags/v[0-9.]*$'").split("\n").map(){
                |x| x.gsub(/.*refs\/tags\//, '')
            }
            local_tags =runGit("tag -l | egrep '^v[0-9.]*$'").split("\n")

            new_tags = local_tags - remote_tags
            if new_tags.empty? then
                puts "All tags are already submitted."
                #                return
            end

            puts "This will officially release these tags: #{new_tags.join(", ")}"
            rep = GitMaintain::confirm("release them")
            if rep != 'y' then
                raise "Aborting.."
            end

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

            puts "Last chance to cancel before submitting"
            rep= GitMaintain::confirm("submit these releases")
            if rep != 'y' then
                raise "Aborting.."
            end
            puts `#{SUBMIT_BINARY}`
        end


        def list_branches(opts)
            puts getStableList(opts[:br_suff])
        end
        def list_suffixes(opts)
            puts getSuffixList()
        end
        def submit_release(opts)
            submitReleases()
        end
    end
end
