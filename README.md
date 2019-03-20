git-maintain is a simple ruby script to deal with all the hassle of maintaining stable branches in a project.

The idea is to script most of the maintenance tasks so the maintainer can focus on just reviewing and not on writing up release notes, looking for commits and such.

- Note: the workflow is highly inspired to the git-topic-branches (https://github.com/nmorey/git-topic-branches)
  and both can be used at the same time
- Note2: Releasing on github is done through github-release gem (https://github.com/mpalmer/github-release)

# Command summary

- **cp**: Backport commits and eventually push them to github
- **create**: Create missing local branches from all the stable branches
- **steal**: Steal commit from upstream that fixes commit in the branch or were tagged as stable
- **list**: List commit present in the branch but not in the stable branch
- **list_stable**: List commit present in the stable branch but not in the latest associated relase
- **merge**: Merge branch with suffix specified in -m <suff> into the main branch
- **push**: Push branches to github for validation
- **monitor**: Check the travis state of all branches
- **push_stable**: Push to stable repo
- **monitor_stable**: Check the travis state of all stable branches
- **release**: Create new release on all concerned branches
- **reset**: Reset branch against upstream
- **submit_release**: Push the to stable and create the release packages

# Configuration

## Basic shell setup
- git-maintain should be in your path
- Load git-maintain-completion.sh for shell completion

## Remote setup
- the 'github' remote should be your own WIP github to test out branches before submitting to the official repo.
  Also know as the 'Validation' repo. It can be switched to another remote by setting maintain.valid-repo=xxx in your gitconfig
- the 'origin' remote should be the official repo in read-only mode to avoid any accidental pushes
- the 'stable' remote should be the official repo in RW mode
  Also know as the 'Stable' repo. It can be switched to another remote by setting maintain.stable-repo=xxx in your gitconfig

## Stealing commits

The steal feature uses was shamelessly copied it from https://git.kernel.org/pub/scm/linux/kernel/git/sashal/stable-tools.git/tree/

## Making releases
The release process being very specific to each project, the release command does nothing by default.
However the behaviour can be overriden for specific repo (detected by repo name)

Check the lib/addons/RDMACore.rb for an example.
In this case, the release command bump the version in all the appropriate files (after computing the previous and next version numbers), commit and tags the commit.


# How do I use it

## Branch setup
As said, this uses the branching schemes recommended/compatible of git-topic-branches.

A non compulsory recommendation is to create
I personnaly uses this scheme for my rdma-core work:
```
$ git branch
dev/stable-v15/master
dev/stable-v15/pending
dev/stable-v16/master
dev/stable-v16/pending
dev/stable-v17/master
dev/stable-v17/pending
dev/stable-v17/test
dev/stable-v18/master
dev/stable-v18/pending
* dev/stable-v19/master
```

I also use the git-topic-branches features:
```
git config --get-regexp devel-base
devel-base.dev---stable-v19 origin/stable-v19
devel-base.dev---stable-v18 origin/stable-v18
devel-base.dev---stable-v17 origin/stable-v17
devel-base.dev---stable-v16 origin/stable-v16
devel-base.dev---stable-v15 origin/stable-v15
```
This allows me to:
- autorebase on the stable branches. This is useful for dealing with development branches for stable branches
- Detect when all my patches have made it to the upstream repo

I also set the right config value for the 'steal' command to work
```
$ git config --get-regexp stable-base
stable-base.dev---stable-v19 v19
stable-base.dev---stable-v18 v18
stable-base.dev---stable-v17 v17
stable-base.dev---stable-v16 v16
stable-base.dev---stable-v15 v15
```
This will allow 'git maintain steal' to figure out what should be backported in the stable branches.


You know can use a regexp for dealing with branch names that extends with version
 without any changes to your .gitconfig

Configure your local branch name space that also extracts the version:
```
$ git config --get maintain.branch-format
dev\/stable-v([0-9]*)
```

Configure the upstream stable branches. Use ruby regexp value extraction (\\1) so git-maintain
cal automatically insert the right version number
```
$ git config --get maintain.stable-branch-format
stable-v\1

```
Finally configure the upstream fork points for stable branches so the `steal` commands know where to start from
```
$ git config --get maintain.stable-base-format
v\1

```

Note that this value can be overriden by the stable-base.XXX value if needed

Also, once you set these parameters, you can have git-maintain create all branches for you by running
``
$ git maintain create
```
## Day-to-day workflow

Watch the mailing-lists (and/or github and/or the upstream branches) for patches that are tagged for maintainance.
Apply them to the appropriate branches

```git maintain cp -s deadbeef --version '1[789]'```

And push them to my own github repo so that Travis will check everything out

```git maintain push --version '1[789]'```

Some time later, check their status

```git maintain monitor --version '1[789]'```

If everything looks good, push to the stable repo

```git maintain push_stable --version '1[789]'```

If patches have been sent to the ML but are not yet accepted, I usually try them out on a "pending" branch.

```git maintain cp -s deadbeef --version '1[789]' -b pending```

Note that it is your own job to create the branches (yet!)

Push it to my own github too.

```git maintain push --version '1[789]' -b pending```

Once this gets accepted (and Travis is OK too), I merge this branch back to my 'master'

```git maintain merge --version '1[789]' -m pending```

The default -b option here is master so it is not required to specify it. Also branch suffixed with something else than master cannot be pushed to stable branches for safety reasons.

If this is all broken and the patch should not be applied, I simply reset my branch

```git maintain reset --version '1[789]' -m pending```

Note: This has been made as safe as possible and is querying you before doing anything destructive.

## Stealing commits

This uses a ruby version of the 'steal-stable-commits' script originally available here https://git.kernel.org/pub/scm/linux/kernel/git/sashal/stable-tools.git/tree/

It allows to automatically cherry-pick commits that have been marked as fixing a bug in your branch.

What it does is parse the master branch for commits that contains the standard

```Fixes: deadbeef00 ("broken commit msg")```

It will then check if the broken commit is in your branch (and not already fixed). It will then prompt you for reviewing the fix and apply it on your local stable branch.

If the developers from your project follow this, it removes a lot of the hassle of finding which patch applies to which branches, It will do it for you !

You can get more infos on how all this works here: https://git.kernel.org/pub/scm/linux/kernel/git/sashal/stable-tools.git/tree/README (stable steal-commits section).

One of the added feature is the ability to blacklist a commit for certain branch.
(Useful when there is a commit broken in your stable branch but the fix breaks the ABI or simply won't apply.)

Blacklisting the fix (for a specific branch) will prevent it from ever popping up when stealing commits.
Blacklisting is done through git-notes. It attaches a note to the "fix" commit in master and simply add the name of the branch it is blacklisted in. To run-blacklist the commit, edit the note and remove the branch name.

Note that blacklisted commites will show an info message when skipped so you don't have to dig through all the notes to find which one you wanted.

To run:

```git maintain steal```


## Releases

Once some work has been done, it is time for a new release.

First, unless you're working for the rdma-core repo, you'll need to add your own 'add-on' class to do automatize tyour release process. Please look at 'addons/RDMACore.rb' for an example.

Then all you need to do is create your release(s)

```git maintain release --version '1[789]'```

This will run your addon code. What you usually want to do in there is create a tag and eventually bump version numbers, add releases notes, etc.

I strongly advise here to then use the 'push_stable' command. It will update the branches, but NOT push the tag.
This means that if something has been broken by the release commit (if any), there is still time to fix it.

The tag will not have been propagated anywhere else and can be deleted manually.

```git maintain push_stable --version '1[789]'```

You can then monitor the status on Travis

```git maintain monitor_stable --version '1[789]'```


Once everything is green, it is time to submit your release

```git maintain submit_release --version '1[789]'```

This will submit the all pending tags to github, and prepare an email for the project mailing list (requires the 'patch.target' option from git-topic-branches)

Review your email, send it and your day is over !

Enjoy, and feel free to report bugs, missing features and/or send patches

