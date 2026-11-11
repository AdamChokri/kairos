#!/usr/bin/env bash
# ci/scripts/build_images.sh [--cleanup] - builds the two images with the agent's Docker and writes each to
# images/<name>.tar with `docker save` (plan WP4.2). Trivy (`trivy image --input`) and later Syft read those
# files: no scanner container ever gets the Docker socket, which would mean root on the agent.
# Tags are local to the agent and carry the commit: kairos-api:ci-<12 characters>, kairos-web:ci-<12 characters>.
# `--cleanup` (the ci stage's post action) removes this build's images and the image files, so the disk does not fill.
set -Eeuo pipefail
# shellcheck source=./lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTROL=build_images

sha="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
tag="ci-$sha"

if [[ ${1:-} == --cleanup ]]; then
  for name in api web; do docker rmi --force "kairos-$name:$tag" >/dev/null 2>&1 || true; done
  rm -rf "$ROOT/images"
  echo "build_images: images of $tag and image files removed"
  exit 0
fi

mkdir -p "$ROOT/images"
# DOCKER_BUILDKIT keeps the build output readable; the context of each image is its own folder.
docker build --pull=false --build-arg "GIT_SHA=$sha" -t "kairos-api:$tag" "$ROOT/backend"
docker build --pull=false --build-arg "GIT_SHA=$sha" -t "kairos-web:$tag" "$ROOT/frontend"
for name in api web; do
  docker save -o "$ROOT/images/kairos-$name.tar" "kairos-$name:$tag"
done
printf '%s\n' "$tag" > "$ROOT/images/tag.txt"
ls -l "$ROOT/images"
echo "build_images: passed (kairos-api:$tag and kairos-web:$tag, saved under images/)"
