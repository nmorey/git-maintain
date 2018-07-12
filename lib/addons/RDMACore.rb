module Backport
    class RDMACoreBranch < Branch
        REPO_NAME = "rdma-core"

        def release(opts)
            prev_ver=@repo.runGit("show HEAD:CMakeLists.txt  | egrep \"[sS][eE][tT]\\\\(PACKAGE_VERSION\"").
                         chomp().gsub(/[sS][eE][tT]\(PACKAGE_VERSION\s*"([0-9.]*)".*$/, '\1')
            ver_nums = prev_ver.split(".")
            new_ver =  (ver_nums[0 .. -2] + [ver_nums[-1].to_i() + 1 ]).join(".")
            git_prev_ver = "v" + (ver_nums[-1] == "0" ? ver_nums[0 .. -2].join(".") : prev_ver)

            puts "Preparing release #{prev_ver} => #{new_ver}"
            rep = Backport::checkLog(opts, @local_branch, git_prev_ver, "release")
            if rep != "y" then
                puts "Skipping release"
                return
            end

            # Prepare tag message
            tag_path=`mktemp`.chomp()
            puts tag_path
            tag_file = File.open(tag_path, "w+")
            tag_file.puts "rdma-core-#{new_ver}:"
            tag_file.puts ""
            tag_file.puts "Updates from version #{prev_ver}"
            tag_file.puts " * Backport fixes:"
            tag_file.puts `git log HEAD ^#{git_prev_ver} --format='   * %s'`
            tag_file.close()

            # Update version number in relevant files
            @repo.run("sed -i -e 's/\\(Version:[[:space:]]*\\)[0-9.]*/\\1#{new_ver}/g' redhat/rdma-core.spec suse/rdma-core.spec")
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
            @repo.runGit("commit -m 'Bump to version #{new_ver}' --verbose --edit --signoff")
            if $? != 0 then
                raise("Failed to commit on branch #{local_branch}")
            end
            @repo.runGit("tag -a -s v#{new_ver} --edit -F #{tag_path}")
            if $? != 0 then
                raise("Failed to tag branch #{local_branch}")
            end
            `rm -f #{tag_path}`
        end
    end

    Backport::registerCustom(RDMACoreBranch::REPO_NAME, Backport::Repo, RDMACoreBranch)
end
