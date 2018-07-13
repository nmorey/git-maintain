Gem::Specification.new do |s|
  s.name        = 'git-maintain'
  s.version     = "0.1.1"
  s.date        = "2018-07-13"
  s.summary     = "Your ultimate script for maintaining stable branches."
  s.description = "Be lazy and let git-maintain do all the heavy lifting for maintaining stable branches.
Leaves you only with the essential: reviewing the selected patches and decide where they should go."
  s.authors     = ["Nicolas Morey-Chaisemartin"]
  s.email       = 'nmoreychaisemartin@suse.de'
  s.executables << 'git-maintain'
  s.files       = [
    "LICENSE",
    "README.md",
    "lib/branch.rb", "lib/common.rb", "lib/repo.rb", "lib/travis.rb",
    "lib/addons/RDMACore.rb",
    "git-maintain-completion.sh"
  ]
  s.homepage    =
    'https://github.com/nmorey/git-maintain'
  s.license       = 'MIT'
end
