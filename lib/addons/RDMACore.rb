module GitMaintain
    class RDMACoreBranch < Branch
        REPO_NAME = "rdma-core"

        def release(opts)
            prev_ver=@repo.runGit("show HEAD:CMakeLists.txt  | egrep \"[sS][eE][tT]\\\\(PACKAGE_VERSION\"").
                         chomp().gsub(/[sS][eE][tT]\(PACKAGE_VERSION\s*"([0-9.]*)".*$/, '\1')
            ver_nums = prev_ver.split(".")
            new_ver =  (ver_nums[0 .. -2] + [ver_nums[-1].to_i() + 1 ]).join(".")
            rel_ver = new_ver
            rel_type = :stable
            commit_msg = "Bump to version"

            if @branch_type == :user_specified && @local_branch == "master"
                rel_type = :major
                new_ver = ([ ver_nums[0].to_i() + 1] + ver_nums[1 .. -1]).join(".")
                rel_ver = prev_ver
                prev_ver = ([ ver_nums[0].to_i() - 1] + ver_nums[1 .. -1]).join(".")
                ver_nums = prev_ver.split(".")
                commit_msg ="Update library version to be"
            end

            git_prev_ver = "v" + prev_ver
            # Older tags might do have the terminal minor version (.0) for major releases
            @repo.runGit("rev-parse --verify --quiet #{git_prev_ver}")
            if $? != 0 then
                # Try without the minor version number
                git_prev_ver = "v" + ver_nums[0 .. -2].join(".")
            end

            puts "Preparing #{rel_type.to_s} release #{prev_ver} => #{rel_ver}"
            rep = GitMaintain::checkLog(opts, @local_branch, git_prev_ver, "release")
            if rep != "y" then
                puts "Skipping release"
                return
            end

            # Prepare tag message
            tag_path=`mktemp`.chomp()
            puts tag_path
            tag_file = File.open(tag_path, "w+")
            tag_file.puts "rdma-core-#{rel_ver}:"
            tag_file.puts ""
            tag_file.puts "Updates from version #{prev_ver}"
            if rel_type == :stable then
                tag_file.puts " * Backport fixes:"
            end
            tag_file.puts `git log HEAD ^#{git_prev_ver} --no-merges --format='   * %s'`
            tag_file.close()

            if rel_type == :major
                # For major, tag the current version first
                @repo.runGit("tag -a -s v#{rel_ver} --edit -F #{tag_path}")
                if $? != 0 then
                    raise("Failed to tag branch #{local_branch}")
                end
            end

            # Update version number in relevant files
            @repo.run("sed -i -e 's/\\(Version:[[:space:]]*\\)[0-9.]\\+/\\1#{new_ver}/g' redhat/rdma-core.spec suse/rdma-core.spec")
            @repo.run("sed -i -e 's/\\([sS][eE][tT](PACKAGE_VERSION[[:space:]]*\"\\)[0-9.]*\"/\\1#{new_ver}\"/g' CMakeLists.txt")

            @repo.run("cat <<EOF > debian/changelog.new
rdma-core (#{new_ver}-1) unstable; urgency=low

  * New upstream release.

 -- $(git config user.name) <$(git config user.email)>  $(date '+%a, %d %b %Y %T %z')

$(cat debian/changelog)
EOF
mv debian/changelog.new debian/changelog")
            # Add and commit
            @repo.runGit("add  redhat/rdma-core.spec suse/rdma-core.spec CMakeLists.txt debian/changelog")
            @repo.runGit("commit -m '#{commit_msg} #{new_ver}' --verbose --edit --signoff")
            if $? != 0 then
                raise("Failed to commit on branch #{local_branch}")
            end

            if rel_type == :stable
                @repo.runGit("tag -a -s v#{rel_ver} --edit -F #{tag_path}")
                if $? != 0 then
                    raise("Failed to tag branch #{local_branch}")
                end
            end
            `rm -f #{tag_path}`
        end
    end

    GitMaintain::registerCustom(RDMACoreBranch::REPO_NAME,
                                { GitMaintain::Branch => RDMACoreBranch })
end
