Gem::Specification.new do |s|
  s.name        = 'git-maintain'
  s.version     = `git describe`.chomp().gsub(/^v/, "").gsub(/-([0-9]+)-g/, '-\1.g')
  s.date        = "2018-07-13"
  s.summary     = "Your ultimate script for maintaining stable branches."
  s.description = "Be lazy and let git-maintain do all the heavy lifting for maintaining stable branches.\n"+
                  "Leaves you only with the essential: reviewing the selected patches and decide where they should go."
  s.authors     = ["Nicolas Morey-Chaisemartin"]
  s.email       = 'nmoreychaisemartin@suse.de'
  s.executables << 'git-maintain'
  s.files       = [
    "LICENSE",
    "CHANGELOG",
    "README.md",
    "lib/branch.rb", "lib/common.rb", "lib/repo.rb", "lib/travis.rb",
    "lib/addons/RDMACore.rb",
    "git-maintain-completion.sh"
  ]
  s.homepage    =
    'https://github.com/nmorey/git-maintain'
  s.license       = 'MIT'
end
