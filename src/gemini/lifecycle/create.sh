#!/bin/bash
set -e

# Add Gemini alias, opting into GEMINI_CLI_YOLO if the flag was set at image-build
# time via the feature's yolo option. NO_BROWSER is always set — there is no browser
# in a devcontainer. (Alias is appended at create time, not every start, to avoid
# duplicating the line in ~/.zshrc on restart.)
if [ -f /usr/local/share/devcontainer/.gemini-skip-permissions ]; then
  echo 'alias gemini="GEMINI_CLI_YOLO=true NO_BROWSER=true /usr/local/bin/gemini"' >> ~/.zshrc
else
  echo 'alias gemini="NO_BROWSER=true /usr/local/bin/gemini"' >> ~/.zshrc
fi
