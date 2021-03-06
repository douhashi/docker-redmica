#!/usr/bin/env bash
set -Eeuo pipefail

# see https://www.redmine.org/projects/redmine/wiki/redmineinstall
defaultRubyVersion='2.6'
declare -A rubyVersions=()

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

relasesUrl='https://github.com/redmica/redmica/archive'
versionsPage="$(wget -qO- 'https://github.com/redmica/redmica/releases')"

passenger="$(wget -qO- 'https://rubygems.org/api/v1/gems/passenger.json' | sed -r 's/^.*"version":"([^"]+)".*$/\1/')"

travisEnv=
for version in "${versions[@]}"; do
	fullVersion=$(echo "$versionsPage" | sed -nr "s/.*($version\.[0-9]+)\.tar\.gz[^.].*/\1/p" | sort -V | tail -1)
	md5="$(wget -qO- "$relasesUrl/v$fullVersion.tar.gz" | md5sum | cut -d' ' -f1)"

	rubyVersion="${rubyVersions[$version]:-$defaultRubyVersion}"

	echo "$version: $fullVersion (ruby $rubyVersion; passenger $passenger)"

	cp docker-entrypoint.sh "$version/"
	sed -e 's/%%REDMICA_VERSION%%/'"$fullVersion"'/' \
		-e 's/%%RUBY_VERSION%%/'"$rubyVersion"'/' \
		-e 's/%%REDMICA_DOWNLOAD_MD5%%/'"$md5"'/' \
		Dockerfile-debian.template > "$version/Dockerfile"

	mkdir -p "$version/passenger"
	sed -e 's/%%REDMINE%%/douhashi\/redmica:'"$fullVersion"'/' \
		-e 's/%%PASSENGER_VERSION%%/'"$passenger"'/' \
		Dockerfile-passenger.template > "$version/passenger/Dockerfile"

	mkdir -p "$version/alpine"
	cp docker-entrypoint.sh "$version/alpine/"
	sed -i -e 's/gosu/su-exec/g' "$version/alpine/docker-entrypoint.sh"
	sed -e 's/%%REDMICA_VERSION%%/'"$fullVersion"'/' \
		-e 's/%%RUBY_VERSION%%/'"$rubyVersion"'/' \
		-e 's/%%REDMICA_DOWNLOAD_MD5%%/'"$md5"'/' \
		Dockerfile-alpine.template > "$version/alpine/Dockerfile"

	travisEnv='\n  - VERSION='"$version/alpine$travisEnv"
	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
