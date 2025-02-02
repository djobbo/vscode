# ---------------------------------------------------------------------------------------------
#   Copyright (c) Microsoft Corporation. All rights reserved.
#   Licensed under the MIT License. See License.txt in the project root for license information.
# ---------------------------------------------------------------------------------------------
builtin autoload -Uz add-zsh-hook

# Prevent the script recursing when setting up
if [ -n "$VSCODE_SHELL_INTEGRATION" ]; then
	ZDOTDIR=$USER_ZDOTDIR
	builtin return
fi

# This variable allows the shell to both detect that VS Code's shell integration is enabled as well
# as disable it by unsetting the variable.
VSCODE_SHELL_INTEGRATION=1

# Only fix up ZDOTDIR if shell integration was injected (not manually installed) and has not been called yet
if [[ "$VSCODE_INJECTION" == "1" ]]; then
	if [[ $options[norcs] = off  && -f $USER_ZDOTDIR/.zshrc ]]; then
		VSCODE_ZDOTDIR=$ZDOTDIR
		ZDOTDIR=$USER_ZDOTDIR
		. $USER_ZDOTDIR/.zshrc
		ZDOTDIR=$VSCODE_ZDOTDIR
	fi

	if [[ -f $USER_ZDOTDIR/.zsh_history && -z HISTFILE ]]; then
		HISTFILE=$USER_ZDOTDIR/.zsh_history
	fi
fi

# Shell integration was disabled by the shell, exit without warning assuming either the shell has
# explicitly disabled shell integration as it's incompatible or it implements the protocol.
if [ -z "$VSCODE_SHELL_INTEGRATION" ]; then
	builtin return
fi

# The property (P) and command (E) codes embed values which require escaping.
# Backslashes are doubled. Non-alphanumeric characters are converted to escaped hex.
__vsc_escape_value() {
	builtin emulate -L zsh

	# Process text byte by byte, not by codepoint.
	builtin local LC_ALL=C str="$1" i byte token out=''

	for (( i = 0; i < ${#str}; ++i )); do
		byte="${str:$i:1}"

		# Backslashes must be doubled.
		if [ "$byte" = "\\" ]; then
			token="\\\\"
		# Conservatively pass alphanumerics through.
		elif [[ "$byte" == [0-9A-Za-z] ]]; then
			token="$byte"
		# Hex-encode anything else.
		# (Importantly including: semicolon, newline, and control chars).
		else
			token="\\x${(l:2::0:)$(( [##16] #byte ))}"
			#            | |  |       |/|/ |_____|
			#            | |  |       | |     |
			# left-pad --+ |  |       | |     +- the byte value of the character
			# two digits --+  |       | +------- in hexadecimal
			# with '0' -------+       +--------- with no prefix
		fi

		out+="$token"
	done

	builtin print -r "$out"
}

__vsc_in_command_execution="1"
__vsc_current_command=""

__vsc_prompt_start() {
	builtin printf '\e]633;A\a'
}

__vsc_prompt_end() {
	builtin printf '\e]633;B\a'
}

__vsc_update_cwd() {
	builtin printf '\e]633;P;Cwd=%s\a' "$(__vsc_escape_value "${PWD}")"
}

__vsc_command_output_start() {
	builtin printf '\e]633;C\a'
	builtin printf '\e]633;E;%s\a' "$(__vsc_escape_value "${__vsc_current_command}")"
}

__vsc_continuation_start() {
	builtin printf '\e]633;F\a'
}

__vsc_continuation_end() {
	builtin printf '\e]633;G\a'
}

__vsc_right_prompt_start() {
	builtin printf '\e]633;H\a'
}

__vsc_right_prompt_end() {
	builtin printf '\e]633;I\a'
}

__vsc_command_complete() {
	if [[ "$__vsc_current_command" == "" ]]; then
		builtin printf '\e]633;D\a'
	else
		builtin printf '\e]633;D;%s\a' "$__vsc_status"
	fi
	__vsc_update_cwd
}

if [[ -o NOUNSET ]]; then
	if [ -z "${RPROMPT-}" ]; then
		RPROMPT=""
	fi
fi
__vsc_update_prompt() {
	__vsc_prior_prompt="$PS1"
	__vsc_prior_prompt2="$PS2"
	__vsc_in_command_execution=""
	PS1="%{$(__vsc_prompt_start)%}$PS1%{$(__vsc_prompt_end)%}"
	PS2="%{$(__vsc_continuation_start)%}$PS2%{$(__vsc_continuation_end)%}"
	if [ -n "$RPROMPT" ]; then
		__vsc_prior_rprompt="$RPROMPT"
		RPROMPT="%{$(__vsc_right_prompt_start)%}$RPROMPT%{$(__vsc_right_prompt_end)%}"
	fi
}

__vsc_precmd() {
	local __vsc_status="$?"
	if [ -z "${__vsc_in_command_execution-}" ]; then
		# not in command execution
		__vsc_command_output_start
	fi

	__vsc_command_complete "$__vsc_status"
	__vsc_current_command=""

	# in command execution
	if [ -n "$__vsc_in_command_execution" ]; then
		# non null
		__vsc_update_prompt
	fi
}

__vsc_preexec() {
	PS1="$__vsc_prior_prompt"
	PS2="$__vsc_prior_prompt2"
	if [ -n "$RPROMPT" ]; then
		RPROMPT="$__vsc_prior_rprompt"
	fi
	__vsc_in_command_execution="1"
	__vsc_current_command=$1
	__vsc_command_output_start
}
add-zsh-hook precmd __vsc_precmd
add-zsh-hook preexec __vsc_preexec

if [[ $options[login] = off && $USER_ZDOTDIR != $VSCODE_ZDOTDIR ]]; then
	ZDOTDIR=$USER_ZDOTDIR
fi
