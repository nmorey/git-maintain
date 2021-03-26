module GitMaintain
    class HealthdBranch < Branch
        REPO_NAME = "healthd"

        def release(opts)
            prev_ver=@repo.runGit("show HEAD:CHANGELOG | grep -A 1 -- '---------'  | head -n 2 | tail -n 1 | awk '{ print $1}'").chomp()
            ver_nums = prev_ver.split(".")

            if opts[:manual_branch] == nil then
                new_ver =  (ver_nums[0 .. -2] + [ver_nums[-1].to_i() + 1 ]).join(".")
                git_prev_ver = "v" + (ver_nums[-1] == "0" ? ver_nums[0 .. -2].join(".") : prev_ver)
            else
                new_ver =  (ver_nums[0 .. -3] + [ver_nums[-2].to_i() + 1 ] + [ "0" ]).join(".")
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
            tag_file.puts "healthd-#{new_ver}"
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
            @repo.run("sed -i -e 's/\\(Version:[[:space:]]*\\)[0-9.]\\+/\\1#{new_ver}/g' */*.spec")
            @repo.runGit("add  CHANGELOG */*.spec")

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
    class HealthdRepo < Repo
        def initialize(path)
            super(path)
            @NOTIFY_RELEASE = false
        end
    end
    GitMaintain::registerCustom(HealthdBranch::REPO_NAME,
                                { GitMaintain::Branch => HealthdBranch,
                                  GitMaintain::Repo => HealthdRepo})
end
