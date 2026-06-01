# Module containing addon classes for hpc-testing repository.
module GitMaintain

    # Subclass of Branch customized for the hpc-testing repository.
    class HPCTestingBranch < Branch
        # The name of this repository.
        REPO_NAME = "hpc-testing"

        # Configure hpc-testing release options.
        #
        # @param action [Symbol] Selected action name
        # @param optsParser [OptionParser] The OptionParser instance
        # @param opts [Hash] The options hash to populate
        def self.set_opts(action, optsParser, opts)
            opts[:auto_news] = false

            case action
            when :release
                 optsParser.on("--auto-news", "Auto-generate NEWS entries.") {
                     opts[:auto_news] = true }
            end
        end

        # Create a new release for hpc-testing.
        # Updates spec files, NEWS, commits, and tags the release.
        #
        # @param opts [Hash] Options hash
        # @raise [GitMaintainError] If prepping, committing, or tagging fails
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
            rep = checkLog(opts, @local_branch, git_prev_ver, "release")
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
        end

        # Initialize HPCTestingBranch, forcing NO_CI to true.
        #
        # @param repo [Repo] The Repo instance
        # @param version [String] Suffix version or branch name
        # @param ci [CI] The CI instance
        # @param branch_suff [String] Branch suffix
        # @raise [NoRefError] If resolving git references fails
        def initialize(repo, version, ci, branch_suff)
            super(repo, version, ci, branch_suff)
            @NO_CI = true
        end
    end

    # Repo class customized for the hpc-testing repository.
    class HPCTestingRepo < Repo
        # Initialize HPCTestingRepo with release notifications disabled.
        #
        # @param path [String] Repository directory path
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
