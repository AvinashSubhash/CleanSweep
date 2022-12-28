#!/bin/sh

PROGRESS_CURR=0
PROGRESS_TOTAL=349                         

# This file was autowritten by rmlint
# rmlint was executed from: /home/kingaiva/github/CleanSweep/
# Your command line was: rmlint /home/kingaiva

RMLINT_BINARY="/usr/bin/rmlint"

# Only use sudo if we're not root yet:
# (See: https://github.com/sahib/rmlint/issues/27://github.com/sahib/rmlint/issues/271)
SUDO_COMMAND="sudo"
if [ "$(id -u)" -eq "0" ]
then
  SUDO_COMMAND=""
fi

USER='kingaiva'
GROUP='kingaiva'

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

   $ rmlint /home/kingaiva

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

handle_emptydir '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/SmartSteamEmu/544390/ugc' # empty folder
handle_emptydir '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/SmartSteamEmu/544390/screenshots' # empty folder
handle_emptydir '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/SmartSteamEmu/544390/remote' # empty folder
handle_emptydir '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/EmptySteamDepot' # empty folder
handle_emptydir '/home/kingaiva/github/Optic-Nerve-Segmentation/unet2/unetsm/assets' # empty folder
handle_emptydir '/home/kingaiva/github/Optic-Nerve-Segmentation/unet1/unetscratch/assets' # empty folder
handle_emptydir '/home/kingaiva/github/Accent-Recognition-System/second_model/model_two/assets' # empty folder
handle_emptydir '/home/kingaiva/github/Accent-Recognition-System/image-text-model/assets' # empty folder
handle_emptydir '/home/kingaiva/Videos' # empty folder
handle_emptydir '/home/kingaiva/Pictures/Screen Shots' # empty folder
handle_emptydir '/home/kingaiva/Pictures' # empty folder
handle_emptyfile '/home/kingaiva/github/server/TekPeek/website/tekpeek/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/tests/functional/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/TekPeek/website/homepage/migrations/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/server/TekPeek/website/website/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/api/files/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/api/payload/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/TekPeek/website/homepage/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/api/session/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/css/font-icons/index.html' # empty file
handle_emptyfile '/home/kingaiva/github/TekPeek/website/tekpeek/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/server/TekPeek/website/homepage/migrations/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/index.html' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/users/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/css/ie.css' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/css/font-icons/font-awesome/index.html' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/data/index.html' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/tests/unit/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/TekPeek/website/website/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/server/TekPeek/website/homepage/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/css/font-icons/glyphicons/index.html' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/css/index.html' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/css/font-icons/entypo/index.html' # empty file
handle_emptyfile '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/api/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/errors/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/index.html' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/main/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/tests/__init__.py' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/vertical-timeline/index.html' # empty file
handle_emptyfile '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/index.html' # empty file

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/SmartSteamEmu/Plugins/x86/SSEFirewall.ini' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/SmartSteamEmu/Plugins/x64/SSEFirewall.ini' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/SmartSteamEmu/Plugins/x86/SSEFirewall.ini' # duplicate

original_cmd  '/home/kingaiva/Screenshots/Thu Dec 15 15:44:34 IST 2022.jpg' # original
remove_cmd    '/home/kingaiva/Screenshots/Thu Dec 15 15:44:58 IST 2022.jpg' '/home/kingaiva/Screenshots/Thu Dec 15 15:44:34 IST 2022.jpg' # duplicate

original_cmd  '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/arch.png' # original
remove_cmd    '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/archlinux.png' '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/arch.png' # duplicate

original_cmd  '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/Manjaro.i686.png' # original
remove_cmd    '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/manjaro.png' '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/Manjaro.i686.png' # duplicate
remove_cmd    '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/Manjaro.x86_64.png' '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/Manjaro.i686.png' # duplicate
remove_cmd    '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/manjarolinux.png' '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/Manjaro.i686.png' # duplicate

original_cmd  '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/pop-os.png' # original
remove_cmd    '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/pop.png' '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/pop-os.png' # duplicate

original_cmd  '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/red.png' # original
remove_cmd    '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/redhat.png' '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/red.png' # duplicate

original_cmd  '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/gnu-linux.png' # original
remove_cmd    '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/kernel.png' '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/gnu-linux.png' # duplicate
remove_cmd    '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/lfs.png' '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/gnu-linux.png' # duplicate
remove_cmd    '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/linux.png' '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/gnu-linux.png' # duplicate
remove_cmd    '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/unknown.png' '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/gnu-linux.png' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/Mono/etc/mono/2.0/web.config' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/2.0/web.config' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/Mono/etc/mono/2.0/web.config' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/out.json' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/out.json' '/home/kingaiva/github/server/TekPeek/website/out.json' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/homepage/models.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/homepage/models.py' '/home/kingaiva/github/server/TekPeek/website/homepage/models.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/homepage/urls.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/homepage/urls.py' '/home/kingaiva/github/server/TekPeek/website/homepage/urls.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/homepage/migrations/0001_initial.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/homepage/migrations/0001_initial.py' '/home/kingaiva/github/server/TekPeek/website/homepage/migrations/0001_initial.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/homepage/migrations/0002_delete_cleartrash.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/homepage/migrations/0002_delete_cleartrash.py' '/home/kingaiva/github/server/TekPeek/website/homepage/migrations/0002_delete_cleartrash.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/homepage/templates/index.html' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/homepage/templates/index.html' '/home/kingaiva/github/server/TekPeek/website/homepage/templates/index.html' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/img/news-template.png' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/img/news-template.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/img/news-template.png' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/img/tekpeek.jpg' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/img/tekpeek.jpg' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/img/tekpeek.jpg' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/admin.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/admin.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/admin.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/urls.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/urls.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/urls.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0003_remove_data_blog_id_data_blog_auth_data_blog_date_and_more.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0003_remove_data_blog_id_data_blog_auth_data_blog_date_and_more.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0003_remove_data_blog_id_data_blog_auth_data_blog_date_and_more.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0004_data_bolg_image.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0004_data_bolg_image.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0004_data_bolg_image.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0006_alter_data_blog_date.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0006_alter_data_blog_date.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0006_alter_data_blog_date.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0007_alter_data_blog_date.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0007_alter_data_blog_date.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0007_alter_data_blog_date.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0010_highlight.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0010_highlight.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0010_highlight.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0011_alter_data_blog_image_alter_news_image_link.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0011_alter_data_blog_image_alter_news_image_link.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0011_alter_data_blog_image_alter_news_image_link.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0013_delete_datahandler.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0013_delete_datahandler.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0013_delete_datahandler.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0014_auto_20220829_0442.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0014_auto_20220829_0442.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0014_auto_20220829_0442.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/website/settings.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/website/settings.py' '/home/kingaiva/github/server/TekPeek/website/website/settings.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/website/asgi.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/website/asgi.py' '/home/kingaiva/github/server/TekPeek/website/website/asgi.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/website/wsgi.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/website/wsgi.py' '/home/kingaiva/github/server/TekPeek/website/website/wsgi.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/tpw.svg' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/tpw.svg' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/tpw.svg' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/assets/tpw.svg' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/tpw.svg' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/Power-Pass.jpg' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/fixed_img/Power-Pass.jpg' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/Power-Pass.jpg' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/assets/fixed_img/Power-Pass.jpg' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/Power-Pass.jpg' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/laboratory online logo template social media illustration.png' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/fixed_img/laboratory online logo template social media illustration.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/laboratory online logo template social media illustration.png' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/assets/fixed_img/laboratory online logo template social media illustration.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/laboratory online logo template social media illustration.png' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/naive-bayes.png' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/fixed_img/naive-bayes.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/naive-bayes.png' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/assets/fixed_img/naive-bayes.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/naive-bayes.png' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/tekpeek-transparent-small.png' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/fixed_img/tekpeek-transparent-small.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/tekpeek-transparent-small.png' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/assets/fixed_img/tekpeek-transparent-small.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/tekpeek-transparent-small.png' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/js/scripts.js' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/js/scripts.js' '/home/kingaiva/github/server/TekPeek/website/static/dist/js/scripts.js' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/js/scripts.js' '/home/kingaiva/github/server/TekPeek/website/static/dist/js/scripts.js' # duplicate

original_cmd  '/home/kingaiva/github/Codechef-problems/codechef-march-3.py' # original
remove_cmd    '/home/kingaiva/warp-status.txt' '/home/kingaiva/github/Codechef-problems/codechef-march-3.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0005_rename_bolg_image_data_blog_image.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0005_rename_bolg_image_data_blog_image.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0005_rename_bolg_image_data_blog_image.py' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/Mono/etc/mono/2.0/Browsers/Compat.browser' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/2.0/Browsers/Compat.browser' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/Mono/etc/mono/2.0/Browsers/Compat.browser' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/4.0/Browsers/Compat.browser' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/Mono/etc/mono/2.0/Browsers/Compat.browser' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/4.5/Browsers/Compat.browser' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/Mono/etc/mono/2.0/Browsers/Compat.browser' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/4.0/settings.map' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/4.5/settings.map' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/4.0/settings.map' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/homepage/tests.py' # original
remove_cmd    '/home/kingaiva/github/server/TekPeek/website/tekpeek/tests.py' '/home/kingaiva/github/server/TekPeek/website/homepage/tests.py' # duplicate
remove_cmd    '/home/kingaiva/github/TekPeek/website/homepage/tests.py' '/home/kingaiva/github/server/TekPeek/website/homepage/tests.py' # duplicate
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/tests.py' '/home/kingaiva/github/server/TekPeek/website/homepage/tests.py' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/Mono/etc/mono/mconfig/config.xml' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/mconfig/config.xml' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/Mono/etc/mono/mconfig/config.xml' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/core/__init__.py' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/__init__.py' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/core/__init__.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/escalate.py' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/escalate.py' '/home/kingaiva/github/byob/byob/modules/escalate.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/icloud.py' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/icloud.py' '/home/kingaiva/github/byob/byob/modules/icloud.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/keylogger.py' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/keylogger.py' '/home/kingaiva/github/byob/byob/modules/keylogger.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/outlook.py' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/outlook.py' '/home/kingaiva/github/byob/byob/modules/outlook.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/packetsniffer.py' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/packetsniffer.py' '/home/kingaiva/github/byob/byob/modules/packetsniffer.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/portscanner.py' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/portscanner.py' '/home/kingaiva/github/byob/byob/modules/portscanner.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/webcam.py' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/webcam.py' '/home/kingaiva/github/byob/byob/modules/webcam.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/static/byob_logo_email-black.png' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/byob_logo_email-black.png' '/home/kingaiva/github/byob/byob/static/byob_logo_email-black.png' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/au.png' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/hm.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/au.png' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0009_news.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0009_news.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0009_news.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/homepage/admin.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/homepage/admin.py' '/home/kingaiva/github/server/TekPeek/website/homepage/admin.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/fr.png' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/gf.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/fr.png' # duplicate
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/re.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/fr.png' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0001_initial.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0001_initial.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0001_initial.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/bv.png' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/no.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/bv.png' # duplicate
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/sj.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/bv.png' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/us.png' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/xxx.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/flags/us.png' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/os/darwin.png' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/os/osx.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/os/darwin.png' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/os/win.png' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/os/win32.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/os/win.png' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/loader-1.gif' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/aci-tree/image/load-root.gif' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/loader-1.gif' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/os/linux.png' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/os/linux2.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/os/linux.png' # duplicate
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/os/nix.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/images/os/linux.png' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/ckeditor/plugins/icons.png' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/ckeditor/skins/moono/icons.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/ckeditor/plugins/icons.png' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/apps.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/apps.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/apps.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/FixedHeader-3.0.0/css/fixedHeader.bootstrap.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/FixedHeader-3.0.0/css/fixedHeader.foundation.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/FixedHeader-3.0.0/css/fixedHeader.bootstrap.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/FixedHeader-3.0.0/css/fixedHeader.bootstrap.min.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/FixedHeader-3.0.0/css/fixedHeader.foundation.min.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/FixedHeader-3.0.0/css/fixedHeader.bootstrap.min.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Select-1.0.1/css/select.dataTables.min.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Select-1.0.1/css/select.jqueryui.min.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Select-1.0.1/css/select.dataTables.min.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Select-1.0.1/css/select.dataTables.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Select-1.0.1/css/select.jqueryui.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Select-1.0.1/css/select.dataTables.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Responsive-1.0.7/css/responsive.dataTables.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Responsive-1.0.7/css/responsive.jqueryui.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Responsive-1.0.7/css/responsive.dataTables.css' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0008_alter_data_blog_date.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0008_alter_data_blog_date.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0008_alter_data_blog_date.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0002_alter_data_blog_content.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0002_alter_data_blog_content.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0002_alter_data_blog_content.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/delhi-metro-planner.png' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/fixed_img/delhi-metro-planner.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/delhi-metro-planner.png' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/assets/fixed_img/delhi-metro-planner.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/delhi-metro-planner.png' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/views.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/views.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/views.py' # duplicate

original_cmd  '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/driver.png' # original
remove_cmd    '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/memtest.png' '/home/kingaiva/Downloads/wrench-1080p/dedsec/icons/driver.png' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/css/jquery.terminal-2.12.0.min.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/css/jquery.terminal.min.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/css/jquery.terminal-2.12.0.min.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/css/jquery.terminal-2.12.0.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/css/jquery.terminal.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/css/jquery.terminal-2.12.0.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/screenshot.py' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/screenshot.py' '/home/kingaiva/github/byob/byob/modules/screenshot.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/manage.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/manage.py' '/home/kingaiva/github/server/TekPeek/website/manage.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/form-password.almost-flat.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/form-password.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/form-password.almost-flat.css' # duplicate
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/form-password.gradient.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/form-password.almost-flat.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/form-password.almost-flat.min.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/form-password.gradient.min.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/form-password.almost-flat.min.css' # duplicate
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/form-password.min.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/form-password.almost-flat.min.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/markdownarea.almost-flat.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/markdownarea.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/markdownarea.almost-flat.css' # duplicate
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/markdownarea.gradient.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/markdownarea.almost-flat.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/markdownarea.almost-flat.min.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/markdownarea.gradient.min.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/markdownarea.almost-flat.min.css' # duplicate
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/markdownarea.min.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/markdownarea.almost-flat.min.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/notify.almost-flat.min.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/notify.gradient.min.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/notify.almost-flat.min.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/notify.almost-flat.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/notify.gradient.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/uikit/addons/css/notify.almost-flat.css' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Responsive-1.0.7/css/responsive.dataTables.min.css' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Responsive-1.0.7/css/responsive.jqueryui.min.css' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/Responsive-1.0.7/css/responsive.dataTables.min.css' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/homepage/apps.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/homepage/apps.py' '/home/kingaiva/github/server/TekPeek/website/homepage/apps.py' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/process.py' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/process.py' '/home/kingaiva/github/byob/byob/modules/process.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/homepage/views.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/homepage/views.py' '/home/kingaiva/github/server/TekPeek/website/homepage/views.py' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/js/blog-scripts.js' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/js/blog-scripts.js' '/home/kingaiva/github/server/TekPeek/website/static/dist/js/blog-scripts.js' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0012_datahandler.py' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/tekpeek/migrations/0012_datahandler.py' '/home/kingaiva/github/server/TekPeek/website/tekpeek/migrations/0012_datahandler.py' # duplicate

original_cmd  '/home/kingaiva/github/hiddentools.dev/public/favicon.ico' # original
remove_cmd    '/home/kingaiva/github/hiddentools.dev/src/assets/hiddentools-logo.png' '/home/kingaiva/github/hiddentools.dev/public/favicon.ico' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.4/slide-03-front.png' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.5/slide-04-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.4/slide-03-front.png' # duplicate

original_cmd  '/home/kingaiva/Screenshots/5StepsToCreateThePerfectRole-PlayingVideo_Blogpost@2x (1).png' # original
remove_cmd    '/home/kingaiva/Screenshots/5StepsToCreateThePerfectRole-PlayingVideo_Blogpost@2x.webp' '/home/kingaiva/Screenshots/5StepsToCreateThePerfectRole-PlayingVideo_Blogpost@2x (1).png' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/db.sqlite3' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/db.sqlite3' '/home/kingaiva/github/server/TekPeek/website/db.sqlite3' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/avinash.jpg' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/fixed_img/avinash.jpg' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/avinash.jpg' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/assets/fixed_img/avinash.jpg' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/avinash.jpg' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/bg-signup.jpg' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/fixed_img/bg-signup.jpg' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/bg-signup.jpg' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/assets/fixed_img/bg-signup.jpg' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/bg-signup.jpg' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/img/News_Template_2_1.png' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/img/News_Template_2_1.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/img/News_Template_2_1.png' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/js/mdb.min.js' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/js/mdb.min.js' '/home/kingaiva/github/server/TekPeek/website/static/dist/js/mdb.min.js' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fav.ico' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/fav.ico' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fav.ico' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/assets/fav.ico' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fav.ico' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/2.0/DefaultWsdlHelpGenerator.aspx' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/4.0/DefaultWsdlHelpGenerator.aspx' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/2.0/DefaultWsdlHelpGenerator.aspx' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/4.5/DefaultWsdlHelpGenerator.aspx' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/2.0/DefaultWsdlHelpGenerator.aspx' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/ckeditor/plugins/icons_hidpi.png' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/ckeditor/skins/moono/icons_hidpi.png' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/ckeditor/plugins/icons_hidpi.png' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/js/jquery.terminal-2.12.0.min.js' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/js/jquery.terminal.min.js' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/js/jquery.terminal-2.12.0.min.js' # duplicate

original_cmd  '/home/kingaiva/github/hiddentools.dev/assets/hiddentools-twitter-image.jpg' # original
remove_cmd    '/home/kingaiva/github/hiddentools.dev/src/assets/hiddentools-twitter-image.jpg' '/home/kingaiva/github/hiddentools.dev/assets/hiddentools-twitter-image.jpg' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.02/slide-02-back.jpg' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.03/slide-01-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.02/slide-02-back.jpg' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/jQuery-1.11.3/jquery-1.11.3.min.js' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-1.11.3.min.js' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/datatables/jQuery-1.11.3/jquery-1.11.3.min.js' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/welcome.png' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/fixed_img/welcome.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/welcome.png' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/assets/fixed_img/welcome.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/welcome.png' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DEV.00-Placeholder-front.png' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/MNV.01.01/slide-04-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DEV.00-Placeholder-front.png' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/OSS.01.02/slide02-front.png' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/OSS.01.02/slide04-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/OSS.01.02/slide02-front.png' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/Mono/etc/mono/browscap.ini' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/MonoBleedingEdge/etc/mono/browscap.ini' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/Mono/etc/mono/browscap.ini' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/css/template-styles.css' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/css/template-styles.css' '/home/kingaiva/github/server/TekPeek/website/static/dist/css/template-styles.css' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/css/styles.css' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/css/styles.css' '/home/kingaiva/github/server/TekPeek/website/static/dist/css/styles.css' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/css/styles.css' '/home/kingaiva/github/server/TekPeek/website/static/dist/css/styles.css' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/img/news-one.png' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/img/news-one.png' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/img/news-one.png' # duplicate

original_cmd  '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/js/jquery.terminal-2.12.0.js' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/js/jquery.terminal.js' '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/assets/js/jquery-terminal/js/jquery.terminal-2.12.0.js' # duplicate

original_cmd  '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/bg-masthead.jpg' # original
remove_cmd    '/home/kingaiva/github/TekPeek/website/static/dist/assets/fixed_img/bg-masthead.jpg' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/bg-masthead.jpg' # duplicate
remove_cmd    '/home/kingaiva/github/AvinashSubhash.github.io/dist/assets/fixed_img/bg-masthead.jpg' '/home/kingaiva/github/server/TekPeek/website/static/dist/assets/fixed_img/bg-masthead.jpg' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.03/slide-01-front.png' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.03/slide-1-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.03/slide-01-front.png' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/vote-1/slide-01-front.png' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/vote-2/slide-01-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/vote-1/slide-01-front.png' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/vote-3/slide-01-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/vote-1/slide-01-front.png' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/vote-1/slide-01-back.jpg' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/vote-2/slide-01-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/vote-1/slide-01-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/vote-3/slide-01-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/vote-1/slide-01-back.jpg' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.02/slide-03-back.jpg' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.03/slide-04-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.02/slide-03-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/IVC.01.03/slide-03-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.02/slide-03-back.jpg' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.04/slide-05-back.jpg' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/IVC.01.04/slide-05-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.04/slide-05-back.jpg' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.04/slide-03-back.jpg' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/IVC.01.04/slide-03-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.04/slide-03-back.jpg' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.5/slide-01a-front.png' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.5/slide-01b-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.5/slide-01a-front.png' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.5/slide-01c-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.5/slide-01a-front.png' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/slide-04-front.png' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.02/slide-04-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/slide-04-front.png' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/IVC.01.02/slide-04-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/slide-04-front.png' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/IVC.01.03/slide-04-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/slide-04-front.png' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/ODS.01.01/slide-01-front.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/slide-04-front.png' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/ODS.01.01/slide-03-back.jpg' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/ODS.01.02/slide-02-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/ODS.01.01/slide-03-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/ODS.01.02/slide-03-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/ODS.01.01/slide-03-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/ODS.01.03/slide-03-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/ODS.01.01/slide-03-back.jpg' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/IVC.01.01/slide-03-back.jpg' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/IVC.01.01/slide-04-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/IVC.01.01/slide-03-back.jpg' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Academy/Officers/AcademyOfficer.png' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Officers/Wheeler.png' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Academy/Officers/AcademyOfficer.png' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.5/slide-01a-back.jpg' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.5/slide-01b-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.5/slide-01a-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.5/slide-01c-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/NWT-UhS58K/NWT.01.5/slide-01a-back.jpg' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DEV.00-Placeholder-back.jpg' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.01/slide-04-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DEV.00-Placeholder-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DSL.01.02/slide-04-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DEV.00-Placeholder-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/IVC.01.02/slide-04-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DEV.00-Placeholder-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/IVC.01.03/slide-04-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DEV.00-Placeholder-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/MNV.01.01/slide-04-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DEV.00-Placeholder-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/ODS.01.01/slide-01-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DEV.00-Placeholder-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/OSS.01.02/slide01-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/DEV.00-Placeholder-back.jpg' # duplicate

original_cmd  '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/OSS.01.01/slide04-back.jpg' # original
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/OSS.01.01/slide05-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/OSS.01.01/slide04-back.jpg' # duplicate
remove_cmd    '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/OSS.01.02/slide05-back.jpg' '/home/kingaiva/niteteam4/NITE.Team.4.v23.06.2021/nt4_Data/PlayerAssets/Briefing/OSS.01.01/slide04-back.jpg' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/xmrig/xmrig_linux2' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/xmrig/xmrig_linux2' '/home/kingaiva/github/byob/byob/modules/xmrig/xmrig_linux2' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/xmrig/xmrig_darwin' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/xmrig/xmrig_darwin' '/home/kingaiva/github/byob/byob/modules/xmrig/xmrig_darwin' # duplicate

original_cmd  '/home/kingaiva/github/byob/byob/modules/xmrig/xmrig_win32' # original
remove_cmd    '/home/kingaiva/github/byob/web-gui/buildyourownbotnet/modules/xmrig/xmrig_win32' '/home/kingaiva/github/byob/byob/modules/xmrig/xmrig_win32' # duplicate
                                               
                                               
                                               
######### END OF AUTOGENERATED OUTPUT #########
                                               
if [ $PROGRESS_CURR -le $PROGRESS_TOTAL ]; then
    print_progress_prefix                      
    echo "${COL_BLUE}Done!${COL_RESET}"      
fi                                             
                                               
if [ -z $DO_REMOVE ] && [ -z $DO_DRY_RUN ]     
then                                           
  echo "Deleting script " "$0"             
  rm -f '/home/kingaiva/github/CleanSweep/rmlint.sh';                                     
fi                                             
