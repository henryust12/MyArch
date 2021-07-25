#!/bin/sh

PROGRESS_CURR=0
PROGRESS_TOTAL=3194                        

# This file was autowritten by rmlint
# rmlint was executed from: /home/shima/
# Your command line was: rmlint /home/shima/

RMLINT_BINARY="/usr/bin/rmlint"

# Only use sudo if we're not root yet:
# (See: https://github.com/sahib/rmlint/issues/27://github.com/sahib/rmlint/issues/271)
SUDO_COMMAND="sudo"
if [ "$(id -u)" -eq "0" ]
then
  SUDO_COMMAND=""
fi

USER='shima'
GROUP='shima'

# Set to true on -n
DO_DRY_RUN=

# Set to true on -p
DO_PARANOID_CHECK=

# Set to true on -r
DO_CLONE_READONLY=

# Set to true on -q
DO_SHOW_PROGRESS=true

# Set to true on -c
DO_DELETE_EMPTY_DIRS=

# Set to true on -k
DO_KEEP_DIR_TIMESTAMPS=

# Set to true on -i
DO_ASK_BEFORE_DELETE=

##################################
# GENERAL LINT HANDLER FUNCTIONS #
##################################

COL_RED='[0;31m'
COL_BLUE='[1;34m'
COL_GREEN='[0;32m'
COL_YELLOW='[0;33m'
COL_RESET='[0m'

print_progress_prefix() {
    if [ -n "$DO_SHOW_PROGRESS" ]; then
        PROGRESS_PERC=0
        if [ $((PROGRESS_TOTAL)) -gt 0 ]; then
            PROGRESS_PERC=$((PROGRESS_CURR * 100 / PROGRESS_TOTAL))
        fi
        printf '%s[%3d%%]%s ' "${COL_BLUE}" "$PROGRESS_PERC" "${COL_RESET}"
        if [ $# -eq "1" ]; then
            PROGRESS_CURR=$((PROGRESS_CURR+$1))
        else
            PROGRESS_CURR=$((PROGRESS_CURR+1))
        fi
    fi
}

handle_emptyfile() {
    print_progress_prefix
    echo "${COL_GREEN}Deleting empty file:${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        rm -f "$1"
    fi
}

handle_emptydir() {
    print_progress_prefix
    echo "${COL_GREEN}Deleting empty directory: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        rmdir "$1"
    fi
}

handle_bad_symlink() {
    print_progress_prefix
    echo "${COL_GREEN} Deleting symlink pointing nowhere: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        rm -f "$1"
    fi
}

handle_unstripped_binary() {
    print_progress_prefix
    echo "${COL_GREEN} Stripping debug symbols of: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        strip -s "$1"
    fi
}

handle_bad_user_id() {
    print_progress_prefix
    echo "${COL_GREEN}chown ${USER}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chown "$USER" "$1"
    fi
}

handle_bad_group_id() {
    print_progress_prefix
    echo "${COL_GREEN}chgrp ${GROUP}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chgrp "$GROUP" "$1"
    fi
}

handle_bad_user_and_group_id() {
    print_progress_prefix
    echo "${COL_GREEN}chown ${USER}:${GROUP}${COL_RESET} $1"
    if [ -z "$DO_DRY_RUN" ]; then
        chown "$USER:$GROUP" "$1"
    fi
}

###############################
# DUPLICATE HANDLER FUNCTIONS #
###############################

check_for_equality() {
    if [ -f "$1" ]; then
        # Use the more lightweight builtin `cmp` for regular files:
        cmp -s "$1" "$2"
        echo $?
    else
        # Fallback to `rmlint --equal` for directories:
        "$RMLINT_BINARY" -p --equal  "$1" "$2"
        echo $?
    fi
}

original_check() {
    if [ ! -e "$2" ]; then
        echo "${COL_RED}^^^^^^ Error: original has disappeared - cancelling.....${COL_RESET}"
        return 1
    fi

    if [ ! -e "$1" ]; then
        echo "${COL_RED}^^^^^^ Error: duplicate has disappeared - cancelling.....${COL_RESET}"
        return 1
    fi

    # Check they are not the exact same file (hardlinks allowed):
    if [ "$1" = "$2" ]; then
        echo "${COL_RED}^^^^^^ Error: original and duplicate point to the *same* path - cancelling.....${COL_RESET}"
        return 1
    fi

    # Do double-check if requested:
    if [ -z "$DO_PARANOID_CHECK" ]; then
        return 0
    else
        if [ "$(check_for_equality "$1" "$2")" -ne "0" ]; then
            echo "${COL_RED}^^^^^^ Error: files no longer identical - cancelling.....${COL_RESET}"
            return 1
        fi
    fi
}

cp_symlink() {
    print_progress_prefix
    echo "${COL_YELLOW}Symlinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            # replace duplicate with symlink
            rm -rf "$1"
            ln -s "$2" "$1"
            # make the symlink's mtime the same as the original
            touch -mr "$2" -h "$1"
        fi
    fi
}

cp_hardlink() {
    if [ -d "$1" ]; then
        # for duplicate dir's, can't hardlink so use symlink
        cp_symlink "$@"
        return $?
    fi
    print_progress_prefix
    echo "${COL_YELLOW}Hardlinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            # replace duplicate with hardlink
            rm -rf "$1"
            ln "$2" "$1"
        fi
    fi
}

cp_reflink() {
    if [ -d "$1" ]; then
        # for duplicate dir's, can't clone so use symlink
        cp_symlink "$@"
        return $?
    fi
    print_progress_prefix
    # reflink $1 to $2's data, preserving $1's  mtime
    echo "${COL_YELLOW}Reflinking to original: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            touch -mr "$1" "$0"
            if [ -d "$1" ]; then
                rm -rf "$1"
            fi
            cp --archive --reflink=always "$2" "$1"
            touch -mr "$0" "$1"
        fi
    fi
}

clone() {
    print_progress_prefix
    # clone $1 from $2's data
    # note: no original_check() call because rmlint --dedupe takes care of this
    echo "${COL_YELLOW}Cloning to: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        if [ -n "$DO_CLONE_READONLY" ]; then
            $SUDO_COMMAND $RMLINT_BINARY --dedupe  --dedupe-readonly "$2" "$1"
        else
            $RMLINT_BINARY --dedupe  "$2" "$1"
        fi
    fi
}

skip_hardlink() {
    print_progress_prefix
    echo "${COL_BLUE}Leaving as-is (already hardlinked to original): ${COL_RESET}$1"
}

skip_reflink() {
    print_progress_prefix
    echo "${COL_BLUE}Leaving as-is (already reflinked to original): ${COL_RESET}$1"
}

user_command() {
    print_progress_prefix

    echo "${COL_YELLOW}Executing user command: ${COL_RESET}$1"
    if [ -z "$DO_DRY_RUN" ]; then
        # You can define this function to do what you want:
        echo 'no user command defined.'
    fi
}

remove_cmd() {
    print_progress_prefix
    echo "${COL_YELLOW}Deleting: ${COL_RESET}$1"
    if original_check "$1" "$2"; then
        if [ -z "$DO_DRY_RUN" ]; then
            if [ -n "$DO_KEEP_DIR_TIMESTAMPS" ]; then
                touch -r "$(dirname "$1")" "$STAMPFILE"
            fi
            if [ -n "$DO_ASK_BEFORE_DELETE" ]; then
              rm -ri "$1"
            else
              rm -rf "$1"
            fi
            if [ -n "$DO_KEEP_DIR_TIMESTAMPS" ]; then
                # Swap back old directory timestamp:
                touch -r "$STAMPFILE" "$(dirname "$1")"
                rm "$STAMPFILE"
            fi

            if [ -n "$DO_DELETE_EMPTY_DIRS" ]; then
                DIR=$(dirname "$1")
                while [ ! "$(ls -A "$DIR")" ]; do
                    print_progress_prefix 0
                    echo "${COL_GREEN}Deleting resulting empty dir: ${COL_RESET}$DIR"
                    rmdir "$DIR"
                    DIR=$(dirname "$DIR")
                done
            fi
        fi
    fi
}

original_cmd() {
    print_progress_prefix
    echo "${COL_GREEN}Keeping:  ${COL_RESET}$1"
}

##################
# OPTION PARSING #
##################

ask() {
    cat << EOF

This script will delete certain files rmlint found.
It is highly advisable to view the script first!

Rmlint was executed in the following way:

   $ rmlint /home/shima/

Execute this script with -d to disable this informational message.
Type any string to continue; CTRL-C, Enter or CTRL-D to abort immediately
EOF
    read -r eof_check
    if [ -z "$eof_check" ]
    then
        # Count Ctrl-D and Enter as aborted too.
        echo "${COL_RED}Aborted on behalf of the user.${COL_RESET}"
        exit 1;
    fi
}

usage() {
    cat << EOF
usage: $0 OPTIONS

OPTIONS:

  -h   Show this message.
  -d   Do not ask before running.
  -x   Keep rmlint.sh; do not autodelete it.
  -p   Recheck that files are still identical before removing duplicates.
  -r   Allow deduplication of files on read-only btrfs snapshots. (requires sudo)
  -n   Do not perform any modifications, just print what would be done. (implies -d and -x)
  -c   Clean up empty directories while deleting duplicates.
  -q   Do not show progress.
  -k   Keep the timestamp of directories when removing duplicates.
  -i   Ask before deleting each file
EOF
}

DO_REMOVE=
DO_ASK=

while getopts "dhxnrpqcki" OPTION
do
  case $OPTION in
     h)
       usage
       exit 0
       ;;
     d)
       DO_ASK=false
       ;;
     x)
       DO_REMOVE=false
       ;;
     n)
       DO_DRY_RUN=true
       DO_REMOVE=false
       DO_ASK=false
       DO_ASK_BEFORE_DELETE=false
       ;;
     r)
       DO_CLONE_READONLY=true
       ;;
     p)
       DO_PARANOID_CHECK=true
       ;;
     c)
       DO_DELETE_EMPTY_DIRS=true
       ;;
     q)
       DO_SHOW_PROGRESS=
       ;;
     k)
       DO_KEEP_DIR_TIMESTAMPS=true
       STAMPFILE=$(mktemp 'rmlint.XXXXXXXX.stamp')
       ;;
     i)
       DO_ASK_BEFORE_DELETE=true
       ;;
     *)
       usage
       exit 1
  esac
done

if [ -z $DO_REMOVE ]
then
    echo "#${COL_YELLOW} ///${COL_RESET}This script will be deleted after it runs${COL_YELLOW}///${COL_RESET}"
fi

if [ -z $DO_ASK ]
then
  usage
  ask
fi

if [ -n "$DO_DRY_RUN" ]
then
    echo "#${COL_YELLOW} ////////////////////////////////////////////////////////////${COL_RESET}"
    echo "#${COL_YELLOW} /// ${COL_RESET} This is only a dry run; nothing will be modified! ${COL_YELLOW}///${COL_RESET}"
    echo "#${COL_YELLOW} ////////////////////////////////////////////////////////////${COL_RESET}"
fi

######### START OF AUTOGENERATED OUTPUT #########

handle_emptydir '/home/shima/Videos' # empty folder
handle_emptydir '/home/shima/Templates/Imported_Templates' # empty folder
handle_emptydir '/home/shima/Pictures/Screen Shots' # empty folder
handle_emptyfile '/home/shima/Documents/tsb-java/PortableGit/usr/share/pki/ca-trust-legacy/ca-bundle.legacy.disable.crt' # empty file
handle_emptyfile '/home/shima/Documents/tsb-java/PortableGit/etc/pki/ca-trust/extracted/pem/objsign-ca-bundle.pem' # empty file
handle_emptyfile '/home/shima/Documents/tsb-java/PortableGit/usr/share/pki/ca-trust-legacy/ca-bundle.legacy.default.crt' # empty file
handle_emptyfile '/home/shima/Documents/tsb-java/PortableGit/mingw64/etc/pki/ca-trust/extracted/pem/objsign-ca-bundle.pem' # empty file
handle_emptyfile '/home/shima/Documents/tsb-java/python/2021.06.24/Sample05.py' # empty file
handle_emptyfile '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/pki/ca-trust-legacy/ca-bundle.legacy.default.crt' # empty file
handle_emptyfile '/home/shima/Documents/tsb-java/python/2021.07.01/script-ran.py' # empty file
handle_emptyfile '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/pki/ca-trust-legacy/ca-bundle.legacy.disable.crt' # empty file

original_cmd  '/home/shima/fonts.scale' # original
remove_cmd    '/home/shima/fonts.dir' '/home/shima/fonts.scale' # duplicate

original_cmd  '/home/shima/VirtualBox VMs/Rocky/Rocky.vbox-prev' # original
remove_cmd    '/home/shima/VirtualBox VMs/Rocky/Rocky.vbox' '/home/shima/VirtualBox VMs/Rocky/Rocky.vbox-prev' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/xzegrep' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/xzfgrep' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/xzegrep' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/xzgrep' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/xzegrep' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/xzcmp' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/xzdiff' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/xzcmp' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/update-ca-trust' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/p11-kit/p11-kit-extract-trust' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/update-ca-trust' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tclConfig.sh' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8/tclConfig.sh' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tclConfig.sh' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tk8.6/images/logo100.gif' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tk8.6/demos/images/tcllogo.gif' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tk8.6/images/logo100.gif' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/Atlassian.Bitbucket.UI.exe.config' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/GitHub.UI.exe.config' '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/Atlassian.Bitbucket.UI.exe.config' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-credential-manager-core.exe.config' '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/Atlassian.Bitbucket.UI.exe.config' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/doc/xz/COPYING.GPLv2' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/xz/COPYING.GPLv2' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/doc/xz/COPYING.GPLv2' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/doc/xz/COPYING' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/xz/COPYING' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/doc/xz/COPYING' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/gettext/gettext-runtime/libasprintf/COPYING.LIB' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/gettext/gettext-runtime/intl/COPYING.LIB' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/gettext/gettext-runtime/libasprintf/COPYING.LIB' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libiconv/libcharset/COPYING.LIB' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libiconv/COPYING.LIB' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libiconv/libcharset/COPYING.LIB' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzegrep' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzfgrep' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzegrep' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzgrep' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzegrep' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bzegrep' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzegrep' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bzfgrep' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzegrep' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bzgrep' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzegrep' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzcmp' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzdiff' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzcmp' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bzcmp' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzcmp' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bzdiff' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzcmp' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/gettext.sh' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/gettext.sh' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/gettext.sh' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/perl.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/perl5.32.1.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/perl.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/gunzip' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/uncompress' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/gunzip' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/reset.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/tset.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/reset.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/tclsh.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/tclsh8.6.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/tclsh.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/mergetools/gvimdiff' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/mergetools/nvimdiff' '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/mergetools/gvimdiff' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso2022-jp.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso2022-jp.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso2022-jp.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/ebcdic.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/ebcdic.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/ebcdic.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/update-ca-trust' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/p11-kit/p11-kit-extract-trust' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/update-ca-trust' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-16.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-16.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-16.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1258.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp1258.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1258.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/gb1988.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/gb1988.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/gb1988.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1255.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp1255.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1255.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1256.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp1256.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1256.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/koi8-r.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/koi8-r.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/koi8-r.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1257.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp1257.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1257.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1250.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp1250.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1250.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1251.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp1251.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1251.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1252.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp1252.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1252.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1254.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp1254.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1254.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/symbol.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/symbol.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/symbol.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1253.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp1253.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp1253.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/koi8-u.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/koi8-u.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/koi8-u.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/http1.0/http.tcl' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/http1.0/http.tcl' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/http1.0/http.tcl' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/http1.0/pkgIndex.tcl' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/http1.0/pkgIndex.tcl' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/http1.0/pkgIndex.tcl' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/bg.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/bg.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/bg.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/af.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/af.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/af.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-14.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-14.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-14.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macTurkish.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macTurkish.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macTurkish.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macIceland.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macIceland.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macIceland.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-13.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-13.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-13.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-10.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-10.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-10.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macUkraine.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macUkraine.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macUkraine.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macRomania.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macRomania.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macRomania.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-15.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-15.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-15.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ca.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ca.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ca.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/bn.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/bn.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/bn.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/de.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/de.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/de.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/de_be.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/de_be.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/de_be.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/history.tcl' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/history.tcl' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/history.tcl' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/el.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/el.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/el.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_in.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_in.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_in.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_za.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_za.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_za.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_au.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_au.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_au.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_nz.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_nz.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_nz.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/et.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/et.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/et.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/eu.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/eu.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/eu.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fa_ir.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/fa_ir.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fa_ir.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fa_in.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/fa_in.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fa_in.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fi.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/fi.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fi.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fr_ch.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/fr_ch.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fr_ch.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/he.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/he.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/he.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/hi.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/hi.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/hi.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fa.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/fa.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fa.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/hr.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/hr.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/hr.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/hu.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/hu.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/hu.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/id.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/id.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/id.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ko.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ko.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ko.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kok_in.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/kok_in.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kok_in.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/lv.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/lv.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/lv.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/is.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/is.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/is.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/lt.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/lt.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/lt.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/mk.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/mk.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/mk.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/be.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/be.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/be.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ar_in.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ar_in.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ar_in.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ms_my.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ms_my.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ms_my.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/bn_in.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/bn_in.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/bn_in.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ms.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ms.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ms.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/mr.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/mr.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/mr.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/nn.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/nn.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/nn.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/nb.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/nb.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/nb.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/pt.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/pt.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/pt.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kl_gl.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/kl_gl.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kl_gl.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_gb.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_gb.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_gb.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fo_fo.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/fo_fo.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fo_fo.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ga_ie.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ga_ie.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ga_ie.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_ie.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_ie.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_ie.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fr_be.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/fr_be.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fr_be.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/pt_br.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/pt_br.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/pt_br.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fr_ca.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/fr_ca.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fr_ca.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/nl_be.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/nl_be.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/nl_be.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ru.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ru.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ru.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_ar.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_ar.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_ar.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ru_ua.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ru_ua.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ru_ua.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sh.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/sh.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sh.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sl.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/sl.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sl.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sk.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/sk.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sk.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/gl_es.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/gl_es.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/gl_es.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_sg.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_sg.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_sg.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_hn.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_hn.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_hn.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/af_za.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/af_za.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/af_za.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_pa.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_pa.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_pa.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_ni.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_ni.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_ni.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ta_in.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ta_in.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ta_in.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/hi_in.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/hi_in.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/hi_in.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_cr.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_cr.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_cr.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_mx.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_mx.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_mx.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_do.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_do.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_do.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sr.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/sr.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sr.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_pr.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_pr.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_pr.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_sv.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_sv.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_sv.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_ve.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_ve.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_ve.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_pe.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_pe.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_pe.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/mr_in.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/mr_in.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/mr_in.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_bo.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_bo.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_bo.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_cl.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_cl.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_cl.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_zw.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_zw.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_zw.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_bw.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_bw.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_bw.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_co.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_co.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_co.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_py.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_py.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_py.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_uy.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_uy.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_uy.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/id_id.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/id_id.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/id_id.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/gv_gb.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/gv_gb.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/gv_gb.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_ec.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_ec.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_ec.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_gt.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es_gt.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es_gt.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kw_gb.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/kw_gb.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kw_gb.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ta.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ta.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ta.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/th.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/th.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/th.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sv.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/sv.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sv.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/tr.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/tr.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/tr.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/te.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/te.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/te.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/zh_cn.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/zh_cn.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/zh_cn.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/zh_sg.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/zh_sg.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/zh_sg.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8/8.4/platform/shell-1.1.4.tm' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8/8.4/platform/shell-1.1.4.tm' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8/8.4/platform/shell-1.1.4.tm' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/tclIndex' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/tclIndex' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/tclIndex' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/vi.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/vi.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/vi.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/tclConfig.sh' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tclConfig.sh' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/tclConfig.sh' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/zh.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/zh.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/zh.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/expat/COPYING' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/licenses/expat/COPYING' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/expat/COPYING' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libffi/LICENSE' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/licenses/libffi/LICENSE' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libffi/LICENSE' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/gettext/gnulib-local/lib/libxml/COPYING' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/gettext/gettext-tools/gnulib-lib/libxml/COPYING' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/gettext/gnulib-local/lib/libxml/COPYING' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/licenses/libxml2/COPYING' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/gettext/gnulib-local/lib/libxml/COPYING' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.be.txt' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.ca.txt' '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.be.txt' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.cs.txt' '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.be.txt' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.da.txt' '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.be.txt' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.el.txt' '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.be.txt' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.eo.txt' '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.be.txt' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.et.txt' '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.be.txt' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.gl.txt' '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.be.txt' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.nb.txt' '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.be.txt' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.sv.txt' '/home/shima/Documents/tsb-java/PortableGit/usr/share/gnupg/help.be.txt' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/openssl/LICENSE' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/licenses/openssl/LICENSE' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/openssl/LICENSE' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-citool' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-gui' '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-citool' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sw.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/sw.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sw.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/zlib/LICENSE' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/licenses/zlib/LICENSE' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/zlib/LICENSE' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/it.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/it.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/it.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macCyrillic.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macCyrillic.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macCyrillic.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macDingbats.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macDingbats.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macDingbats.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macCentEuro.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macCentEuro.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macCentEuro.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macCroatian.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macCroatian.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macCroatian.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ro.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ro.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ro.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/es.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/es.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ar.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ar.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ar.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kw.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/kw.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kw.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/63/cygwin' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/63/cygwin' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/63/cygwin' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-16color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-16color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-16color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-16color-bce' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-16color-bce' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-16color-bce' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-16color-s' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-16color-s' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-16color-s' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-256color-bce' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-256color-bce' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-256color-bce' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-256color-bce-s' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-256color-bce-s' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-256color-bce-s' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-16color-bce-s' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-16color-bce-s' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-16color-bce-s' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-bce' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.Eterm' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-bce.Eterm' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.Eterm' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.gnome' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-bce.gnome' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.gnome' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.mrxvt' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-bce.mrxvt' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.mrxvt' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-s' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-s' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-s' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.konsole' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-bce.konsole' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.konsole' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.xterm-new' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-bce.xterm-new' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.xterm-new' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.Eterm' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.Eterm' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.Eterm' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.rxvt' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-bce.rxvt' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.rxvt' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.linux' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-bce.linux' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-bce.linux' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.konsole' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.konsole' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.konsole' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.linux' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.linux' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.linux' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.linux-m1' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.linux-m1' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.linux-m1' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.linux-m1b' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.linux-m1b' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.linux-m1b' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel1' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.minitel1' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel1' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel1b' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.minitel1b' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel1b' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.mlterm' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.mlterm' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.mlterm' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.mlterm-256color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.mlterm-256color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.mlterm-256color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.mrxvt' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.mrxvt' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.mrxvt' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.putty-m1' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.putty-m1' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.putty-m1' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.putty-m1b' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.putty-m1b' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.putty-m1b' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.putty' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.putty' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.putty' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.putty-m2' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.putty-m2' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.putty-m2' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.teraterm' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.teraterm' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.teraterm' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.putty-256color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.putty-256color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.putty-256color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.rxvt' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.rxvt' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.rxvt' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.vte' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.vte' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.vte' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel12-80' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel1b-80' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel12-80' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel2-80' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel12-80' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.minitel12-80' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel12-80' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.minitel1b-80' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel12-80' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.minitel2-80' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel12-80' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.xterm-256color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.xterm-256color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.xterm-256color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.vte-256color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.vte-256color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.vte-256color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.xterm-r6' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.xterm-r6' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.xterm-r6' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen4' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen4' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen4' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.xterm-new' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.xterm-xfree86' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.xterm-new' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.xterm-new' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.xterm-new' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.xterm-xfree86' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.xterm-new' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+88color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+88color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+88color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp857.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp857.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp857.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp775.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp775.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp775.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp864.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp864.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp864.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+256color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+256color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+256color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp860.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp860.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp860.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+256setaf' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+256setaf' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+256setaf' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp855.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp855.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp855.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp869.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp869.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp869.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp437.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp437.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp437.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp863.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp863.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp863.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp737.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp737.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp737.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp866.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp866.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp866.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp865.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp865.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp865.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp850.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp850.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp850.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp862.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp862.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp862.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp861.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp861.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp861.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/ascii.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/ascii.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/ascii.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp874.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp874.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp874.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp852.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp852.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp852.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+kbs' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+kbs' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+kbs' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+app' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+app' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+app' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+noapp' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+noapp' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+noapp' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+direct2' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+direct2' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+direct2' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+direct' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+direct' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+direct' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+noalt' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+noalt' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+noalt' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-w' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-w' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-w' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen5' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen5' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen5' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcc2' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+pcc2' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcc2' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcc3' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+pcc3' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcc3' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcf2' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+pcf2' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcf2' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcfkeys' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+pcfkeys' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcfkeys' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sm+1002' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+sm+1002' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sm+1002' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+x10mouse' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+x10mouse' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+x10mouse' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sl-twm' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+sl-twm' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sl-twm' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+x11mouse' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+x11mouse' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+x11mouse' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-1003' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-1003' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-1003' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-1002' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-1002' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-1002' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-1006' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-1006' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-1006' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-256color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-256color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-256color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-88color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-88color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-88color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-16color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-16color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-16color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-bold' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-bold' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-bold' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-mono' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-mono' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-mono' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.linux-m2' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.linux-m2' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.linux-m2' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-8bit' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-8bit' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-8bit' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-direct2' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-direct2' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-direct2' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+edit' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+edit' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+edit' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-old' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-old' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-old' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-direct' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-direct' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-direct' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-r5' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-r5' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-r5' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-nic' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-nic' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-nic' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libssh2/LICENSE' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/licenses/libssh2/LICENSE' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libssh2/LICENSE' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-hp' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-hp' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-hp' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-1005' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-1005' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-1005' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-new' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-new' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-new' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-vt220' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-vt220' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-vt220' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-sun' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-sun' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-sun' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-noapp' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-noapp' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-noapp' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-r6' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-r6' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-r6' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-x11hilite' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-x11hilite' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-x11hilite' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-utf8' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-utf8' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-utf8' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-sco' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-sco' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-sco' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+titlestack' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+titlestack' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+titlestack' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v33' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-xf86-v33' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v33' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-x10mouse' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-x10mouse' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-x10mouse' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-x11mouse' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-x11mouse' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-x11mouse' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v43' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-xf86-v43' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v43' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v40' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-xf86-v40' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v40' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xi' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-xi' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xi' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xfree86' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-xfree86' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xfree86' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm.js' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm.js' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm.js' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xtermc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xtermc' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xtermc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v44' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-xf86-v44' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v44' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm1' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm1' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm1' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterms-sun' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterms-sun' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterms-sun' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xtermm' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xtermm' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xtermm' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-24' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterms' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-24' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-24' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-24' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterms' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-24' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sm+1005' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+sm+1005' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sm+1005' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen+fkeys' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen+fkeys' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen+fkeys' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/licenses/vim/license.txt' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/doc/uganda.txt' '/home/shima/Documents/tsb-java/PortableGit/usr/share/licenses/vim/license.txt' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/uk.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/uk.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/uk.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/it_ch.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/it_ch.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/it_ch.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pc+edit' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+pc+edit' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pc+edit' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fr.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/fr.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fr.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ar_jo.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ar_jo.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ar_jo.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ar_lb.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ar_lb.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ar_lb.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ar_sy.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ar_sy.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ar_sy.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel1b-nb' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.minitel1b-nb' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel1b-nb' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ca.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ca_es.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ca.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_english_united_kingdom.1252.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_english_united_kingdom.ascii.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_english_united_kingdom.1252.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_af.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_af_af.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_af.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_is.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_is_is.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_is.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_nl.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_nl_nl.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_nl.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_pl.cp1250.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_pl_pl.cp1250.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_pl.cp1250.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_pt_pt.latin1.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_pt_pt.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_pt_pt.latin1.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ru.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ru_ru.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ru.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_sk.cp1250.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_sk_sk.cp1250.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_sk.cp1250.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_eo_eo.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_eo_xx.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_eo_eo.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_sr.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_sr_yu.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_sr.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_cs.cp1250.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_cs_cz.cp1250.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_cs.cp1250.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh_cn.18030.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh_cn.gbk.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh_cn.18030.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+keypad' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+keypad' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+keypad' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh.cp936.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh_cn.cp936.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh.cp936.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh.big5.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh.cp950.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh.big5.vim' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh_tw.big5.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh.big5.vim' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh_tw.cp950.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_zh.big5.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_de.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_de_de.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_de.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_fr.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_fr_fr.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_fr.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macThai.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macThai.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macThai.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/jis0201.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/jis0201.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/jis0201.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/da.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/da.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/da.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kl.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/kl.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kl.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-vt52' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-vt52' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-vt52' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/nl.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/nl.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/nl.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.hu' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.hu.cp1250' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.hu' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/ssl/ct_log_list.cnf' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/ssl/ct_log_list.cnf.dist' '/home/shima/Documents/tsb-java/PortableGit/mingw64/ssl/ct_log_list.cnf' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/ssl/ct_log_list.cnf' '/home/shima/Documents/tsb-java/PortableGit/mingw64/ssl/ct_log_list.cnf' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/ssl/ct_log_list.cnf.dist' '/home/shima/Documents/tsb-java/PortableGit/mingw64/ssl/ct_log_list.cnf' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_11.class' # original
remove_cmd    '/home/shima/Documents/tsb-java/02-04/bin/list2_11.class' '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_11.class' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sm+1003' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+sm+1003' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sm+1003' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_13.class' # original
remove_cmd    '/home/shima/Documents/tsb-java/02-04/bin/list2_13.class' '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_13.class' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.zh.utf-8' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.zh_tw.utf-8' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.zh.utf-8' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_15.class' # original
remove_cmd    '/home/shima/Documents/tsb-java/02-04/bin/list2_15.class' '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_15.class' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/02-04/src/list2_12.java' # original
remove_cmd    '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/src/list2_12.java' '/home/shima/Documents/tsb-java/02-04/src/list2_12.java' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/02-04/src/list2_14.java' # original
remove_cmd    '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/src/list2_14.java' '/home/shima/Documents/tsb-java/02-04/src/list2_14.java' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/02-04/src/list2_15.java' # original
remove_cmd    '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/src/list2_15.java' '/home/shima/Documents/tsb-java/02-04/src/list2_15.java' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/eu_es.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/eu_es.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/eu_es.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/02-04/src/list2_10.java' # original
remove_cmd    '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/src/list2_10.java' '/home/shima/Documents/tsb-java/02-04/src/list2_10.java' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_12.class' # original
remove_cmd    '/home/shima/Documents/tsb-java/02-04/bin/list2_12.class' '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_12.class' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/ssl/openssl.cnf' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/ssl/openssl.cnf.dist' '/home/shima/Documents/tsb-java/PortableGit/usr/ssl/openssl.cnf' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/ssl/openssl.cnf' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/ssl/openssl.cnf.dist' '/home/shima/Documents/tsb-java/PortableGit/mingw64/ssl/openssl.cnf' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/paste.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/paste.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/paste.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/gnat.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/gnat.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/gnat.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/gzip.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/gzip.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/gzip.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/clojurecomplete.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/clojurecomplete.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/clojurecomplete.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/context.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/context.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/context.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/contextcomplete.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/contextcomplete.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/contextcomplete.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/adacomplete.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/adacomplete.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/adacomplete.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/rustfmt.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/rustfmt.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/rustfmt.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/rust.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/rust.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/rust.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+alt+title' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+alt+title' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+alt+title' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/ada.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/ada.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/ada.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html32.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/html32.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html32.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xsd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/xsd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xsd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xsl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/xsl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xsl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/gcc-libs/COPYING.RUNTIME' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/licenses/gcc-libs/RUNTIME.LIBRARY.EXCEPTION' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/gcc-libs/COPYING.RUNTIME' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/default.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/colors/default.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/default.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/blue.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/colors/blue.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/blue.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v333' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-xf86-v333' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v333' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/murphy.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/colors/murphy.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/murphy.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v32' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-xf86-v32' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-xf86-v32' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/ron.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/colors/ron.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/ron.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/torte.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/colors/torte.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/torte.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/zellner.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/colors/zellner.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/zellner.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-basic' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-basic' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-basic' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/ant.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/ant.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/ant.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xmlcomplete.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xmlcomplete.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xmlcomplete.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/cargo.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/cargo.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/cargo.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/csslint.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/csslint.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/csslint.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/context.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/context.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/context.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/koehler.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/colors/koehler.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/koehler.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/industry.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/colors/industry.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/industry.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kok.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/kok.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/kok.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/decada.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/decada.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/decada.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/makepkg-template/perl-binary-module-dependency-1.template' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/makepkg-template/perl-binary-module-dependency.template' '/home/shima/Documents/tsb-java/PortableGit/usr/share/makepkg-template/perl-binary-module-dependency-1.template' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/erlang.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/erlang.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/erlang.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen+italics' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen+italics' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen+italics' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fortran_F.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/fortran_F.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fortran_F.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fortran_cv.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/fortran_cv.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fortran_cv.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fortran_lf95.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/fortran_lf95.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fortran_lf95.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/g95.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/g95.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/g95.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/gcc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/gcc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/gcc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/cs.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/cs.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/cs.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/ghc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/ghc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/ghc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/go.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/go.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/go.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/eruby.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/eruby.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/eruby.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/gnat.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/gnat.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/gnat.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/icc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/icc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/icc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen2' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen2' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen2' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/mt.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/mt.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/mt.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/ifort.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/ifort.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/ifort.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pce2' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+pce2' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pce2' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/hp_acc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/hp_acc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/hp_acc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/irix5_c.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/irix5_c.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/irix5_c.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/intel.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/intel.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/intel.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/gfortran.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/gfortran.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/gfortran.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/irix5_cpp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/irix5_cpp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/irix5_cpp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/mips_c.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/mips_c.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/mips_c.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/mipspro_c89.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/mipspro_c89.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/mipspro_c89.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/mcs.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/mcs.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/mcs.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/mipspro_cpp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/mipspro_cpp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/mipspro_cpp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/msbuild.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/msbuild.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/msbuild.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/neato.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/neato.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/neato.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/onsgmls.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/onsgmls.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/onsgmls.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/pyunit.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/pyunit.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/pyunit.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/pylint.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/pylint.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/pylint.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/rake.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/rake.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/rake.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/ruby.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/ruby.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/ruby.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/rubyunit.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/rubyunit.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/rubyunit.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/se.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/se.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/se.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/rst.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/rst.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/rst.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/rspec.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/rspec.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/rspec.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/rustc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/rustc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/rustc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/perl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/perl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/perl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/pl.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/pl.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/pl.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/xbuild.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/xbuild.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/xbuild.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/stack.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/stack.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/stack.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/xmlwf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/xmlwf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/xmlwf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/8th.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/8th.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/8th.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/abap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/abap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/abap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/abaqus.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/abaqus.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/abaqus.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/btm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/btm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/btm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/bzl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/bzl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/bzl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cfg.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/cfg.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cfg.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cmake.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/cmake.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cmake.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/ant.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/ant.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/ant.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_ca.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_ca.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_ca.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftoff.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftoff.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftoff.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/context.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/context.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/context.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/csh.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/csh.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/csh.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cvsrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/cvsrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cvsrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/changelog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/changelog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/changelog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/debcontrol.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/debcontrol.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/debcontrol.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cucumber.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/cucumber.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cucumber.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/clojure.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/clojure.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/clojure.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/docbk.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/docbk.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/docbk.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dockerfile.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/dockerfile.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dockerfile.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dtd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/dtd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dtd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/debchangelog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/debchangelog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/debchangelog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dune.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/dune.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dune.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cs.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/cs.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cs.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fortran_elf90.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/fortran_elf90.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fortran_elf90.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/csc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/csc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/csc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/erlang.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/erlang.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/erlang.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/eiffel.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/eiffel.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/eiffel.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/framescript.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/framescript.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/framescript.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/fvwm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/fvwm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/fvwm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/msvc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/msvc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/msvc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/gdb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/gdb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/gdb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/gitconfig.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/gitconfig.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/gitconfig.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/eruby.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/eruby.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/eruby.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/gitsendemail.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/gitsendemail.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/gitsendemail.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/go.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/go.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/go.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/groovy.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/groovy.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/groovy.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/gprof.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/gprof.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/gprof.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/flexwiki.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/flexwiki.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/flexwiki.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/haml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/haml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/haml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/haskell.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/haskell.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/haskell.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/hamster.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/hamster.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/hamster.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/hgcommit.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/hgcommit.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/hgcommit.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/group.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/group.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/group.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/htmldjango.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/htmldjango.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/htmldjango.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/indent.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/indent.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/indent.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/html.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/html.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/html.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/initex.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/initex.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/initex.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/ishd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/ishd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/ishd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/java.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/java.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/java.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/json.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/json.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/json.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_hk.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_hk.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_hk.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_ph.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_ph.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_ph.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/kconfig.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/kconfig.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/kconfig.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/jsp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/jsp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/jsp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sm+1006' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+sm+1006' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sm+1006' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/kwt.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/kwt.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/kwt.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/less.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/less.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/less.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/loginaccess.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/loginaccess.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/loginaccess.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/liquid.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/liquid.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/liquid.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/ocaml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/ocaml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/ocaml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/lprolog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/lprolog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/lprolog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mailaliases.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/mailaliases.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mailaliases.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cdrdaoconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/denyhosts.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cdrdaoconf.vim' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/hostconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cdrdaoconf.vim' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/cdrdaoconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cdrdaoconf.vim' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/denyhosts.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cdrdaoconf.vim' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/hostconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/cdrdaoconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mail.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/mail.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mail.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+indirect' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+indirect' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+indirect' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/make.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/make.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/make.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/manconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/manconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/manconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/logtalk.dict' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/logtalk.dict' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/logtalk.dict' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mplayerconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/mplayerconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mplayerconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/ch.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/ch.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/ch.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mma.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/mma.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mma.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/mf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ga.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ga.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ga.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/msmessages.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/msmessages.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/msmessages.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mrxvtrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/mrxvtrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mrxvtrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/mp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/neomuttrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/neomuttrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/neomuttrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/nanorc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/nanorc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/nanorc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/netrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/netrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/netrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/fetchmail.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/fetchmail.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/fetchmail.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/nroff.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/nroff.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/nroff.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/objc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/objc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/objc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/nsis.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/nsis.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/nsis.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/passwd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/passwd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/passwd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/pdf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/pdf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/pdf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/plaintex.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/plaintex.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/plaintex.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dictdconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/dictdconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dictdconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/pinfo.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/pinfo.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/pinfo.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/pascal.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/pascal.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/pascal.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/prolog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/prolog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/prolog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/libao.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/libao.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/libao.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/logindefs.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/logindefs.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/logindefs.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/protocols.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/protocols.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/protocols.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/lua.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/lua.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/lua.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/r.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/r.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/r.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/registry.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/registry.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/registry.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rhelp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/rhelp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rhelp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/procmail.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/procmail.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/procmail.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dircolors.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/dircolors.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dircolors.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rnc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/rnc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rnc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/arch.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/arch.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/arch.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/pablo.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/colors/pablo.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/pablo.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rnoweb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/rnoweb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rnoweb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/gv.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/gv.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/gv.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rpl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/rpl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rpl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rmd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/rmd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rmd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sbt.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/sbt.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sbt.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ja.eucjp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ja_jp.eucjp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ja.eucjp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/scala.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/scala.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/scala.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dtrace.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/dtrace.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dtrace.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/hog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/hog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/hog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rrst.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/rrst.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rrst.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rust.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/rust.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/rust.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/quake.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/quake.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/quake.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/setserial.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/setserial.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/setserial.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/services.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/services.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/services.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sh.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/sh.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sh.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/slpconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/slpconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/slpconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/modconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/modconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/modconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/tcl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/tcl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/tcl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/crm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/crm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/crm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sshconfig.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/sshconfig.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sshconfig.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sudoers.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/sudoers.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sudoers.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/readline.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/readline.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/readline.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/alsaconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/alsaconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/alsaconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/svg.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/svg.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/svg.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/pbx.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/pbx.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/pbx.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sieve.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/sieve.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sieve.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/scss.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/scss.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/scss.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/systemverilog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/systemverilog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/systemverilog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/tcl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/tcl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/tcl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+tmux' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+tmux' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+tmux' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/text.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/text.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/text.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/terminfo.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/terminfo.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/terminfo.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/treetop.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/treetop.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/treetop.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/logtalk.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/logtalk.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/logtalk.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/tex.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/tex.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/tex.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/udevperm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/udevperm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/udevperm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/m4.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/m4.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/m4.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/udevrules.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/udevrules.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/udevrules.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/updatedb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/updatedb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/updatedb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/verilog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/verilog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/verilog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/vroom.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/vroom.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/vroom.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/vb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/vb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/vb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sql.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/sql.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sql.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xhtml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/xhtml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xhtml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/lftp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/lftp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/lftp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/grub.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/grub.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/grub.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/tt2html.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/tt2html.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/tt2html.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dictconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/dictconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dictconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/udevconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/udevconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/udevconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xf86conf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/xf86conf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xf86conf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/conf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/conf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/conf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mailcap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/mailcap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/mailcap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xmodmap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/xmodmap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xmodmap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/vhdl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/vhdl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/vhdl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/xml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xsd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/xsd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xsd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xs.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/xs.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xs.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+vt+edit' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+vt+edit' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+vt+edit' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xdefaults.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/xdefaults.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xdefaults.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/aap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/aap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/aap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/ld.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/ld.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/ld.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/wast.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/wast.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/wast.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ch.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/ch.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ch.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/a2ps.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/a2ps.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/a2ps.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/eterm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/eterm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/eterm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/bst.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/bst.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/bst.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cdl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/cdl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cdl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/awk.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/awk.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/awk.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/chaiscript.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/chaiscript.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/chaiscript.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ada.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/ada.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ada.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/bzl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/bzl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/bzl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/d.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/d.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/d.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dictdconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/dictdconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dictdconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/docbk.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/docbk.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/docbk.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/automake.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/automake.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/automake.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_be.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/en_be.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/en_be.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugof.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugof.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugof.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cuda.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/cuda.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cuda.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/config.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/config.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/config.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dictconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/dictconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dictconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/changelog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/changelog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/changelog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dosbatch.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/dosbatch.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dosbatch.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/clojure.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/clojure.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/clojure.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/tex.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/tex.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/tex.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cs.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/cs.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cs.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dylan.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/dylan.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dylan.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/eiffel.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/eiffel.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/eiffel.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/eruby.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/eruby.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/eruby.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/gitolite.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/gitolite.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/gitolite.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/go.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/go.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/go.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/gitconfig.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/gitconfig.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/gitconfig.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_10.class' # original
remove_cmd    '/home/shima/Documents/tsb-java/02-04/bin/list2_10.class' '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_10.class' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/parray.tcl' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/parray.tcl' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/parray.tcl' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/framescript.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/framescript.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/framescript.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/htmldjango.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/htmldjango.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/htmldjango.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cobol.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/cobol.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cobol.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/idlang.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/idlang.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/idlang.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dtd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/dtd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dtd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ishd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/ishd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ishd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/jsp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/jsp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/jsp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/calendar.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/calendar.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/calendar.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/lisp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/lisp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/lisp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/automake.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/automake.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/automake.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/less.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/less.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/less.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/logtalk.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/logtalk.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/logtalk.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/64/dumb' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/64/dumb' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/64/dumb' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/mail.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/mail.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/mail.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/liquid.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/liquid.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/liquid.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/lua.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/lua.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/lua.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/mf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/mf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/mf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/mma.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/mma.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/mma.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/objc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/objc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/objc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ja.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ja.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ja.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/nsis.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/nsis.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/nsis.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/javascript.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/javascript.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/javascript.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/falcon.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/falcon.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/falcon.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/postscr.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/postscr.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/postscr.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ld.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/ld.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ld.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/java.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/java.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/java.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/hog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/hog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/hog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/pov.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/pov.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/pov.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/pascal.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/pascal.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/pascal.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ocaml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/ocaml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ocaml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/mp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/mp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/mp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/prolog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/prolog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/prolog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/occam.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/occam.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/occam.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/raml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/raml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/raml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/lifelines.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/lifelines.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/lifelines.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rmd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/rmd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rmd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rnoweb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/rnoweb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rnoweb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rhelp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/rhelp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rhelp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rrst.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/rrst.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rrst.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/scheme.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/scheme.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/scheme.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/dot.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/dot.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/dot.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rpl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/rpl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rpl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/systemd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/systemd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/systemd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/sql.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/sql.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/sql.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/gl.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/gl.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/gl.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/sass.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/sass.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/sass.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/tcsh.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/tcsh.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/tcsh.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/tilde.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/tilde.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/tilde.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/r.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/r.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/r.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/treetop.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/treetop.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/treetop.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/php.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/php.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/php.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/vb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/vb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/vb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/sml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/sml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/sml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/vroom.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/vroom.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/vroom.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/sdl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/sdl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/sdl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rust.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/rust.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/rust.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/tf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/tf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/tf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/xslt.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/xslt.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/xslt.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/xhtml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/xhtml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/xhtml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/verilog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/verilog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/verilog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/sas.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/sas.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/sas.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/scala.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/scala.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/scala.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dosini.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/dosini.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/dosini.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/wast.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/wast.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/wast.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/xsd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/xsd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/xsd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/yacc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/yacc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/yacc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/te_in.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/te_in.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/te_in.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/zsh.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/zsh.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/zsh.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/teraterm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/teraterm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/teraterm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/vhdl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/vhdl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/vhdl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/accents.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/accents.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/accents.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/xinetd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/xinetd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/xinetd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/eo.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/eo.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/eo.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/armenian-eastern_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/armenian-eastern_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/armenian-eastern_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/armenian-western_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/armenian-western_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/armenian-western_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/arabic_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/arabic_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/arabic_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/belarusian-jcuken.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/belarusian-jcuken.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/belarusian-jcuken.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/canfr-win.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/canfr-win.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/canfr-win.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/croatian_iso-8859-2.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/croatian_iso-8859-2.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/croatian_iso-8859-2.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/bulgarian-bds.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/bulgarian-bds.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/bulgarian-bds.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/croatian_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/croatian_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/croatian_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/bulgarian-phonetic.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/bulgarian-phonetic.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/bulgarian-phonetic.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/czech_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/czech_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/czech_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/dvorak.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/dvorak.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/dvorak.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/esperanto.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/esperanto.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/esperanto.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/czech.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/czech.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/czech.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/croatian_cp1250.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/croatian_cp1250.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/croatian_cp1250.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/greek.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/greek.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/greek.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/esperanto_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/esperanto_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/esperanto_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/greek_cp1253.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/greek_cp1253.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/greek_cp1253.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/greek_cp737.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/greek_cp737.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/greek_cp737.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/postscr.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/postscr.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/postscr.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrew_iso-8859-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/hebrew_iso-8859-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrew_iso-8859-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/c.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/c.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/c.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrewp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/hebrewp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrewp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrew_cp1255.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/hebrew_cp1255.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrew_cp1255.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrew_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/hebrew_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrew_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrewp_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/hebrewp_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrewp_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/kazakh-jcuken.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/kazakh-jcuken.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/kazakh-jcuken.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/mongolian_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/mongolian_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/mongolian_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/reva.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/reva.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/reva.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/xf86conf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/xf86conf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/xf86conf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/polish-slash.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/polish-slash.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/polish-slash.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/zh_hk.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/zh_hk.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/zh_hk.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/persian-iranian_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/persian-iranian_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/persian-iranian_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/context.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/context.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/context.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/magyar_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/magyar_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/magyar_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/pyrex.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/pyrex.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/pyrex.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/02-04/src/list2_13.java' # original
remove_cmd    '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/src/list2_13.java' '/home/shima/Documents/tsb-java/02-04/src/list2_13.java' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/persian.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/persian.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/persian.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+alt1049' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+alt1049' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+alt1049' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xslt.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/xslt.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xslt.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/pinyin.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/pinyin.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/pinyin.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/polish-slash_cp852.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/polish-slash_cp852.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/polish-slash_cp852.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrewp_iso-8859-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/hebrewp_iso-8859-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrewp_iso-8859-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/kana.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/kana.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/kana.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/russian-jcuken.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/russian-jcuken.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/russian-jcuken.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/russian-dvorak.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/russian-dvorak.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/russian-dvorak.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian-latin.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/serbian-latin.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian-latin.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/php.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/php.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/php.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/russian-jcukenmac.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/russian-jcukenmac.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/russian-jcukenmac.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/polish-slash_cp1250.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/polish-slash_cp1250.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/polish-slash_cp1250.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/polish-slash_iso-8859-2.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/polish-slash_iso-8859-2.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/polish-slash_iso-8859-2.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian-latin_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/serbian-latin_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian-latin_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/russian-yawerty.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/russian-yawerty.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/russian-yawerty.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/slpspi.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/slpspi.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/slpspi.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/serbian.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/muttrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/muttrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/muttrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/russian-jcukenwin.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/russian-jcukenwin.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/russian-jcukenwin.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/polish-slash_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/polish-slash_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/polish-slash_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/hamster.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/hamster.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/hamster.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/oldturkic-orkhon_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/oldturkic-orkhon_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/oldturkic-orkhon_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian_cp1251.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/serbian_cp1251.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian_cp1251.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian_iso-8859-5.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/serbian_iso-8859-5.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian_iso-8859-5.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+osc104' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+osc104' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+osc104' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/bdf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/bdf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/bdf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian_iso-8859-2.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/serbian_iso-8859-2.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian_iso-8859-2.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrew.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/hebrew.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrew.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/slovak.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/slovak.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/slovak.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/slovak_iso-8859-2.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/slovak_iso-8859-2.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/slovak_iso-8859-2.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/slovak_cp1250.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/slovak_cp1250.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/slovak_cp1250.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/greek_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/greek_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/greek_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/sinhala-phonetic_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/sinhala-phonetic_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/sinhala-phonetic_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/thaana-phonetic_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/thaana-phonetic_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/thaana-phonetic_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/ukrainian-dvorak.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/ukrainian-dvorak.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/ukrainian-dvorak.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/de_at.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/de_at.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/de_at.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrewp_cp1255.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/hebrewp_cp1255.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/hebrewp_cp1255.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/slovak_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/slovak_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/slovak_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/vietnamese-telex_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/vietnamese-telex_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/vietnamese-telex_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/macros/shellmenu.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/macros/shellmenu.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/macros/shellmenu.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso2022-kr.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso2022-kr.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso2022-kr.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/vietnamese-vni_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/vietnamese-vni_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/vietnamese-vni_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/sass.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/sass.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/sass.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/zimbu.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/zimbu.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/zimbu.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/vietnamese-viqr_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/vietnamese-viqr_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/vietnamese-viqr_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/macros/swapmous.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/macros/swapmous.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/macros/swapmous.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/lithuanian-baltic.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/lithuanian-baltic.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/lithuanian-baltic.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_it.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_it_it.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_it.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_fi.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_fi_fi.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_fi.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_es.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_es_es.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_es.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_sv.utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_sv_se.utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_sv.utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/sinhala.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/sinhala.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/sinhala.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/mswin.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/mswin.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/mswin.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ant.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/ant.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/ant.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/pack/dist/opt/swapmouse/plugin/swapmouse.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/pack/dist/opt/swapmouse/plugin/swapmouse.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/pack/dist/opt/swapmouse/plugin/swapmouse.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/tamil_tscii.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/tamil_tscii.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/tamil_tscii.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/eterm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/eterm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/eterm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/pack/dist/opt/shellmenu/plugin/shellmenu.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/pack/dist/opt/shellmenu/plugin/shellmenu.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/pack/dist/opt/shellmenu/plugin/shellmenu.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/ukrainian-jcuken.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/ukrainian-jcuken.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/ukrainian-jcuken.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/plugin/vimballPlugin.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/pack/dist/opt/vimball/plugin/vimballPlugin.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/plugin/vimballPlugin.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/pack/dist/opt/justify/plugin/justify.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/pack/dist/opt/justify/plugin/justify.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/pack/dist/opt/justify/plugin/justify.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/ascii.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/ascii.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/ascii.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/splint.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/splint.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/splint.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cidfont.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/cidfont.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cidfont.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1251.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/cp1251.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1251.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1253.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/cp1253.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1253.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1254.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/cp1254.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1254.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1255.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/cp1255.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1255.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/lisp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/lisp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/lisp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/gb_roman.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/gb_roman.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/gb_roman.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1257.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/cp1257.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1257.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-10.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-10.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-10.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/hp-roman8.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/hp-roman8.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/hp-roman8.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-13.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-13.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-13.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-14.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-14.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-14.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-2.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-2.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-2.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-3.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-3.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-3.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/greek_iso-8859-7.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/greek_iso-8859-7.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/greek_iso-8859-7.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-4.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-4.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-4.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-15.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-15.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-15.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-5.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-5.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-5.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-11.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-11.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-11.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-8.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-8.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-8.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-9.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-9.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-9.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-7.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/iso-8859-7.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/iso-8859-7.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/jis_roman.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/jis_roman.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/jis_roman.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/koi8-u.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/koi8-u.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/koi8-u.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/prolog.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/prolog.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/prolog.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/mac-roman.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/mac-roman.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/mac-roman.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/vimball.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/pack/dist/opt/vimball/autoload/vimball.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/vimball.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cns_roman.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/cns_roman.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cns_roman.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/ks_roman.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/ks_roman.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/ks_roman.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/a2ps.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/a2ps.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/a2ps.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-2.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-2.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-2.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-6.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-6.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-6.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-7.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-7.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-7.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+r6f2' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+r6f2' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+r6f2' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-9.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-9.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-9.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-3.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-3.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-3.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-1.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-1.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-1.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-4.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-4.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-4.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-8.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-8.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-8.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-5.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso8859-5.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso8859-5.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/abaqus.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/abaqus.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/abaqus.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/abc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/abc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/abc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/koi8-r.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/koi8-r.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/koi8-r.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/a65.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/a65.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/a65.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/aflex.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/aflex.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/aflex.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/abap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/abap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/abap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/apachestyle.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/apachestyle.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/apachestyle.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ampl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ampl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ampl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/abel.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/abel.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/abel.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzless' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzmore' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzless' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bzless' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzless' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bzmore' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzless' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/art.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/art.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/art.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/occam.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/occam.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/occam.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ahdl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ahdl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ahdl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/asm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/asm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/asm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ada.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ada.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ada.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ant.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ant.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ant.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/antlr.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/antlr.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/antlr.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/arch.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/arch.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/arch.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fortran_g77.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/fortran_g77.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fortran_g77.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/acedb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/acedb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/acedb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/aptconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/aptconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/aptconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/8th.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/8th.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/8th.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/aap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/aap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/aap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/asmh8300.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/asmh8300.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/asmh8300.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/aspperl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/aspperl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/aspperl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/asn.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/asn.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/asn.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/atlas.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/atlas.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/atlas.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/avra.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/avra.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/avra.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cmake.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/cmake.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cmake.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/aml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/aml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/aml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ayacc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ayacc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ayacc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/b.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/b.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/b.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/asteriskvm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/asteriskvm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/asteriskvm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/bc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bst.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/bst.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bst.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bzl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/bzl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bzl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sl' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+sl' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+sl' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/blank.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/blank.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/blank.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bib.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/bib.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bib.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/catalog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/catalog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/catalog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/autohotkey.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/autohotkey.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/autohotkey.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/calendar.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/calendar.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/calendar.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/automake.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/automake.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/automake.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cdrdaoconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cdrdaoconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cdrdaoconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bzr.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/bzr.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bzr.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ch.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ch.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ch.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cfg.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cfg.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cfg.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/changelog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/changelog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/changelog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cheetah.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cheetah.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cheetah.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/bst.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/bst.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/bst.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/chaskell.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/chaskell.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/chaskell.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/chordpro.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/chordpro.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/chordpro.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cdrtoc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cdrtoc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cdrtoc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/chicken.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/chicken.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/chicken.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/change.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/change.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/change.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/chaiscript.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/chaiscript.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/chaiscript.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/btm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/btm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/btm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cmod.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cmod.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cmod.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cmusrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cmusrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cmusrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/coco.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/coco.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/coco.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/cs.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/cs.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/cs.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/colortest.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/colortest.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/colortest.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/crm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/crm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/crm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/context.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/context.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/context.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/csp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/csp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/csp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/conf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/conf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/conf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/modelsim_vcom.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/modelsim_vcom.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/modelsim_vcom.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cobol.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cobol.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cobol.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/config.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/config.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/config.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cterm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cterm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cterm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cupl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cupl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cupl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ctrlh.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ctrlh.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ctrlh.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/conaryrecipe.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/conaryrecipe.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/conaryrecipe.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cuplsim.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cuplsim.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cuplsim.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/aspvbs.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/aspvbs.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/aspvbs.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/csc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/csc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/csc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cvsrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cvsrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cvsrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cynlib.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cynlib.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cynlib.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dcd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dcd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dcd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/csdl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/csdl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/csdl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/datascript.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/datascript.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/datascript.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/def.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/def.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/def.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/crontab.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/crontab.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/crontab.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1250.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/cp1250.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1250.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/desc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/desc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/desc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/debcontrol.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/debcontrol.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/debcontrol.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/denyhosts.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/denyhosts.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/denyhosts.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cucumber.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cucumber.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cucumber.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cynpp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cynpp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cynpp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dictdconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dictdconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dictdconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cuda.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cuda.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cuda.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/css.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/css.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/css.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/diva.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/diva.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/diva.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/django.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/django.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/django.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/docbksgml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/docbksgml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/docbksgml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bdf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/bdf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/bdf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/docbk.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/docbk.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/docbk.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/docbkxml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/docbkxml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/docbkxml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/scss.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/scss.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/scss.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/diff.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/diff.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/diff.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dosbatch.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dosbatch.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dosbatch.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/basic.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/basic.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/basic.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dnsmasq.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dnsmasq.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dnsmasq.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/RstFold.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/RstFold.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/RstFold.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ave.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ave.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ave.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dot.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dot.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dot.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dosini.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dosini.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dosini.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dns.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dns.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dns.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dsl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dsl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dsl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dts.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dts.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dts.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sgml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/sgml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sgml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dracula.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dracula.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dracula.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dune.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dune.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dune.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dylanlid.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dylanlid.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dylanlid.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dylanintr.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dylanintr.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dylanintr.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/elf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/elf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/elf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cweb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cweb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cweb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dylan.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dylan.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dylan.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/esterel.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/esterel.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/esterel.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/edif.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/edif.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/edif.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/eiffel.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/eiffel.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/eiffel.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dtml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dtml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dtml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/esmtprc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/esmtprc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/esmtprc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/eviews.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/eviews.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/eviews.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/expect.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/expect.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/expect.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fdcc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/fdcc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fdcc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/euphoria3.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/euphoria3.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/euphoria3.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/euphoria4.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/euphoria4.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/euphoria4.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ecd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ecd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ecd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fasm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/fasm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fasm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-256color-s' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-256color-s' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-256color-s' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/falcon.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/falcon.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/falcon.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fan.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/fan.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fan.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/focexec.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/focexec.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/focexec.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.konsole-256color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.konsole-256color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.konsole-256color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fetchmail.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/fetchmail.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fetchmail.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/form.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/form.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/form.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/elinks.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/elinks.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/elinks.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fgl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/fgl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fgl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gdb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gdb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gdb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/flexwiki.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/flexwiki.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/flexwiki.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gitsendemail.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gitsendemail.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gitsendemail.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fvwm2m4.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/fvwm2m4.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fvwm2m4.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/readline.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/readline.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/readline.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/eruby.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/eruby.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/eruby.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gdmo.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gdmo.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gdmo.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/forth.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/forth.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/forth.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/esqlc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/esqlc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/esqlc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gnash.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gnash.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gnash.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/godoc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/godoc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/godoc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/go.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/go.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/go.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/exim.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/exim.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/exim.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fvwm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/fvwm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/fvwm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/grads.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/grads.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/grads.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gedcom.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gedcom.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gedcom.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/framescript.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/framescript.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/framescript.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gprof.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gprof.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gprof.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-256color' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen-256color' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen-256color' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/group.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/group.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/group.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gretl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gretl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gretl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/autodoc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/autodoc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/autodoc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gpg.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gpg.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gpg.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/eterm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/eterm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/eterm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gkrellmrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gkrellmrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gkrellmrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gsp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gsp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gsp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/arduino.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/arduino.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/arduino.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/haste.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/haste.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/haste.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/grub.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/grub.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/grub.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/hb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gtkrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gtkrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gtkrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hamster.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/hamster.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hamster.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hercules.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/hercules.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hercules.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hastepreproc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/hastepreproc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hastepreproc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hex.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/hex.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hex.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hitest.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/hitest.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hitest.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/htmlm4.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/htmlm4.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/htmlm4.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hostconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/hostconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hostconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gitolite.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/gitolite.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/gitolite.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/htmldjango.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/htmldjango.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/htmldjango.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcf0' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+pcf0' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcf0' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/htmlcheetah.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/htmlcheetah.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/htmlcheetah.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/icon.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/icon.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/icon.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/htmlos.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/htmlos.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/htmlos.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/indent.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/indent.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/indent.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ibasic.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ibasic.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ibasic.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/idlang.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/idlang.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/idlang.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcc0' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+pcc0' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcc0' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/icemenu.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/icemenu.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/icemenu.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcc1' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+pcc1' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+pcc1' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hostsaccess.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/hostsaccess.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hostsaccess.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/idl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/idl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/idl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jal.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/jal.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jal.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/javacc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/javacc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/javacc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/initex.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/initex.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/initex.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/java.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/java.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/java.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/inform.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/inform.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/inform.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/initng.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/initng.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/initng.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jam.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/jam.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jam.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ipfilter.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ipfilter.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ipfilter.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jgraph.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/jgraph.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jgraph.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jovial.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/jovial.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jovial.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jproperties.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/jproperties.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jproperties.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fo.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/fo.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/fo.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/kivy.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/kivy.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/kivy.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/kscript.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/kscript.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/kscript.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ishd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ishd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ishd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/kwt.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/kwt.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/kwt.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cucumber.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/cucumber.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cucumber.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jsp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/jsp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jsp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/latte.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/latte.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/latte.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lace.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lace.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lace.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/libao.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/libao.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/libao.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jess.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/jess.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/jess.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ldapconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ldapconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ldapconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lftp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lftp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lftp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lite.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lite.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lite.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/limits.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/limits.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/limits.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/liquid.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/liquid.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/liquid.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/loginaccess.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/loginaccess.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/loginaccess.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lilo.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lilo.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lilo.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lhaskell.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lhaskell.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lhaskell.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lout.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lout.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lout.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lotos.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lotos.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lotos.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/litestep.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/litestep.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/litestep.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ldif.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ldif.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ldif.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/logindefs.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/logindefs.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/logindefs.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lprolog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lprolog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lprolog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lynx.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lynx.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lynx.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/ssl/misc/tsget' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/ssl/misc/tsget.pl' '/home/shima/Documents/tsb-java/PortableGit/usr/ssl/misc/tsget' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lifelines.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lifelines.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lifelines.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lss.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lss.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lss.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mailcap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mailcap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mailcap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lua.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lua.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lua.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mailaliases.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mailaliases.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mailaliases.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lscript.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lscript.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lscript.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mallard.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mallard.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mallard.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/manual.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/manual.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/manual.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mail.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mail.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mail.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/master.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/master.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/master.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lsl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lsl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lsl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/manconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/manconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/manconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mason.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mason.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mason.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/m4.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/m4.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/m4.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mgl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mgl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mgl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/logtalk.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/logtalk.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/logtalk.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mix.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mix.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mix.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mmix.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mmix.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mmix.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/model.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/model.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/model.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/modsim3.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/modsim3.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/modsim3.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/modula3.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/modula3.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/modula3.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mma.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mma.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mma.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mmp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mmp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mmp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mib.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mib.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mib.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/modula2.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/modula2.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/modula2.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/msidl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/msidl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/msidl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/msql.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/msql.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/msql.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mplayerconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mplayerconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mplayerconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/modconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/modconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/modconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/messages.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/messages.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/messages.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/moo.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/moo.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/moo.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/maxima.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/maxima.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/maxima.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/murphi.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/murphi.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/murphi.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/msmessages.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/msmessages.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/msmessages.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mush.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mush.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mush.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/monk.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/monk.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/monk.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mupad.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mupad.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mupad.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/netrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/netrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/netrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mrxvtrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mrxvtrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mrxvtrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nosyntax.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/nosyntax.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nosyntax.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/n1ql.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/n1ql.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/n1ql.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nanorc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/nanorc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nanorc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/natural.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/natural.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/natural.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nasm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/nasm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nasm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nroff.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/nroff.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nroff.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mysql.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mysql.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mysql.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/obj.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/obj.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/obj.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ncf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ncf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ncf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/objcpp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/objcpp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/objcpp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/matlab.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/matlab.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/matlab.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/occam.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/occam.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/occam.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nastran.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/nastran.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nastran.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/omnimark.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/omnimark.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/omnimark.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ninja.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ninja.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ninja.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/papp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/papp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/papp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lpc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/lpc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/lpc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/passwd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/passwd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/passwd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ocaml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ocaml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ocaml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/phtml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/phtml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/phtml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/openroad.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/openroad.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/openroad.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ora.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ora.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ora.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pilrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pilrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pilrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/plaintex.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/plaintex.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/plaintex.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pascal.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pascal.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pascal.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/plp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/plp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/plp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sq.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/sq.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/sq.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/po.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/po.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/po.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pod.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pod.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pod.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pcap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pcap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pcap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/plsql.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/plsql.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/plsql.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pic.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pic.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pic.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pli.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pli.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pli.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pine.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pine.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pine.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/prescribe.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/prescribe.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/prescribe.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/make.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/make.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/make.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/povini.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/povini.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/povini.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ppd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ppd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ppd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ppwiz.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ppwiz.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ppwiz.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/promela.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/promela.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/promela.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/prolog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/prolog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/prolog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pinfo.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pinfo.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pinfo.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pike.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pike.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pike.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nqc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/nqc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nqc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/procmail.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/procmail.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/procmail.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pov.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pov.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pov.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/privoxy.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/privoxy.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/privoxy.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/protocols.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/protocols.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/protocols.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/psf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/psf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/psf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/proto.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/proto.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/proto.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/chicken.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/chicken.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/chicken.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pyrex.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pyrex.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pyrex.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/purifylog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/purifylog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/purifylog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/progress.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/progress.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/progress.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/qf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/qf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/qf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/raml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/raml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/raml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/quake.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/quake.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/quake.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/radiance.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/radiance.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/radiance.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/racc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/racc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/racc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/plm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/plm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/plm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/opl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/opl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/opl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ptcap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ptcap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ptcap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/r.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/r.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/r.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/remind.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/remind.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/remind.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rcslog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rcslog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rcslog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rng.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rng.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rng.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rmd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rmd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rmd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rnoweb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rnoweb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rnoweb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/elflord.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/colors/elflord.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/colors/elflord.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ratpoison.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ratpoison.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ratpoison.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/robots.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/robots.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/robots.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rrst.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rrst.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rrst.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rcs.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rcs.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rcs.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rhelp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rhelp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rhelp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/readline.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/readline.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/readline.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rnc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rnc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rnc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/registry.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/registry.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/registry.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rebol.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rebol.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rebol.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1252.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/cp1252.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/cp1252.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rib.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rib.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rib.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/latin1.ps' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/print/latin1.ps' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/print/latin1.ps' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rust.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rust.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rust.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/screen.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/screen.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/screen.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rpl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rpl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rpl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/scilab.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/scilab.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/scilab.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sdc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sdc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sdc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sbt.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sbt.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sbt.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sdl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sdl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sdl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rtf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rtf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rtf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sgmldecl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sgmldecl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sgmldecl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sendpr.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sendpr.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sendpr.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sieve.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sieve.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sieve.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sgmllnx.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sgmllnx.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sgmllnx.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sensors.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sensors.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sensors.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sgml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sgml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sgml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/scheme.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/scheme.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/scheme.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rexx.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/rexx.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/rexx.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sinda.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sinda.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sinda.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sindaout.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sindaout.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sindaout.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/pack/dist/opt/matchit/doc/tags' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/pack/dist/opt/matchit/doc/tags' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/pack/dist/opt/matchit/doc/tags' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/services.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/services.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/services.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/scala.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/scala.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/scala.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sicad.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sicad.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sicad.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slice.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/slice.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slice.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slrnsc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/slrnsc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slrnsc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/setserial.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/setserial.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/setserial.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/smith.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/smith.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/smith.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian_utf-8.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/serbian_utf-8.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian_utf-8.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slpspi.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/slpspi.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slpspi.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slpreg.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/slpreg.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slpreg.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/snnsnet.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/snnsnet.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/snnsnet.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slpconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/slpconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slpconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/smil.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/smil.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/smil.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/spice.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/spice.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/spice.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sql.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sql.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sql.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/simula.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/simula.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/simula.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sisu.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sisu.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sisu.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/spyce.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/spyce.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/spyce.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/snnsres.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/snnsres.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/snnsres.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/skill.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/skill.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/skill.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/splint.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/splint.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/splint.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slrnrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/slrnrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slrnrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqlhana.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sqlhana.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqlhana.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqlforms.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sqlforms.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqlforms.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqlinformix.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sqlinformix.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqlinformix.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/snobol4.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/snobol4.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/snobol4.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqlj.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sqlj.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqlj.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/smcl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/smcl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/smcl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/squid.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/squid.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/squid.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqloracle.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sqloracle.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqloracle.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/snnspat.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/snnspat.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/snnspat.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/srec.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/srec.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/srec.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/smarty.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/smarty.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/smarty.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/st.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/st.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/st.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/strace.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/strace.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/strace.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/elinks.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/elinks.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/elinks.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/hostsaccess.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/hostsaccess.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/hostsaccess.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/screen.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/screen.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/screen.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/limits.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/limits.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/limits.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/svg.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/svg.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/svg.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/svn.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/svn.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/svn.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqr.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sqr.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqr.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sysctl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sysctl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sysctl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/systemd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/systemd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/systemd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/stp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/stp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/stp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pdf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pdf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pdf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/systemverilog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/systemverilog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/systemverilog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/takcmp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/takcmp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/takcmp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tak.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tak.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tak.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tar.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tar.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tar.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tads.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tads.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tads.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/taskedit.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/taskedit.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/taskedit.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/taskdata.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/taskdata.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/taskdata.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/tcsh.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/tcsh.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/tcsh.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ist.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/ist.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/ist.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/takout.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/takout.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/takout.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mgp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mgp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mgp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/racc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/racc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/racc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/bcc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/bcc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/bcc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/template.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/template.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/template.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/bdf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/bdf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/bdf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pccts.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pccts.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pccts.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tasm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tasm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tasm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/teraterm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/teraterm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/teraterm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/stata.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/stata.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/stata.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tilde.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tilde.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tilde.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tpp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tpp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tpp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sudoers.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sudoers.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sudoers.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slang.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/slang.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/slang.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/terminfo.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/terminfo.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/terminfo.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/syntax.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/syntax.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/syntax.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/treetop.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/treetop.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/treetop.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/texmf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/texmf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/texmf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/trustees.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/trustees.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/trustees.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/alsaconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/alsaconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/alsaconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sed.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sed.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sed.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/trasys.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/trasys.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/trasys.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tt2html.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tt2html.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tt2html.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tssgm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tssgm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tssgm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-pcolor' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm-pcolor' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm-pcolor' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tli.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tli.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tli.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sshdconfig.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sshdconfig.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sshdconfig.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/texinfo.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/texinfo.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/texinfo.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tssop.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tssop.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tssop.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tsscl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tsscl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tsscl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tt2.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tt2.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tt2.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tsalt.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tsalt.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tsalt.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tt2js.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tt2js.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tt2js.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/jikes.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/jikes.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/jikes.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/udevperm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/udevperm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/udevperm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/upstreaminstalllog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/upstreaminstalllog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/upstreaminstalllog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/uc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/uc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/uc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tcsh.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tcsh.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tcsh.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/uil.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/uil.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/uil.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/clean.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/clean.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/clean.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/upstart.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/upstart.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/upstart.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/updatedb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/updatedb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/updatedb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/udevconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/udevconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/udevconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/usw2kagtlog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/usw2kagtlog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/usw2kagtlog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/valgrind.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/valgrind.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/valgrind.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tidy.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/tidy.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/tidy.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/udevrules.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/udevrules.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/udevrules.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vgrindefs.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/vgrindefs.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vgrindefs.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/upstreamlog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/upstreamlog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/upstreamlog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/verilog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/verilog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/verilog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/upstreamdat.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/upstreamdat.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/upstreamdat.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/upstreamrpt.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/upstreamrpt.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/upstreamrpt.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vmasm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/vmasm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vmasm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vb.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/vb.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vb.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vroom.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/vroom.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vroom.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/virata.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/virata.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/virata.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/verilogams.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/verilogams.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/verilogams.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/gpg.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/gpg.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/gpg.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/pamconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/pamconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/pamconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vue.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/vue.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vue.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dictconf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/dictconf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/dictconf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.gnome' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.gnome' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.gnome' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/usserverlog.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/usserverlog.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/usserverlog.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/voscm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/voscm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/voscm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wast.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/wast.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wast.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vsejcl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/vsejcl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vsejcl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/viminfo.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/viminfo.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/viminfo.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hgcommit.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/hgcommit.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hgcommit.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/web.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/web.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/web.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vera.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/vera.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vera.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/whitespace.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/whitespace.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/whitespace.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/webmacro.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/webmacro.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/webmacro.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wget.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/wget.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wget.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macRoman.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macRoman.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macRoman.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/dingbats.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/dingbats.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/dingbats.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macGreek.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macGreek.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macGreek.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wvdial.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/wvdial.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wvdial.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/wml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wsh.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/wsh.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wsh.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vrml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/vrml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/vrml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wsml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/wsml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wsml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wdiff.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/wdiff.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/wdiff.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/aap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/aap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/aap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/winbatch.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/winbatch.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/winbatch.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/pyrex.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/pyrex.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/pyrex.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xpm2.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/xpm2.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xpm2.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/z8a.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/z8a.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/z8a.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xquery.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/xquery.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xquery.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/zimbu.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/zimbu.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/zimbu.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/02-04/src/list2_11.java' # original
remove_cmd    '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/src/list2_11.java' '/home/shima/Documents/tsb-java/02-04/src/list2_11.java' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xhtml.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/xhtml.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xhtml.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian_cp1250.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/serbian_cp1250.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/serbian_cp1250.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dtrace.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/dtrace.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/dtrace.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xdefaults.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/xdefaults.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xdefaults.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen3' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen3' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen3' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel1-nb' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/73/screen.minitel1-nb' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/73/screen.minitel1-nb' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/tmux.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/tmux.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/tmux.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ja.cp932.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ja_jp.cp932.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ja.cp932.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/groff.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/groff.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/groff.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cpp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/cpp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/cpp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xsd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/xsd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xsd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xinetd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/xinetd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/xinetd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/slpreg.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/slpreg.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/slpreg.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xf86conf.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/xf86conf.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xf86conf.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xpm.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/xpm.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xpm.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/macros/justify.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/macros/justify.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/macros/justify.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/arabic.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/arabic.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/arabic.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/javascriptreact.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/javascriptreact.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/javascriptreact.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/thaana.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/thaana.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/thaana.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indoff.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indoff.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indoff.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso2022.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/iso2022.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/iso2022.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sensors.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/sensors.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sensors.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/zh_tw.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/zh_tw.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/zh_tw.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ko_kr.msg' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/msgs/ko_kr.msg' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/msgs/ko_kr.msg' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/bib.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/indent/bib.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/indent/bib.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ja.ujis.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ja_jp.ujis.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/menu_ja.ujis.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/croatian.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/keymap/croatian.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/keymap/croatian.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fpc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/fpc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/fpc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/logcheck.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/logcheck.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/logcheck.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sysctl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/sysctl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/sysctl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xinetd.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/xinetd.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xinetd.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/python/2021.06.03/main.py' # original
remove_cmd    '/home/shima/Documents/tsb-java/python/2021.06.24/main.py' '/home/shima/Documents/tsb-java/python/2021.06.03/main.py' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/python/2021.06.17/main.py' '/home/shima/Documents/tsb-java/python/2021.06.03/main.py' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/config.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/config.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/config.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sindacmp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sindacmp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sindacmp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/tidy.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/tidy.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/tidy.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xbl.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/xbl.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xbl.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_14.class' # original
remove_cmd    '/home/shima/Documents/tsb-java/02-04/bin/list2_14.class' '/home/shima/Documents/tsb-java/java/shima/workspace/02-04/bin/list2_14.class' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/art.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/ftplugin/art.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/ftplugin/art.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/cucumber.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/compiler/cucumber.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/compiler/cucumber.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+x11hilite' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/terminfo/78/xterm+x11hilite' '/home/shima/Documents/tsb-java/PortableGit/usr/lib/terminfo/78/xterm+x11hilite' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/cmd/git.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/bin/git.exe' '/home/shima/Documents/tsb-java/PortableGit/cmd/git.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bunzip2.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzcat.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bunzip2.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bzip2.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/bunzip2.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/wish.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/wish86.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/wish.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/tclsh.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/tclsh86.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/tclsh.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/unxz.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/xz.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/unxz.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/xzcat.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/unxz.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/edit.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/edit.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/edit.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libbrotlidec.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libbrotlidec.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libbrotlidec.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libcares-4.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libcares-4.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libcares-4.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libgcc_s_seh-1.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libgcc_s_seh-1.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libgcc_s_seh-1.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libjansson-4.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libjansson-4.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libjansson-4.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libmetalink-3.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libmetalink-3.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libmetalink-3.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libpcreposix-0.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libpcreposix-0.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libpcreposix-0.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/liblzma-5.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/liblzma-5.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/liblzma-5.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libbz2-1.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libbz2-1.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libbz2-1.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libidn2-0.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libidn2-0.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libidn2-0.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libbrotlicommon.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libbrotlicommon.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libbrotlicommon.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libintl-8.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libintl-8.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libintl-8.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libtre-5.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libtre-5.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libtre-5.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libwinpthread-1.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libwinpthread-1.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libwinpthread-1.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libssp-0.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libssp-0.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libssp-0.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/doc/git-doc/git.html' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/doc/git-doc/index.html' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/doc/git-doc/git.html' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-upload-archive.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-upload-pack.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-add.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-am.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-annotate.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-apply.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-archive.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-bisect--helper.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-blame.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-branch.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-bugreport.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-bundle.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-cat-file.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-check-attr.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-check-ignore.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-check-mailmap.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-check-ref-format.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-checkout-index.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-checkout.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-cherry-pick.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-cherry.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-clean.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-clone.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-column.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-commit-graph.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-commit-tree.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-commit.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-config.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-count-objects.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-credential-cache--daemon.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-credential-cache.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-credential-store.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-credential.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-describe.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-diff-files.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-diff-index.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-diff-tree.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-diff.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-difftool.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-env--helper.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-fast-export.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-fast-import.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-fetch-pack.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-fetch.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-fmt-merge-msg.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-for-each-ref.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-for-each-repo.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-format-patch.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-fsck-objects.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-fsck.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-fsmonitor--daemon.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-gc.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-get-tar-commit-id.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-grep.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-hash-object.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-help.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-index-pack.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-init-db.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-init.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-interpret-trailers.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-log.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-ls-files.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-ls-remote.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-ls-tree.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-mailinfo.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-mailsplit.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-maintenance.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-merge-base.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-merge-file.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-merge-index.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-merge-ours.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-merge-recursive.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-merge-subtree.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-merge-tree.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-merge.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-mktag.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-mktree.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-multi-pack-index.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-mv.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-name-rev.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-notes.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-pack-objects.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-pack-redundant.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-pack-refs.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-patch-id.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-prune-packed.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-prune.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-pull.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-push.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-range-diff.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-read-tree.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-rebase.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-receive-pack.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-reflog.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-remote-ext.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-remote-fd.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-remote.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-repack.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-replace.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-rerere.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-reset.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-restore.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-rev-list.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-rev-parse.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-revert.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-rm.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-send-pack.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-shortlog.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-show-branch.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-show-index.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-show-ref.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-show.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-sparse-checkout.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-stage.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-stash.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-status.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-stripspace.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-submodule--helper.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-switch.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-symbolic-ref.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-tag.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-unpack-file.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-unpack-objects.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-update-index.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-update-ref.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-update-server-info.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-upload-archive.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-upload-pack.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-var.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-verify-commit.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-verify-pack.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-verify-tag.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-whatchanged.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-worktree.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-write-tree.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/git/git-wrapper.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git-receive-pack.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libiconv/COPYING' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/gettext/COPYING' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libiconv/COPYING' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/xz/COPYING.GPLv3' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libiconv/COPYING' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/gcc-libs/COPYING3' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libiconv/COPYING' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libunistring/LICENSE' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/licenses/libiconv/COPYING' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/zlib1.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/zlib1.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/zlib1.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/bin/bash.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/bin/sh.exe' '/home/shima/Documents/tsb-java/PortableGit/bin/bash.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/git/compat-bash.exe' '/home/shima/Documents/tsb-java/PortableGit/bin/bash.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bunzip2.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bzcat.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bunzip2.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bzip2.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bunzip2.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/d2u.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/dos2unix.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/d2u.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/mac2unix.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/d2u.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/pinentry-w32.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/pinentry.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/pinentry-w32.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/captoinfo.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/infotocap.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/captoinfo.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/tic.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/captoinfo.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/u2d.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/unix2dos.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/u2d.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/unix2mac.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/u2d.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/core_perl/perlbug' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/core_perl/perlthanks' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/core_perl/perlbug' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp932.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp932.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp932.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp950.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp950.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp950.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/gb12345.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/gb12345.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/gb12345.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macJapan.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/macJapan.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/macJapan.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/euc-jp.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/euc-jp.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/euc-jp.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/ksc5601.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/ksc5601.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/ksc5601.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp949.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp949.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp949.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp936.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/cp936.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/cp936.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/big5.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/big5.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/big5.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/jis0212.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/jis0212.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/jis0212.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/jis0208.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/jis0208.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/jis0208.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/shiftjis.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/shiftjis.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/shiftjis.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/euc-kr.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/euc-kr.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/euc-kr.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/gb2312-raw.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/gb2312-raw.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/gb2312-raw.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/euc-cn.enc' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/gb2312.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/euc-cn.enc' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/euc-cn.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/euc-cn.enc' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/tcl8.6/encoding/gb2312.enc' '/home/shima/Documents/tsb-java/PortableGit/mingw64/lib/tcl8.6/encoding/euc-cn.enc' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/subversion' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/svn' '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/subversion' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/svnadmin' '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/subversion' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/svndumpfilter' '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/subversion' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/svnlook' '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/subversion' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/svnsync' '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/subversion' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/svnversion' '/home/shima/Documents/tsb-java/PortableGit/usr/share/bash-completion/completions/subversion' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/git/git-for-windows.ico' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/git/git-for-windows.ico' '/home/shima/Documents/tsb-java/PortableGit/mingw64/share/git/git-for-windows.ico' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.nb' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.no' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.nb' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.utf-8' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.ko' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.ko.utf-8' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.ko' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.nb.utf-8' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.no.utf-8' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/tutor/tutor.nb.utf-8' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html401t.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/html401t.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html401t.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html40f.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/html40f.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html40f.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html401s.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/html401s.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html401s.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html40s.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/html40s.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html40s.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xhtml10f.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/xhtml10f.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xhtml10f.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xhtml10s.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/xhtml10s.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xhtml10s.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/csscomplete.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/csscomplete.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/csscomplete.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/no/LC_MESSAGES/vim.mo' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/nb/LC_MESSAGES/vim.mo' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/lang/no/LC_MESSAGES/vim.mo' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xhtml10t.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/xhtml10t.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xhtml10t.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html401f.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/html401f.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html401f.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/neovim/Neovim/share/locale/no/LC_MESSAGES/nvim.mo' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/locale/nb/LC_MESSAGES/nvim.mo' '/home/shima/Documents/tsb-java/neovim/Neovim/share/locale/no/LC_MESSAGES/nvim.mo' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html40t.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/html40t.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/html40t.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/foxpro.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/foxpro.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/foxpro.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/doxygen.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/doxygen.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/doxygen.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/clojure.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/clojure.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/clojure.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cmake.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/cmake.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/cmake.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/autoit.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/autoit.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/autoit.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nsis.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/nsis.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/nsis.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/baan.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/baan.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/baan.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xhtml11.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/xml/xhtml11.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/xml/xhtml11.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mp.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/mp.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/mp.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xmodmap.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/xmodmap.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xmodmap.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/muttrc.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/muttrc.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/muttrc.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqlanywhere.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sqlanywhere.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sqlanywhere.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hollywood.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/hollywood.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/hollywood.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pfmain.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/pfmain.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/pfmain.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sas.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/sas.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/sas.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/kconfig.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/kconfig.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/kconfig.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libexpat-1.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libexpat-1.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libexpat-1.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libcurl-4.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libcurl-4.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libcurl-4.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libhogweed-6.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libhogweed-6.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libhogweed-6.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libgmp-10.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libgmp-10.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libgmp-10.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libnghttp2-14.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libnghttp2-14.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libnghttp2-14.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libnettle-8.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libnettle-8.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libnettle-8.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libpcre-1.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libpcre-1.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libpcre-1.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libssh2-1.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libssh2-1.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libssh2-1.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libpcre2-8-0.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libpcre2-8-0.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libpcre2-8-0.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libiconv-2.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libiconv-2.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libiconv-2.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/ssl/certs/ca-bundle.trust.crt' '/home/shima/Documents/tsb-java/PortableGit/mingw64/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libjemalloc.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libjemalloc.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libjemalloc.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libzstd.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libzstd.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libzstd.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libssl-1_1-x64.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libssl-1_1-x64.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libssl-1_1-x64.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/awk.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/gawk-5.0.0.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/awk.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/gawk.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/awk.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/ssl/certs/ca-bundle.crt' '/home/shima/Documents/tsb-java/PortableGit/mingw64/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/ssl/cert.pem' '/home/shima/Documents/tsb-java/PortableGit/mingw64/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/unzip.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/zipinfo.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/unzip.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/nano.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/rnano.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/nano.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/ssl/certs/ca-bundle.trust.crt' '/home/shima/Documents/tsb-java/PortableGit/etc/pki/ca-trust/extracted/openssl/ca-bundle.trust.crt' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/ssl/certs/ca-bundle.crt' '/home/shima/Documents/tsb-java/PortableGit/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/ssl/cert.pem' '/home/shima/Documents/tsb-java/PortableGit/etc/pki/ca-trust/extracted/pem/tls-ca-bundle.pem' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/phpcomplete.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/autoload/phpcomplete.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/autoload/phpcomplete.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/tk86.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/tk86.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/tk86.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libunistring-2.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libunistring-2.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libunistring-2.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libstdc++-6.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libstdc++-6.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libstdc++-6.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/tcl86.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/tcl86.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/tcl86.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xs.vim' # original
remove_cmd    '/home/shima/Documents/tsb-java/neovim/Neovim/share/nvim/runtime/syntax/xs.vim' '/home/shima/Documents/tsb-java/PortableGit/usr/share/vim/vim82/syntax/xs.vim' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-remote-ftp.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-remote-ftps.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-remote-ftp.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-remote-http.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-remote-ftp.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-remote-https.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git-remote-ftp.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libcrypto-1_1-x64.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/libcrypto-1_1-x64.dll' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/libcrypto-1_1-x64.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bash.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/sh.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/bash.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/dlls-copied.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/mingw64/libexec/git-core/git.exe' '/home/shima/Documents/tsb-java/PortableGit/mingw64/bin/git.exe' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/msys-perl5_32.dll' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/lib/perl5/core_perl/CORE/msys-perl5_32.dll' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/msys-perl5_32.dll' # duplicate

original_cmd  '/home/shima/Documents/tsb-java/PortableGit/usr/bin/rview.exe' # original
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/rvim.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/rview.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/view.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/rview.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/vim.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/rview.exe' # duplicate
remove_cmd    '/home/shima/Documents/tsb-java/PortableGit/usr/bin/vimdiff.exe' '/home/shima/Documents/tsb-java/PortableGit/usr/bin/rview.exe' # duplicate
                                               
                                               
                                               
######### END OF AUTOGENERATED OUTPUT #########
                                               
if [ $PROGRESS_CURR -le $PROGRESS_TOTAL ]; then
    print_progress_prefix                      
    echo "${COL_BLUE}Done!${COL_RESET}"      
fi                                             
                                               
if [ -z $DO_REMOVE ] && [ -z $DO_DRY_RUN ]     
then                                           
  echo "Deleting script " "$0"             
  rm -f '/home/shima/rmlint.sh';                                     
fi                                             
