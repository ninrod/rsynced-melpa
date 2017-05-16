#!/usr/bin/env bash

SCRIPTPATH=$(cd $(dirname $0); pwd -P) && cd $SCRIPTPATH
elpa_clone_path=.elpa-clone

rm -rf $elpa_clone_path
git clone --depth 1 https://github.com/dochang/elpa-clone.git $elpa_clone_path

function clone {
  echo "Updating mirror for $2 ($1)"
  emacs -l "$elpa_clone_path/elpa-clone.el" -nw --batch --eval="(elpa-clone \"$1\" \"$SCRIPTPATH/$2\")"
}

clone "http://orgmode.org/elpa/" "org"
# clone "https://elpa.gnu.org/packages/" "gnu"
# clone "rsync://melpa.org/packages/" "melpa"
