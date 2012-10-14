#!/bin/sh -e

# These paths are relative to $hgrepo
lockfile=./.hg/sync.lock
gitClone=./.hg/git
repoPath=./.hg/repos
bridgePath=./.hg/bridge
hgConf=./.hg/hgrc
pullFlag=./.hg/pull.run

usage() {
    echo 1>&2 'setup.sh --master --git <git> --mapfile <mapfile> --hg <hg> <master>
setup.sh --master --bridge <remote> --hg <hg> <master>
setup.sh --master --hg <hg> <master>
setup.sh --user <user> <master>

Create a master or user git-hg-bridge. This script setup a mercurial repository
and use hg-git to initialize the bridge. The initialization is done by either
doing the convertion or by fetching necesseray information from another bridge.

Options:
  --user <dir>          Create a user git-hg-bridge as an hardlinked clone of a
                        master bridge.
  --master              Create a master git-hg-bridge.

  --git <git>           Git repository with converted changesets.
  --mapfile <mapfile>   File mapping git commits to mercurial changesets.
  --bridge <server>     Location of a remote git-hg-bridge.

  --hg <hg>=<path>      One entry of mercurial paths, multiple accepted.
  <master>              Location of a master git-hg-bridge.
'
    exit 1
}

#####################
# Process Arguments #
#####################

cfguser=false
user=""
master=""
cfgmaster=false
git=""
mapfile=""
remote=""
hgpaths=false
echo '' > hgpaths
verbose=false

argfun=""
for arg; do
  if test -z "$argfun"; then
    case $arg in
      -*)
        longarg=""
        sarg="$arg"
        while test "$sarg" != "-"; do
          case $sarg in
            --*) longarg=$arg; sarg="--";;
            -u*) longarg="$longarg --user";;
            -g*) longarg="$longarg --git";;
            -m*) longarg="$longarg --mapfile";;
            -b*) longarg="$longarg --bridge";;
            -h*) longarg="$longarg --hg";;
            -v*) longarg="$longarg --verbose";;
            -*) usage;;
          esac
          # remove the first letter option
          sarg="-${sarg#??}"
        done
        ;;
      *) longarg=$arg;;
    esac
    for larg in $longarg; do
      case $larg in
        --user)
          cfguser=true;
          argfun=set_user;;
        --git) argfun=set_git;;
        --mapfile) argfun=set_mapfile;;
        --bridge) argfun=set_bridge;;
        --hg)
          hgpaths=true;
          argfun=app_hgpaths;;
        --master) cfgmaster=true;;
        --verbose) verbose=true;;
        --help) usage;;
        -*) usage;;
        *) if test -z "$master"; then
             master="$larg"
           else
             usage
           fi;;
      esac
    done
  else
    case $argfun in
      set_*)
        eval ${argfun#set_}=$arg
        ;;
      app_*)
        echo "$arg" >> ${argfun#app_}
        ;;
    esac
    argfun=""
  fi
done

# Check inputs.
if $cfguser; then
  \! $cfgmaster || usage;
  test -z "$git" || usage;
  test -z "$mapfile" || usage;
  test -z "$remote" || usage;
  test -n "$master" || usage;
elif $cfgmaster; then
  $hgpaths || usage;
  test -z "$git" -o -z "$remote" || usage;
  test -z "$mapfile" -o -z "$remote" || usage;
  test \( -n "$git" -a -n "$mapfile" \) \
    -o \( -z "$git" -a -z "$mapfile" \) \
    || usage;
  test -n "$master" || usage;
else
  usage
fi

if $verbose ; then
  set -x;
fi

###########################
# Setup bridge repository #
###########################

if $cfguser; then
  exec ./update.sh --source "$master" --target "$master/users/$user";
fi

# Return the list of repositories from which data are fetched.  This sed
# script extract the data from the list of paths of the hgrc file.
getPullRepos() {
    sed -n '
      /^\[paths\]$/ {
        :newline;
        n;
        /^ *#/ { b newline; };
        /=/ {
          s/=.*//;
          /-pushonly/ { b newline; };
          p;
          b newline;
        }
      }' $hgConf
}

mkdir -p "$master"
hg init "$master"
echo '[paths]
$(cat hgpaths)

[ui]
ssh = ssh -l "$HGUSER"

[git]
intree = 0

[extensions]
hgext.bookmarks =
hggit =
'

rm -f hgpaths
hgConf="$master/.hg/hgrc"

# Check if there is any pending changes.
cd "$master"
for edgeName in $(getPullRepos); do
    hg pull $edgeName
done
cd -

if test -n "$remote"; then
  ssh "$remote" mapfile > ./mapfile
  git="$remote:bridge.git"
  mapfile=./mapfile
fi

if test -n "$git"; then
  git clone --mirror "$git" "$master/.hg/git"
  cp "$mapfile" "$master/.hg/git-mapfile"
fi

if test -n "$remote"; then
  rm -f "$mapfile"
fi

# TODO: do the first hg gimport and hg gexport such as there is no surprise!

