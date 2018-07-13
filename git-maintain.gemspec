Gem::Specification.new do |s|
  s.name        = 'git-maintain'
  s.version     = "0.1.0"
  s.version     = "#{s.version}-alpha-#{ENV['TRAVIS_BUILD_NUMBER']}" if ENV['TRAVIS']
  s.date        = "2018-07-13"
  s.summary     = "git-maintain is a single ruby script to deal with all the hassle of maintaining stable branches in a project."
  s.description = "The idea is to script most of the maintenance tasks so the maintainer can focus on just reviewing and not on writing up release notes, looking for commits and such."
  s.authors     = ["Nicolas Morey-Chaisemartin"]
  s.email       = 'nmoreychaisemartin@suse.de'
  s.executables << 'git-maintain'
  s.files       = ["lib/branch.rb", "lib/common.rb", "lib/repo.rb", "lib/travis.rb", "lib/addons/RDMACore.rb", "git-maintain-completion.sh" ]
  s.homepage    =
    'https://github.com/nmorey/git-maintain'
  s.license       = 'GPL-2.0'
end
