#!/bin/bash

git add -A && git commit -m"Update" && git push origin HEAD:blog-code
hexo g -d