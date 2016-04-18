#!/bin/bash

function tag_and_verify()
{
  local  tag=$1
  echo "Adding server tag: $tag"

  rs_api_cmd="rsc"

  i="0"
  while [ $i -lt 3 ]
  do

    # Use the RL10 proxy to access the api
    echo "ADD TAG COMMAND: ${rs_api_cmd} --rl10 cm15 multi_add /api/tags/multi_add \"resource_hrefs[]=$RS_SELF_HREF\" \"tags[]=$tag\""
    ${rs_api_cmd} --rl10 cm15 multi_add /api/tags/multi_add "resource_hrefs[]=$RS_SELF_HREF" "tags[]=$tag"

    sleep 3
    current_tag=$(${rs_api_cmd} --pp --rl10 cm15 by_resource /api/tags/by_resource "resource_hrefs[]=$RS_SELF_HREF" | grep "$tag" || true)

    if test "$current_tag" = "" ; then
      echo "[$i] Failed to add tag. Sleep and retry..."
    else
      echo "[$i] Successfully added tag."
      break
    fi

   sleep 5
   i=$((i+1))
 done
}
