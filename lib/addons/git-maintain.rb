module GitMaintain
    class GitMaintainBranch < Branch
        REPO_NAME = "git-maintain"
        def self.set_opts(action, optsParser, opts)
            opts[:rel_type] = nil

            case action
            when :release
                 optsParser.on("--major [VERSION]", "Release a major version.") {|val|
                     opts[:rel_type] = :major
                     opts[:new_ver] = val
                 }
                 optsParser.on("--stable", "Release a stable version.") {
                     opts[:rel_type] = :stable
                 }
           end
        end
        def self.check_opts(opts)
            if opts[:action] == :release then
                case opts[:rel_type]
                when nil
                    raise "No release type specified use --stable or --major"
                when :major
                    if opts[:manual_branch] == nil then
                        GitMaintain::log(:INFO, "Major release selected. Auto-forcing branch to master")
                        opts[:manual_branch] = "master"
                    end
                end
            end
        end
        def release(opts)
            prev_ver=@repo.runGit("show HEAD:CHANGELOG | grep -A 1 -- '---------'  | head -n 2 | tail -n 1 | awk '{ print $1}'").chomp()
            ver_nums = prev_ver.split(".")

            if opts[:rel_type] == :stable then
                new_ver =  (ver_nums[0 .. -2] + [ver_nums[-1].to_i() + 1 ]).join(".")
                git_prev_ver = "v" + (ver_nums[-1] == "0" ? ver_nums[0 .. -2].join(".") : prev_ver)
            elsif opts[:rel_type] == :major then
                new_ver =  (ver_nums[0 .. -3] + [ver_nums[-2].to_i() + 1 ] + [ "0" ]).join(".")
                new_ver = opts[:new_ver] if opts[:new_ver] != nil
                git_prev_ver = "v" + prev_ver
            end


            changes=@repo.runGit("show HEAD:CHANGELOG |  awk ' BEGIN {count=0} {if ($1 == \"------------------\") count++; if (count == 0) print $0}'")

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
            tag_file.puts "git-maintain-#{new_ver}"
            tag_file.puts ""
            tag_file.puts changes
            tag_file.close()

            @repo.run("cat <<EOF > CHANGELOG.new
------------------
#{new_ver} #{`date '+ (%Y-%m-%d)'`.chomp()}
------------------

$(cat CHANGELOG)
EOF
mv CHANGELOG.new CHANGELOG")

            # Add and commit
            @repo.runGit("add  CHANGELOG")
            @repo.runGitInteractive("commit -F #{tag_path} --verbose --edit --signoff")
            if $? != 0 then
                raise("Failed to commit on branch #{local_branch}")
            end
            @repo.runGitInteractive("tag -a -s v#{new_ver} --edit -F #{tag_path}")
            if $? != 0 then
                raise("Failed to tag branch #{local_branch}")
            end
            `rm -f #{tag_path}`
        end
    end
    class GitMaintainRepo < Repo
        def initialize(path)
            super(path)
            @NOTIFY_RELEASE = false
        end
    end
    GitMaintain::registerCustom(GitMaintainBranch::REPO_NAME,
                                { GitMaintain::Branch => GitMaintainBranch,
                                  GitMaintain::Repo => GitMaintainRepo})
end
