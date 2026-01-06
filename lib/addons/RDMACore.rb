module GitMaintain
    class RDMACoreBranch < Branch
        REPO_NAME = "rdma-core"
        AZURE_MIN_VERSION = 18
        ACTION_LIST = Branch::ACTION_LIST + [ :validate ]
        ACTION_HELP = {
            :validate => "Validate that branch still builds"
        }.merge(Branch::ACTION_HELP)

        def self.set_opts(action, optsParser, opts)
            opts[:rel_type] = nil

            case action
            when :release
                 optsParser.on("--major", "Release a major version.") {
                     opts[:rel_type] = :major }
                 optsParser.on("--stable", "Release a stable version.") {
                     opts[:rel_type] = :stable }
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
            prev_ver=@repo.runGit("show HEAD:CMakeLists.txt  | grep -E \"[sS][eE][tT]\\\\(PACKAGE_VERSION\"").
                         chomp().gsub(/[sS][eE][tT]\(PACKAGE_VERSION\s*"([0-9.]*)".*$/, '\1')
            ver_nums = prev_ver.split(".")
            new_ver =  (ver_nums[0 .. -2] + [ver_nums[-1].to_i() + 1 ]).join(".")
            rel_ver = new_ver
            commit_msg = "Bump to version"

            if opts[:rel_type] == :major
                new_ver = ([ ver_nums[0].to_i() + 1] + ver_nums[1 .. -1]).join(".")
                rel_ver = prev_ver
                prev_ver = ([ ver_nums[0].to_i() - 1] + ver_nums[1 .. -1]).join(".")
                ver_nums = prev_ver.split(".")
                commit_msg ="Update library version to be"
            end

            git_prev_ver = "v" + prev_ver
            # Older tags might do have the terminal minor version (.0) for major releases
            begin
                @repo.ref_exist?(git_prev_ver)
            rescue NoRefError
                # Try without the minor version number
                git_prev_ver = "v" + ver_nums[0 .. -2].join(".")
            end

            puts "Preparing #{opts[:rel_type].to_s} release #{prev_ver} => #{rel_ver}"
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
            if opts[:rel_type] == :stable then
                tag_file.puts " * Backport fixes:"
            end
            tag_file.puts `git log HEAD ^#{git_prev_ver} --no-merges --format='   * %s'`
            tag_file.close()

            edit_flag = ""
            edit_flag = "--edit" if opts[:no_edit] == false

            if opts[:rel_type] == :major
                # For major, tag the current version first
                release_do_tag(opts, "v" + rel_ver, tag_path)
            end

            # Update version number in relevant files
            @repo.run("sed -i -e 's/\\(Version:[[:space:]]*\\)[0-9.]\\+/\\1#{new_ver}/g' */*.spec")
            @repo.run("sed -i -e 's/\\([sS][eE][tT](PACKAGE_VERSION[[:space:]]*\"\\)[0-9.]*\"/\\1#{new_ver}\"/g' CMakeLists.txt")

            case opts[:rel_type]
            when :stable
                @repo.run("cat <<EOF > debian/changelog.new
rdma-core (#{new_ver}-1) unstable; urgency=low

  * New upstream release.

 -- $(git config user.name) <$(git config user.email)>  $(date '+%a, %d %b %Y %T %z')

$(cat debian/changelog)
EOF
mv debian/changelog.new debian/changelog")
            when :major
                @repo.run("sed -i -e 's/^rdma-core (#{rel_ver}-1)/rdma-core (#{new_ver}-1)/' debian/changelog")
            end

            # Add and commit
            release_do_add_commit(opts, [ "*/*.spec", "CMakeLists.txt", "debian/changelog" ],
                                  nil, "#{commit_msg} #{new_ver}")

            if opts[:rel_type] == :stable
                release_do_tag(opts, "v" + rel_ver, tag_path)
            end
            `rm -f #{tag_path}`
            return 0
        end
        def validate(opts)
            begin
                @repo.runSystem("rm -Rf build/ && mkdir build/ && cd build/ && cmake .. && make -j")
            rescue RuntimeError
                raise("Validation failure")
            end
        end
    end
    class RDMACoreRepo < Repo
        AZURE_MIN_VERSION = 18
        ACTION_LIST = Repo::ACTION_LIST + [ :create_stable ]
        ACTION_HELP = {
            :create_stable => "Create a stable branch from a release tag"
        }.merge(Repo::ACTION_HELP)

        def submitReleases(opts, new_tags)
            new_tags.each(){|tag|
                next if tag !~ /v([0-9]*)\.[0-9]*/
                major=$1.to_i
                # Starting from v27, do not create the github release ourself as this is done by Azure
                createRelease(opts, tag, major < AZURE_MIN_VERSION)
            }
        end

        def self.set_opts(action, optsParser, opts)
            case action
            when :create_stable then
                optsParser.on("-V", "--version [NUM]", Integer,
                              "Specify which version to use to create the stable branch.") {
                |val| opts[:version] = val}
                optsParser.on("-S", "--skip",
                              "Skip docker image generation") {
                |val| opts[:skip_docker] = true}
            end
        end
        def self.check_opts(opts)
            case opts[:action]
                when :create_stable
                if opts[:version].to_s() == "" then
                    raise "Action #{opts[:action]} requires a branch number to be specified"
                end
                 if opts[:br_suff] != "master" then
                    raise "Action #{opts[:action]} can only be done on 'master' suffixed branches"
                end
           end
        end
        def create_stable(opts)
            ver = opts[:version].to_s()
            suff = opts[:br_suff]
            if getBranchList(suff).index(ver) != nil then
                raise("Local branch already exists for version #{ver}")
            end
            br = versionToLocalBranch(ver, suff)
            full_ver = ver.gsub(/([0-9]+)/, @stable_base_format)
            runGit("checkout -B #{br} #{full_ver}")
            cmdList = `awk '/\`\`\`/{p=!p; next};p' Documentation/stable.md`.chomp().split("\n")
            if opts[:skip_docker] == true then
                cmdList = cmdList.map(){|x| x if x !~ /build-images/}.compact()
            end
            cmdList = cmdList.map(){|x| (x !~ /pkg azp/) ? x : (x + " || true") }.compact()
            cmdList << "./buildlib/cbuild pkg azp"

            toDo=cmdList.join("&&")
            begin
                runSystem(toDo)
            rescue RuntimeError
                raise("Fail to run stable creation code")
            end
        end
    end

    class RDMACoreCI < CI
        AZURE_MIN_VERSION = 18
        def initialize(repo)
            super(repo)
            @travis = GitMaintain::TravisCI.new(repo)
            @azure = GitMaintain::AzureCI.new(repo, 'ucfconsort', 'ucfconsort')

            # Auto generate all CI required methods
            # Wicked ruby tricker to find all the public methods of CI but not of inherited classes
            # to dynamically define these method in the object being created
            (GitMaintain::CI.new(repo).public_methods() - Object.new.public_methods()).each(){|method|
                # Skip specific emptyCache method
                next if method == :emptyCache

                self.define_singleton_method(method) { |br, *args|
                    if br.version =~ /([0-9]+)/
                        major=$1.to_i
                    elsif br.version == "master" 
                        major=99999
                    else
                        raise("Unable to monitor branch #{br} on a CI")
                    end
                    if major < AZURE_MIN_VERSION
                        @travis.send(method, br, *args)
                    else
                        @azure.send(method, br, *args)
                    end
                }
            }
        end
        def emptyCache()
            @travis.emptyCache()
            @azure.emptyCache()
        end
    end
    GitMaintain::registerCustom(RDMACoreBranch::REPO_NAME,
                                {
                                    GitMaintain::Branch => RDMACoreBranch,
                                    GitMaintain::Repo => RDMACoreRepo,
                                    GitMaintain::CI => RDMACoreCI,
                                })
end
