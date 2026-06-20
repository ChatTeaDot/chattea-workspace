#!/usr/bin/env sh
set -eu

git pull
git -C chattea-fe pull
git -C chattea-be pull
git -C chattea-terraform-aws pull
