Gem::Specification.new do |s|
  s.name        = 'git-maintain'
  s.version     = `git describe --tags`.chomp().gsub(/^v/, "").gsub(/-([0-9]+)-g/, '-\1.g')
  s.date        = `git show HEAD --format='format:%ci' -s | awk '{ print $1}'`.chomp()
  s.summary     = "Your ultimate script for maintaining stable branches and releasing your project."
  s.description = "Be lazy and let git-maintain do all the heavy lifting for maintaining stable branches.\n"+
                  "Leaves you only with the essential: reviewing the selected patches and decide where they should go."
  s.authors     = ["Nicolas Morey-Chaisemartin"]
  s.email       = 'nmoreychaisemartin@suse.de'
  s.executables << 'git-maintain'
  s.files       = [
    "LICENSE",
    "CHANGELOG",
    "README.md",
    "lib/addons/RDMACore.rb",
    "lib/addons/git-maintain.rb",
    "git-maintain-completion.sh"
  ] + Dir['lib/*.rb'].keep_if { |file| File.file?(file) }
  s.homepage    =
    'https://github.com/nmorey/git-maintain'
  s.license       = 'GPL-3.0'
  if (RUBY_VERSION < '2.7.0')
      s.add_dependency 'octokit', '>= 3.0', '< 5'
  else
      s.add_dependency 'octokit', '~> 5.0'
  end
end
