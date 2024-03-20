#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Build the project.
# hugo -t <your theme>
hugo -t hugo-book

# Go to public folder, submodule commit
cd public
# Add changes to git.
git add .

# Commit changes.
msg="rebuilding site $(date)"
if [ $# -eq 1 ]; then
  msg="$1"
fi
git commit -m "$msg"

# Push source and build repos.
git push origin github-pages

# Come back up to the project root
cd ..

# Commit and push to main branch
git add .

msg="rebuilding site $(date)"
if [ $# -eq 1 ]; then
  msg="$1"
fi
git commit -m "$msg"

git push origin main
