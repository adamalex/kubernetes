#!/bin/bash

tag_and_verify() {
  while true; do
    rsc --rl10 cm15 multi_add /api/tags/multi_add "resource_hrefs[]=$RS_SELF_HREF" "tags[]=$1"

    tag=$(rsc --rl10 --xm ".name:val(\"$1\")" cm15 by_resource /api/tags/by_resource "resource_hrefs[]=$RS_SELF_HREF")

    if [[ "$tag" = "" ]]; then
      sleep 1
    else
      break
    fi
 done
}
