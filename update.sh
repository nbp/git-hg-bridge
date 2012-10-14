#!/bin/sh -e

# These paths are relative to $hgrepo
lockfile=./.hg/sync.lock
gitClone=./.hg/git
repoPath=./.hg/repos
bridgePath=./.hg/bridge
hgConf=./.hg/hgrc
pullFlag=./.hg/pull.run

usage() {
    echo 1>&2 'update.sh --target <bridge-dir> --source <bridge-dir>

Update a git-hg bridge with another git-hg bridge.  If the target does not
exists, it is created as an hard-linked clone of the original repositories. When
the target exists, the script pull changes from the given source and hard-link
changes with the source to save space.

If the target is not specified it defaults to $HOME environment variable.
If the source is not specified and the clone already exists, it is extracted
from git configuration system.

The target must be different than the source.

Options:
  --source <dir>        Directory containing a git-hg bridge which would be used
                        for updating the target.
  --target <dir>        Directory in which sources changes will be merged into.
  -s <dir>              Alias for --source <dir>.
  -t <dir>              Alias for --target <dir>.

'
    exit 1
}

#####################
# Process Arguments #
#####################

src=""
dst=""
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
            -s*) longarg="$longarg --source";;
            -v*) longarg="$longarg --verbose";;
            -t*) longarg="$longarg --target";;
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
        --source) argfun=set_src;;
        --target) argfun=set_dst;;
        --verbose) verbose=true;;
        --help) usage;;
        -*) usage;;
        *) usage;;
      esac
    done
  else
    case $argfun in
      set_*)
        eval ${argfun#set_}=$arg
        ;;
    esac
    argfun=""
  fi
done

# Check inputs.

if test -z "$dst"; then
  dst=$HOME
fi

if test -z "$src"; then
  if test -d "$dst/.hg"; then
    src=$(GIT_DIR="$dst/.hg/git" git config hooks.bridge.source)
  else
    usage
  fi
fi

test "$src" = "$dst" && usage;

if $verbose ; then
  set -x;
fi

############################
# Update target repository #
############################

# Take a command and append the source directory and the destination directory
# with the same relative directory, this prevent doing to many typo :)
copyrel() {
  local rel="$1"
  shift;
  test -e "$src$rel";
  "$@" "$src$rel" "$dst$rel";
}

createMercurial() {
  copyrel "" hg clone -U

  # Erase the default hgrc and replace it by one which handle the bridge and
  # remote connection as well as updates of hark-links.
  echo > "$dst/.hg/hgrc" '
$(# Copy paths from the original file.
  # This section must exists at least to have one remote mercurial.
  sed -n '/^\[paths\]/ { p; :start; n; /^\[/ { Q }; p; b start; }' \
    "$src/.hg/hgrc"
)

[ui]
ssh = ssh -l "$HGUSER"

[git]
intree = 0

$(# Copy extensions from the original file.
  # This section must exists at least to have the bookmarks extension.
  sed -n '/^\[extensions\]/ { p; h; :start; n; /^\[/ { Q }; p; b start; }' \
    "$src/.hg/hgrc"
)
# Enable the relink extention to hard link after pulls.
relink =
'
}

updateMercurial() {
  # Synchronize mercurial
  cd "$dst"
  hg pull "$src"
  # :TODO: benchmark in production
  hg relink "$src"
  cd -
}

createGit() {
  copyrel "/.hg/git" git clone --mirror

  # Add push hook.
  mkdir -p "$dst/.hg/git/hooks"
  cp "$src/git-hg-bridge/push.sh" "$dst/.hg/git/hooks/push.sh"
}

updateGit() {
  # Synchronize git
  GIT_DIR="$dst/.hg/git"
  export GIT_DIR
  git fetch --all -uf origin
  # :TODO: benchmark in production
  git relink "$src/.hg/git"
}

createBridge() {
  copyrel "/.hg/git-mapfile" cp
}

updateBridge() {
  # Merge mapfiles by doing a merge sort and by removing duplicates.
  sort -muk 2 "$src/.hg/git-mapfile" "$dst/.hg/git-mapfile" \
    > "$dst/.hg/git-mapfile.merge"
  mv "$dst/.hg/git-mapfile.merge" "$dst/.hg/git-mapfile"
}

createHome() {
  if test "$HOME" = "$dst"; then
    # Make the git-shell-commands visible to current user.
    ln -s "$src/git-hg-bridge/git-shell-commands" "$dst/git-shell-commands"
    # Make the git-side visible as mercurial.git
    ln -s "$dst/.hg/git" "$dst/mercurial.git"
  fi

  # Save setup config in git config file.
  GIT_DIR="$dst/.hg/git"
  export GIT_DIR
  git config --add hooks.bridge.source "$src"
  git config --add hooks.bridge.mercurial "$dst"
}

createClone() {
  createMercurial
  createGit
  createBridge
  createHome
}

updateClone() {
  # :TODO: lock to prevent pushes with corrupted mapfile
  updateMercurial
  updateGit
  updateBridge
}

if test -d "$dst/.hg"; then
  updateClone
else
  createClone
fi

