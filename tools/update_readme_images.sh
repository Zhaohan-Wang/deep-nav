#!/bin/zsh

set -euo pipefail

project_root="${0:A:h:h}"
runtime_dir="$project_root/artifacts/runtime"
overview_dir="$project_root/artifacts/star_map_overviews"
preview_dir="$project_root/assets/ui/mission_previews"
output_dir="$project_root/docs/readme"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

runtime_image() {
  local source_name="$1"
  local output_name="$2"
  local source_path="$runtime_dir/$source_name"
  local source_stem="${source_name:t:r}"
  local cropped_path="$temp_dir/$source_stem-cropped.png"

  test -f "$source_path" || { print -u2 "Missing runtime screenshot: $source_path"; return 1; }
  sips -c 1944 3456 "$source_path" --out "$cropped_path" >/dev/null
  sips -z 900 1600 -s format jpeg -s formatOptions 88 "$cropped_path" --out "$output_dir/$output_name" >/dev/null
}

source_image() {
  local source_path="$1"
  local output_name="$2"
  local height="$3"
  local width="$4"

  test -f "$source_path" || { print -u2 "Missing source image: $source_path"; return 1; }
  sips -z "$height" "$width" -s format jpeg -s formatOptions 88 "$source_path" --out "$output_dir/$output_name" >/dev/null
}

map_image() {
	local mission="$1"
	local source_path="$overview_dir/$mission.png"
	local cropped_path="$temp_dir/map-$mission-cropped.png"
	local source_width crop_height

	test -f "$source_path" || { print -u2 "Missing map overview: $source_path"; return 1; }
	# 单屏/双屏采集宽度不同，但中央都保留完整的 16:9 地图区域。
	source_width="$(sips -g pixelWidth "$source_path" | awk '/pixelWidth/ {print $2}')"
	crop_height=$((source_width * 9 / 16))
	sips -c "$crop_height" "$source_width" "$source_path" --out "$cropped_path" >/dev/null
	sips -z 900 1600 -s format jpeg -s formatOptions 88 "$cropped_path" --out "$output_dir/map_$mission.jpg" >/dev/null
}

mkdir -p "$output_dir"

runtime_image title_screen.png hero.jpg
runtime_image readme_navigator.png navigator.jpg
runtime_image readme_pilot.png pilot.jpg
runtime_image level_select_experiment.png level_select.jpg
runtime_image role_claim_16x9.png role_claim.jpg
runtime_image mission_result_success.png result_success.jpg
runtime_image mission_result.png result_failure.jpg
runtime_image mission_attribution.png attribution.jpg
runtime_image survey_page_1.png survey.jpg
runtime_image thank_you.png thank_you.jpg

for mission in practice level_1 level_2 level_3; do
  source_image "$preview_dir/$mission.jpg" "mission_$mission.jpg" 539 1270
  map_image "$mission"
done

print "README images refreshed in $output_dir"
