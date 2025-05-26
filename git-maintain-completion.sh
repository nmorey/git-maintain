export _GIT_MAINTAIN_CMD_AWK=$(([ -f /bin/awk ] && echo "/bin/awk") || echo "/usr/bin/awk")
export _GIT_MAINTAIN_CMD_SORT=$(([ -f /bin/sort ] && echo "/bin/sort") || echo "/usr/bin/sort")
export _GIT_MAINTAIN_CMD_GREP=$(([ -f /bin/egrep ] && echo "/bin/egrep") || echo "/usr/bin/egrep")
export _GIT_MAINTAIN_CMD_SED=$(([ -f /bin/sed ] && echo "/bin/sed") || echo "/usr/bin/sed")

_git_maintain_genoptlist(){
	local COMMAND=$*
	${COMMAND}  --help 2>&1 | \
		${_GIT_MAINTAIN_CMD_AWK} 'BEGIN { found = 0 } { if(found == 1) print $$0; if($$1 == "Options:") {found = 1}}' | \
		${_GIT_MAINTAIN_CMD_GREP} -E -e "^[[:space:]]*--" -e "^[[:space:]]*-[a-zA-Z0-9]" | \
		${_GIT_MAINTAIN_CMD_SED} -e 's/^[[:space:]]*//' -e 's/^-[^-], //' | \
		${_GIT_MAINTAIN_CMD_AWK} '{ print $1}' | \
		${_GIT_MAINTAIN_CMD_SED} -e 's/^\(.*\)\[no-\]\(.*$\)/\1\2\n\1no-\2/' | \
		${_GIT_MAINTAIN_CMD_SORT} -u
}
_complete_git_maintain_branch(){
	case $prev in
		-b|--branch-suffix)
			__gitcomp_nl "$(git maintain list_suffixes)"
			;;
		-v|--base-version)
			BRANCHES=
			__gitcomp_nl "$(git maintain list_branches)"
			;;
		-V|--version)
			# Extra arg expected but not completable
			__gitcomp_nl ""
			;;
	esac
}

_git_maintain_cp()
{
   local OPT_LIST=$(_git_maintain_genoptlist git maintain cp)

    case "$prev" in
		-c|--sha1);;
		*)
			__gitcomp_nl "$OPT_LIST"
	        _complete_git_maintain_branch
			;;
	esac;
}

_git_maintain_merge()
{
   local OPT_LIST=$(_git_maintain_genoptlist git maintain merge)
    _get_comp_words_by_ref cur

    case "$prev" in
		-m|--merge)
			__gitcomp_nl "$(git maintain list_suffixes)"
			;;
		*)
			__gitcomp_nl "$OPT_LIST"
	        _complete_git_maintain_branch
			;;
	esac;
}

_git_maintain(){
	local direct_call=${1:-1}
	local cmd_word=$(expr $direct_call + 1)

	__git_has_doubledash && return

	_get_comp_words_by_ref cur
	_get_comp_words_by_ref prev
	_get_comp_words_by_ref cword


	if [ $cword -eq $cmd_word ]; then
		case "$cur" in
			-*)
				__gitcomp_nl "$(_git_maintain_genoptlist git maintain)"
				return
				;;
			*)
				__gitcomp_nl "$(git maintain list_actions | grep -v list_actions)"
				return
				;;
		esac
    else
		_get_comp_words_by_ref words
		local cmd_name=${words[$cmd_word]}
		completion_func="_git_maintain_${cmd_name}"
		declare -f $completion_func > /dev/null
		 if [ $? -eq 0 ]; then
			 $completion_func
		 else
			 OPT_LIST=$(_git_maintain_genoptlist git maintain $cmd_name)
			 case "$prev" in
				 *)
					__gitcomp_nl "$OPT_LIST"
					# Override default completion with specific branch completion (if it matches)
					_complete_git_maintain_branch

			 esac
		 fi
	fi

}

__git_maintain(){
	_git_maintain 0
} && complete -F __git_maintain git-maintain
