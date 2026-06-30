#!/bin/bash
set -e

if [ ! -f /dc-volumes/commandhistory/.zsh_profile ]; then
  touch /dc-volumes/commandhistory/.zsh_profile
fi

cat /dc-volumes/commandhistory/.zsh_profile >> ~/.zshrc
