#!/bin/bash
cd /home/lingmo/iso-build
git init -q
git add -A
git commit -q -m "Initial ISO builder: livecd-creator + self-built repos"
git remote add origin https://github.com/Matrinsoft/iso-build.git
git push -u origin main
echo "push rc=$?"
git log --oneline -1
