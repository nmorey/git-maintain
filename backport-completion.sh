export _BACKPORT_CMD_AWK=$(([ -f /bin/awk ] && echo "/bin/awk") || echo "/usr/bin/awk")
export _BACKPORT_CMD_SORT=$(([ -f /bin/sort ] && echo "/bin/sort") || echo "/usr/bin/sort")
export _BACKPORT_CMD_EGREP=$(([ -f /bin/egrep ] && echo "/bin/egrep") || echo "/usr/bin/egrep")
export _BACKPORT_CMD_SED=$(([ -f /bin/sed ] && echo "/bin/sed") || echo "/usr/bin/sed")

_backport_genoptlist(){
	local COMMAND=$*
	${COMMAND}  --help 2>&1 | \
		${_BACKPORT_CMD_AWK} 'BEGIN { found = 0 } { if(found == 1) print $$0; if($$1 == "Options:") {found = 1}}' | \
		${_BACKPORT_CMD_EGREP} -e "^[[:space:]]*--" -e "^[[:space:]]*-[a-zA-Z0-9]" | \
		${_BACKPORT_CMD_SED} -e 's/^[[:space:]]*//' -e 's/^-[^-], //' | \
		${_BACKPORT_CMD_AWK} '{ print $1}' | \
		${_BACKPORT_CMD_SED} -e 's/^\(.*\)\[no-\]\(.*$\)/\1\2\n\1no-\2/' | \
		${_BACKPORT_CMD_SORT} -u
}
_complete_backport_branch(){
	local LAST=$1
	local cur=$2
	shift 2
	case $LAST in
		-b|--branch-suffix)
			SUFFIXES=$($cmd list_suffixes)
			compgen -W "$SUFFIXES" -- "$cur"
			;;
		-v|--base-version)
			BRANCHES=$(cmd list_branches)
			compgen -W "$BRANCHES" -- "$cur"
			;;
		*)
			echo $*
	esac
}

_complete_backport_cp()
{
   local cur
   local last
   local OPT_LIST=$(_backport_genoptlist $cmd cp)
    _get_comp_words_by_ref cur

    last=$((--COMP_CWORD))
    case "${COMP_WORDS[last]}" in
		-c|--sha1);;
		*)
	        COMPREPLY=( $(_complete_backport_branch "${COMP_WORDS[last]}" "$cur" \
													$(compgen -W "$OPT_LIST" -- "$cur")) )
			;;
	esac;
}

_complete_backport_merge()
{
   local cur
   local last
   local OPT_LIST=$(_backport_genoptlist $cmd merge)
    _get_comp_words_by_ref cur

    last=$((--COMP_CWORD))
    case "${COMP_WORDS[last]}" in
		-m|--merge)
			SUFFIXES=$($cmd list_suffixes)
			COMPREPLY=( $( compgen -W "$SUFFIXES" -- "$cur"))
			;;
		*)
	        COMPREPLY=( $(_complete_backport_branch "${COMP_WORDS[last]}" "$cur" \
													$(compgen -W "$OPT_LIST" -- "$cur")) )
			;;
	esac;
}

_complete_backport(){
    local cur
    local last
	local cmd=$1
	local OPT_LIST
	local CMD_LIST=$($1 list_actions | grep -v list_actions)

    _get_comp_words_by_ref cur
    last=$((COMP_CWORD - 1))
	if [ $last -eq 0 ]; then 
		case "${COMP_WORDS[1]}" in
			-*)
				OPT_LIST=$(_backport_genoptlist $cmd)
				COMPREPLY=( $( compgen -W "$OPT_LIST" -- "$cur") );;
			*)
	            COMPREPLY=( $( compgen -W "$CMD_LIST" -- "$cur") );;
		esac;
    else
		local cmd_name=${COMP_WORDS[1]}
		completion_func="_complete_backport_${cmd_name}"
		declare -f $completion_func > /dev/null
		 if [ $? -eq 0 ]; then
			 $completion_func
		 else
			 OPT_LIST=$(_backport_genoptlist $cmd $cmd_name)
			 case "${COMP_WORDS[last]}" in
				 *)
					 COMPREPLY=( $(compgen -W "$OPT_LIST" -- "$cur") );;
			 esac
		 fi
	fi

} && complete -F _complete_backport git-backport
