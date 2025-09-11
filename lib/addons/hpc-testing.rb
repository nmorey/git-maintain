module GitMaintain
    class HPCTestingBranch < Branch
        REPO_NAME = "hpc-testing"
        def self.set_opts(action, optsParser, opts)
            opts[:auto_news] = false

            case action
            when :release
                 optsParser.on("--auto-news", "Auto-generate NEWS entries.") {
                     opts[:auto_news] = true }
           end
        end
        def release(opts)
            prev_ver=@repo.runGit("show HEAD:rpm/hpc-testing.spec  | grep Version: | awk '{ print $NF}'").
                         chomp()
            ver_nums = prev_ver.split(".")

            if opts[:manual_branch] == nil then
                new_ver =  (ver_nums[0 .. -2] + [ver_nums[-1].to_i() + 1 ]).join(".")
                git_prev_ver = "v" + (ver_nums[-1] == "0" ? ver_nums[0 .. -2].join(".") : prev_ver)
            else
                new_ver =  (ver_nums[0 .. -3] + [ver_nums[-2].to_i() + 1 ] + [ "0" ]).join(".")
                git_prev_ver = "v" + prev_ver
            end

            puts "Preparing release #{prev_ver} => #{new_ver}"
            rep = GitMaintain::checkLog(opts, @local_branch, git_prev_ver, "release")
            if rep != "y" then
                puts "Skipping release"
                return
            end

            # Prepare tag message
            tag_path=`mktemp`.chomp()
            puts tag_path
            tag_file = File.open(tag_path, "w+")
            tag_file.puts "hpc-testing-#{new_ver}"
            tag_file.puts ""
            tag_file.puts `git log HEAD ^#{git_prev_ver} --no-merges --format='   * %s'`
            tag_file.close()

            # Update version number in relevant files
            @repo.run("sed -i -e 's/\\(Version:[[:space:]]*\\)[0-9.]*/\\1#{new_ver}/g' rpm/hpc-testing.spec")

            news_entries = ""
            if opts[:auto_news] == true then
                news_entries = "\n" + @repo.runGit("log HEAD ^#{git_prev_ver} --no-merges  --format='  * %s'")
            end
            @repo.run("cat <<EOF > NEWS.new
- hpc-testing #{new_ver}#{news_entries}
$(cat NEWS)
EOF
mv NEWS.new NEWS")

            release_do_add_commit_tag(opts, ["rpm/hpc-testing.spec", "NEWS"], "v" + new_ver, tag_path)
            `rm -f #{tag_path}`
            return 0
        end

        def initialize(repo, version, ci, branch_suff)
            super(repo, version, ci, branch_suff)
            @NO_CI = true
        end
    end
    class HPCTestingRepo < Repo
        def initialize(path)
            super(path)
            @NOTIFY_RELEASE = false
        end
    end
    GitMaintain::registerCustom(HPCTestingBranch::REPO_NAME,
                                { GitMaintain::Branch => HPCTestingBranch,
                                  GitMaintain::Repo => HPCTestingRepo,
                                  GitMaintain::CI => GitMaintain::TravisCI})
end
