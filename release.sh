#!/bin/bash

VER=$(grep -A 1 -- "---------" CHANGELOG | head -n 2 | tail -n 1 | awk '{ print $1}')
MAJOR=$(echo $VER | sed -e 's/\.[0-9]*$//')
MINOR=$(echo $VER | sed -e 's/.*\.\([0-9]*\)$/\1/')
N_MINOR=$(expr $MINOR + 1)
N_VER="$MAJOR.$N_MINOR"
CHANGES=$(cat CHANGELOG |
			  awk ' BEGIN {count=0} {if ($1 == "------------------") count++; if (count <= 2) print $0}')
tag_file=$(mktemp)
cat <<EOF  > $tag_file
git-maintain $VER

Changelog:
$CHANGES
EOF
git tag -a -s v$VER --edit -F $tag_file && (
	mv CHANGELOG CHANGELOG.old
	cat <<EOF > CHANGELOG
------------------
$N_VER
------------------

EOF
	cat CHANGELOG.old >> CHANGELOG
	rm CHANGELOG.old
	git commit CHANGELOG -m "Bump changelog version to $N_VER"
)
rm -f $tag_file
