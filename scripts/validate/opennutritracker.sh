#!/usr/bin/env bash
# Validate an OpenNutriTracker PR. Requires Flutter (3.44.x). $1 = PR tree.
set -euo pipefail
tree="${1:?}"
cd "$tree"

flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter gen-l10n
flutter analyze
flutter test
