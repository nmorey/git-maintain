#!/bin/bash

VER=$(grep -A 1 -- "---------" CHANGELOG | head -n 2 | tail -n 1 | awk '{ print $1}')
MAJOR=$(echo $VER | sed -e 's/\.[0-9]*$//')
MINOR=$(echo $VER | sed -e 's/.*\.\([0-9]*\)$/\1/')
N_MINOR=$(expr $MINOR + 1)
N_VER="$MAJOR.$N_MINOR"
# Update release date
sed -i -e "s/$VER *$/$VER $(date '+ (%Y-%m-%d)')/" CHANGELOG

CHANGES=$(cat CHANGELOG |
			  awk ' BEGIN {count=0} {if ($1 == "------------------") count++; if (count <= 2) print $0}')

mv CHANGELOG CHANGELOG.old
cat <<EOF > CHANGELOG
------------------
$N_VER
------------------

EOF
cat CHANGELOG.old >> CHANGELOG
rm CHANGELOG.old

tag_file=$(mktemp)
cat <<EOF  > $tag_file
git-maintain $VER

Changelog:
$CHANGES
EOF

git commit CHANGELOG -F $tag_file --edit &&
	git tag -a -s v$VER --edit -F $tag_file
rm -f $tag_file
