#!/usr/bin/env bash
# Build the "native debug symbols" zip that Google Play asks for (issue #10).
# Usage: scripts/android-symbols.sh [godot-version]    e.g. 4.8-beta5, 4.7.2-stable
#
# Godot doesn't put native debug symbols in the AAB, but it publishes them for every
# official Android export template. This downloads the ones matching your template (by
# default the version in android/.build_version, i.e. the installed Gradle build template),
# keeps only the CPU architectures your Android export preset builds (so the zip stays
# under Play Console's size limit), and writes:
#   exports/android-native-debug-symbols-<version>.zip
# Upload it in Play Console: Test and release > App bundle explorer > (your bundle) >
# Downloads > Native debug symbols > Upload. Only valid with the official template
# (gradle_build/android_source_template empty); custom templates need their own symbols.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
forward_to_wsl "$@"
cd "$PROJECT_ROOT"

for tool in curl zip; do
	command -v "$tool" > /dev/null || die "$tool is not installed (in Fedora: sudo dnf install $tool)"
done

# 4.8.beta5 (template file) -> 4.8-beta5 (release tag); 4.7.2.stable -> 4.7.2-stable
if (($# >= 1)); then
	tag="$1"
else
	[[ -f android/.build_version ]] || die "no android/.build_version; install the Android build template or pass a version"
	tag="$(sed 's/\.\([a-z]\)/-\1/' android/.build_version | tr -d '[:space:]')"
fi
[[ "$tag" == *-* ]] || tag="$tag-stable"

# Architectures the Android preset exports (architectures/arm64-v8a=true, ...)
mapfile -t abis < <(sed -n 's/^architectures\/\(.*\)=true$/\1/p' export_presets.cfg 2> /dev/null | sort -u)
((${#abis[@]})) || abis=(arm64-v8a armeabi-v7a)
echo "Godot $tag, architectures: ${abis[*]}"

base="https://github.com/godotengine/godot-builds/releases/download/$tag"
# Pre-releases and stable releases name the file differently
candidates=("Godot_v${tag}_debugsymbols_android_release.zip" "Godot_native_debug_symbols.${tag//-/.}.template_release.android.zip")

cache="exports/.cache"
mkdir -p "$cache"
download=""
for name in "${candidates[@]}"; do
	if [[ -s "$cache/$name" ]]; then
		download="$cache/$name"
		echo "Using cached $download"
		break
	fi
	echo "Downloading $name (about 800 MB)..."
	if curl -fL --progress-bar -o "$cache/$name.part" "$base/$name"; then
		mv "$cache/$name.part" "$cache/$name"
		download="$cache/$name"
		break
	fi
	rm -f "$cache/$name.part"
done
[[ -n "$download" ]] || die "no Android debug symbols found for Godot $tag at $base"

out="exports/android-native-debug-symbols-$tag.zip"
cp "$download" "$out"
for abi in arm64-v8a armeabi-v7a x86 x86_64; do
	if [[ ! " ${abis[*]} " == *" $abi "* ]]; then
		zip -q -d "$out" "$abi/*" 2> /dev/null || true
	fi
done

size_mb=$(($(stat -c %s "$out") / 1024 / 1024))
echo "Wrote $out ($size_mb MB)"
echo "Upload it in Play Console: App bundle explorer > your bundle > Downloads > Native debug symbols."
