#!/usr/bin/env sh
set -eu

clone_if_missing() {
  dir="$1"
  url="$2"

  if [ -d "$dir/.git" ]; then
    echo "$dir already exists"
    return
  fi

  git clone "$url" "$dir"
}

clone_if_missing chattea-fe https://github.com/ChatTeaDot/chattea-fe.git
clone_if_missing chattea-be https://github.com/ChatTeaDot/chattea-be.git
clone_if_missing chattea-terraform-aws https://github.com/ChatTeaDot/chattea-terraform-aws.git
