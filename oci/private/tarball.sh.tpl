#!/usr/bin/env bash
set -o pipefail -o errexit -o nounset

readonly bsdtar="{{tar}}"
readonly jq="{{jq}}"
readonly image="{{image}}"
readonly mtree="{{mtree}}"
readonly output="{{output}}"
readonly tags="{{tags}}"

readonly tree_relative_manifest_path=$(jq -r '.manifests[0].digest | sub(":"; "/")' "$image/index.json")

readonly manifest_path=$(mktemp)
readonly final_mtree_path=$(mktemp)

readonly jq_filter='.[0] |= {
    "Config": ( "blobs/" + ( $manifest[0].config.digest | sub(":"; "/") ) + ".tar.gz" ), 
    "RepoTags": $repotags | split("\n") | map(select(. != "")), 
    "Layers": $manifest[0].layers | map("blobs/" + . + ".tar.gz")
}'

jq -n "$jq_filter" > $manifest_path  \
   --slurpfile manifest "$image/blobs/$tree_relative_manifest_path" \
   --rawfile repotags $tags

cat $mtree > $final_mtree_path
echo "./manifest.json uid=0 gid=0 time=0 mode=0755 type=file content=$manifest_path" >> $final_mtree_path

bsdtar --create --file $output @$final_mtree_path
