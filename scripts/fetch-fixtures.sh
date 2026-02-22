#!/usr/bin/env bash
# Fetch open-source repos used by integration tests.
# Idempotent: skips repos already at the pinned commit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPOS_DIR="$ROOT_DIR/fixtures/repos"

# Parallel arrays
NAMES=(    IceCubesApp                                     Alamofire                                       SwiftFormat)
URLS=(     https://github.com/Dimillian/IceCubesApp.git    https://github.com/Alamofire/Alamofire.git      https://github.com/nicklockwood/SwiftFormat.git)
COMMITS=(  99484408ca50d28f01363af45e3697c24bad412d        f73a2fcb60198ef2b92dc3b6074b18f98ccee875        22a472ced4c621a0e41b982a6f32dec868d09392)

mkdir -p "$REPOS_DIR"

for i in "${!NAMES[@]}"; do
  name="${NAMES[$i]}"
  url="${URLS[$i]}"
  sha="${COMMITS[$i]}"
  dest="$REPOS_DIR/$name"

  # Check if already at correct commit
  if [ -d "$dest/.git" ]; then
    current_sha="$(git -C "$dest" rev-parse HEAD 2>/dev/null || echo "")"
    if [ "$current_sha" = "$sha" ]; then
      echo "ok: $name already at $sha"
      continue
    fi
    echo "xx: $name at wrong commit, re-cloning"
    rm -rf "$dest"
  fi

  echo ">>: Cloning $name"
  git clone --filter=blob:none --no-single-branch "$url" "$dest"
  git -C "$dest" checkout "$sha"
  echo "ok: $name at $sha"
done

# IceCubesApp requires an xcconfig (gitignored); create from template if missing
ICE_XCCONFIG="$REPOS_DIR/IceCubesApp/IceCubesApp.xcconfig"
ICE_TEMPLATE="$REPOS_DIR/IceCubesApp/IceCubesApp.xcconfig.template"
if [ ! -f "$ICE_XCCONFIG" ] && [ -f "$ICE_TEMPLATE" ]; then
  cp "$ICE_TEMPLATE" "$ICE_XCCONFIG"
  echo "ok: created IceCubesApp.xcconfig from template"
fi

# Alamofire 5.11.1 has bugs exposed by Xcode 26's stricter Swift compiler:
# 1. `if case let .failure(error)` shadows self.error; assignment to `error`
#    is rejected as assigning to a `let` constant. Fix: use `self.error`.
# 2. `downloadProgress`/`uploadProgress` closures escape but aren't marked
#    `@escaping`. Fix: add `@escaping`.
# 3. Multi-line `#if canImport(Darwin) && \n !canImport(FoundationNetworking)`
#    is rejected by Swift 6.2 — collapse to single line.
patch_alamofire() {
  local af="$REPOS_DIR/Alamofire"
  [ -d "$af" ] || return

  # Fix 1: self.error shadowing in validate() closures
  # In Xcode 26, `if case let .failure(error)` shadows self.error; the compiler
  # rejects the binding as reassignment to a `let` constant. Fix: rename binding.
  # All three files have the same single-line format on a clean clone.
  python3 -c "
af = '$af'
import os

for fname in ['DataRequest.swift', 'DataStreamRequest.swift', 'DownloadRequest.swift']:
    f = os.path.join(af, 'Source/Core', fname)
    with open(f) as fh: s = fh.read()
    s = s.replace(
        'if case let .failure(error) = result {\n                self.error = error.asAFError(or: .responseValidationFailed(reason: .customValidationFailed(error: error)))',
        'if case let .failure(validationError) = result {\n                self.error = validationError.asAFError(or: .responseValidationFailed(reason: .customValidationFailed(error: validationError)))'
    )
    with open(f, 'w') as fh: fh.write(s)
"

  # Fix 2: @escaping on ProgressHandler closures
  if grep -q 'public func downloadProgress(queue: DispatchQueue = .main, closure: ProgressHandler)' "$af/Source/Core/Request.swift" 2>/dev/null; then
    sed -i '' \
      's/public func downloadProgress(queue: DispatchQueue = .main, closure: ProgressHandler)/public func downloadProgress(queue: DispatchQueue = .main, closure: @escaping ProgressHandler)/' \
      "$af/Source/Core/Request.swift"
    sed -i '' \
      's/public func uploadProgress(queue: DispatchQueue = .main, closure: ProgressHandler)/public func uploadProgress(queue: DispatchQueue = .main, closure: @escaping ProgressHandler)/' \
      "$af/Source/Core/Request.swift"
  fi

  # Fix 3: Multi-line #if canImport(Darwin) && \n !canImport(FoundationNetworking)
  # Swift 6.2 rejects multi-line conditional compilation directives. Collapse to single line.
  for f in "$af"/Source/Core/Session.swift "$af"/Source/Core/WebSocketRequest.swift "$af"/Source/Features/Concurrency.swift; do
    [ -f "$f" ] || continue
    sed -i '' -E '/^[[:space:]]*#if canImport\(Darwin\) &&[[:space:]]*$/{
      N
      s/#if canImport\(Darwin\) &&[[:space:]]*\n[[:space:]]*!canImport\(FoundationNetworking\)[^\n]*/#if canImport(Darwin) \&\& !canImport(FoundationNetworking)/
    }' "$f"
  done

  echo "ok: patched Alamofire for Xcode 26 compatibility"
}
patch_alamofire

# SwiftFormat 0.59.1 (22a472c) has 3 compilation errors with Xcode 26 / Swift 6.2:
# 1. Range<Int>.split is ambiguous (OpaqueGenericParameters.swift)
# 2. removeTokens(in:) overload resolution fails for ClosedRange (HoistPatternLet.swift)
# 3. ClosedRange ... operator resolves to wrong autoUpdating overload (NoForceUnwrapInTests.swift)
patch_swiftformat() {
  local sf="$REPOS_DIR/SwiftFormat"
  [ -d "$sf" ] || return

  python3 -c "
sf = '$sf'
import os

# Fix 1: Range<Int>.split is ambiguous — convert range to [Int] first
f = os.path.join(sf, 'Sources/Rules/OpaqueGenericParameters.swift')
with open(f) as fh: s = fh.read()
s = s.replace(
    'let parameterListTokenIndices = (declaration.argumentsRange.lowerBound + 1) ..< declaration.argumentsRange.upperBound',
    'let parameterListTokenIndices: [Int] = .init((declaration.argumentsRange.lowerBound + 1) ..< declaration.argumentsRange.upperBound)'
)
with open(f, 'w') as fh: fh.write(s)

# Fix 2: removeTokens(in:) overload ambiguous for ClosedRange — use Range<Int> overload
f = os.path.join(sf, 'Sources/Rules/HoistPatternLet.swift')
with open(f) as fh: s = fh.read()
s = s.replace(
    'let range = ((formatter.index(of: .nonSpace, before: startIndex) ?? (prevIndex - 1)) + 1) ... startIndex\n                formatter.removeTokens(in: range)',
    'let rangeLower = (formatter.index(of: .nonSpace, before: startIndex) ?? (prevIndex - 1)) + 1\n                formatter.removeTokens(in: rangeLower ..< startIndex + 1)'
)
with open(f, 'w') as fh: fh.write(s)

# Fix 3: ... operator resolves to Int.autoUpdating (AutoUpdatingIndex) instead of
# ClosedRange<Int>.autoUpdating (AutoUpdatingRange) — use explicit ClosedRange init
f = os.path.join(sf, 'Sources/Rules/NoForceUnwrapInTests.swift')
with open(f) as fh: s = fh.read()
s = s.replace(
    'let absoluteRange = (subExpressionRange.lowerBound + expressionRange.lowerBound) ... (subExpressionRange.upperBound + expressionRange.lowerBound)\n            expressionRange = absoluteRange.autoUpdating(in: self)',
    'let absoluteLower = subExpressionRange.lowerBound + expressionRange.lowerBound\n            let absoluteUpper = subExpressionRange.upperBound + expressionRange.lowerBound\n            let absoluteRange = ClosedRange(uncheckedBounds: (absoluteLower, absoluteUpper))\n            expressionRange = absoluteRange.autoUpdating(in: self)'
)
with open(f, 'w') as fh: fh.write(s)
"

  echo "ok: patched SwiftFormat for Xcode 26 compatibility"
}
patch_swiftformat

# IceCubesApp 2.1.4 (9948440) has 5 categories of compilation errors with Xcode 26 / Swift 6.2:
# 1. @Observable macro makes AccountTabFetcher `final`, blocking subclass inheritance.
# 2. @State properties are file-private in Swift 6.2, breaking cross-file extensions.
# 3. Synthesized memberwise init for structs with @StateObject/@State is now private.
# 4. TimelineView.timelineView is too complex for the type checker.
patch_icecubesapp() {
  local ice="$REPOS_DIR/IceCubesApp"
  [ -d "$ice" ] || return

  python3 -c "
ice = '$ice'
import os

# Fix 1: @Observable makes AccountTabFetcher final — remove macro from base class.
# Subclasses keep @Observable for their own properties; base class properties don't
# need observation tracking for compilation.
f = os.path.join(ice, 'Packages/Account/Sources/Account/Detail/Tabs/Base/AccountTabFetcher.swift')
with open(f) as fh: s = fh.read()
s = s.replace(
    '@MainActor\n@Observable\nclass AccountTabFetcher: StatusesFetcher {',
    '@MainActor\nclass AccountTabFetcher: StatusesFetcher {'
)
with open(f, 'w') as fh: fh.write(s)

# Fix 2: @State properties are file-private in Swift 6.2. Extensions in
# IceCubesApp+Scene.swift and IceCubesApp+Menu.swift can't access @State vars
# declared in IceCubesApp.swift. Fix: merge extensions into the main file.
main_file = os.path.join(ice, 'IceCubesApp/App/Main/IceCubesApp.swift')
scene_file = os.path.join(ice, 'IceCubesApp/App/Main/IceCubesApp+Scene.swift')
menu_file = os.path.join(ice, 'IceCubesApp/App/Main/IceCubesApp+Menu.swift')

with open(main_file) as fh: main_src = fh.read()
with open(scene_file) as fh: scene_src = fh.read()
with open(menu_file) as fh: menu_src = fh.read()

# Append extension content to main file
main_src += '\n// MARK: - Merged from IceCubesApp+Scene.swift (Xcode 26 patch)\n\n' + scene_src
main_src += '\n// MARK: - Merged from IceCubesApp+Menu.swift (Xcode 26 patch)\n\n' + menu_src
with open(main_file, 'w') as fh: fh.write(main_src)

# Replace extension files with empty stubs (files must exist for Xcode project refs)
for path in [scene_file, menu_file]:
    with open(path, 'w') as fh:
        fh.write('// Merged into IceCubesApp.swift for Xcode 26 compatibility\n')

# Fix 3a: StatusRowShareAsImageView — @StateObject synthesized init is now private.
# Add explicit init.
f = os.path.join(ice, 'Packages/StatusKit/Sources/StatusKit/Share/StatusRowShareAsImageView.swift')
with open(f) as fh: s = fh.read()
s = s.replace(
    '  let viewModel: StatusRowViewModel\n  @StateObject var renderer: ImageRenderer<AnyView>\n',
    '  let viewModel: StatusRowViewModel\n  @StateObject var renderer: ImageRenderer<AnyView>\n\n  init(viewModel: StatusRowViewModel, renderer: ImageRenderer<AnyView>) {\n    self.viewModel = viewModel\n    _renderer = StateObject(wrappedValue: renderer)\n  }\n'
)
with open(f, 'w') as fh: fh.write(s)

# Fix 3b: PushNotificationsView — @State synthesized init is now private.
# Add explicit init.
f = os.path.join(ice, 'IceCubesApp/App/Tabs/Settings/PushNotificationsView.swift')
with open(f) as fh: s = fh.read()
s = s.replace(
    '  @State public var subscription: PushNotificationSubscriptionSettings\n\n  var body:',
    '  @State public var subscription: PushNotificationSubscriptionSettings\n\n  init(subscription: PushNotificationSubscriptionSettings) {\n    _subscription = State(initialValue: subscription)\n  }\n\n  var body:'
)
with open(f, 'w') as fh: fh.write(s)

# Fix 4: TimelineView.timelineView — type-checker timeout on complex toolbar.
# Extract toolbar content into a separate computed property.
f = os.path.join(ice, 'Packages/Timeline/Sources/Timeline/View/TimelineView.swift')
with open(f) as fh: s = fh.read()
s = s.replace(
    '    .toolbar {\n'
    '      TimelineToolbarTitleView(timeline: \$timeline, canFilterTimeline: canFilterTimeline)\n'
    '      if #available(iOS 26.0, *) {\n'
    '        ToolbarSpacer(placement: .topBarTrailing)\n'
    '      }\n'
    '      if viewModel.canStreamTimeline(timeline) {\n'
    '        ToolbarItem(placement: .navigationBarTrailing) {\n'
    '          Button {\n'
    '            viewModel.isStreamingTimeline.toggle()\n'
    '          } label: {\n'
    '            Image(\n'
    '              systemName: viewModel.isStreamingTimeline\n'
    '                ? \"antenna.radiowaves.left.and.right\" : \"antenna.radiowaves.left.and.right.slash\")\n'
    '          }\n'
    '          .tint(theme.labelColor)\n'
    '        }\n'
    '      }\n'
    '      TimelineToolbarTagGroupButton(timeline: \$timeline)\n'
    '    }',
    '    .toolbar { timelineToolbarContent }'
)

# Add the extracted toolbar property before the refreshContentFilter method
s = s.replace(
    '  private func refreshContentFilter() {',
    '  @ToolbarContentBuilder\n'
    '  private var timelineToolbarContent: some ToolbarContent {\n'
    '    TimelineToolbarTitleView(timeline: \$timeline, canFilterTimeline: canFilterTimeline)\n'
    '    if #available(iOS 26.0, *) {\n'
    '      ToolbarSpacer(placement: .topBarTrailing)\n'
    '    }\n'
    '    if viewModel.canStreamTimeline(timeline) {\n'
    '      ToolbarItem(placement: .navigationBarTrailing) {\n'
    '        Button {\n'
    '          viewModel.isStreamingTimeline.toggle()\n'
    '        } label: {\n'
    '          Image(\n'
    '            systemName: viewModel.isStreamingTimeline\n'
    '              ? \"antenna.radiowaves.left.and.right\" : \"antenna.radiowaves.left.and.right.slash\")\n'
    '        }\n'
    '        .tint(theme.labelColor)\n'
    '      }\n'
    '    }\n'
    '    TimelineToolbarTagGroupButton(timeline: \$timeline)\n'
    '  }\n\n'
    '  private func refreshContentFilter() {'
)
with open(f, 'w') as fh: fh.write(s)
"

  echo "ok: patched IceCubesApp for Xcode 26 compatibility"
}
patch_icecubesapp

echo ""
echo "All fixtures ready in $REPOS_DIR"
