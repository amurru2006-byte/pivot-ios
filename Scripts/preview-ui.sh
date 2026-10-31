#!/bin/bash
set -euo pipefail
PIVOT_UI_ONLY_TESTING=${PIVOT_UI_ONLY_TESTING:-}
PIVOT_PREVIEW_OUTPUT=build/Previews
PIVOT_UI_BUILD_LOG=build/preview-build.log
PIVOT_UI_LOG=build/interaction-tests.log
PIVOT_UI_RESULT=build/interaction-tests.xcresult
PIVOT_SIM_ENTITLEMENTS=build/simulator-entitlements.plist
PIVOT_RELEASE_SHARD=
PIVOT_PLACES_GROUP=
case "$PIVOT_UI_ONLY_TESTING" in
  '') ;;
  v8-release-finance|v8-release-workout|v8-release-profile|v8-release-pairing)
    PIVOT_RELEASE_SHARD=${PIVOT_UI_ONLY_TESTING#v8-release-}
    PIVOT_PREVIEW_OUTPUT=build/Previews/Release-$PIVOT_RELEASE_SHARD
    PIVOT_UI_BUILD_LOG=build/release-$PIVOT_RELEASE_SHARD-build.log
    PIVOT_UI_LOG=build/release-$PIVOT_RELEASE_SHARD-tests.log
    PIVOT_UI_RESULT=build/release-$PIVOT_RELEASE_SHARD-tests.xcresult
    PIVOT_SIM_ENTITLEMENTS=build/release-$PIVOT_RELEASE_SHARD-simulator-entitlements.plist
    # Validate full coverage before any expensive build; no arbitrary filter.
    PIVOT_RELEASE_FLAGS=$(python3 Scripts/ui_release_shards.py --shard "$PIVOT_RELEASE_SHARD")
    ;;
  PivotUITests/CalendarCreationInteractionTests|PivotUITests/CalendarMutationInteractionTests|PivotUITests/PredictionInteractionTests|PivotUITests/OnlineCoachInteractionTests|PivotUITests/BackupPrivacyInteractionTests|v8-privacy-regression|v8-savings-regression|v8-history-regression|v8-contacts-regression|v8-income-final-regression|v8-training-controls-regression|v8-083-controls-regression)
    PIVOT_PREVIEW_OUTPUT=build/Previews/OnlinePrivacy
    PIVOT_UI_BUILD_LOG=build/online-privacy-build.log
    PIVOT_UI_LOG=build/online-privacy-tests.log
    PIVOT_UI_RESULT=build/online-privacy-tests.xcresult
    PIVOT_SIM_ENTITLEMENTS=build/online-privacy-simulator-entitlements.plist
    ;;
  v8-0810-health-regression|v8-089-planning-regression|v8-088-calendar-controls-regression|v8-088-chart-controls-regression|v8-088-places-regression|v8-088-places-controls-regression|v8-087-linked-travel-regression|v8-086-presentation-regression|v8-086-rest-audio-regression|v8-086-contact-save-regression|PivotUITests/PremiumCoachInteractionTests|PivotUITests/PremiumCoachInteractionTests/testMemoryOptInPersistsAppearsInExactDisclosureAndCanBeRevoked)
    PIVOT_PREVIEW_OUTPUT=build/Previews/OnlinePrivacy
    PIVOT_UI_BUILD_LOG=build/online-privacy-build.log
    PIVOT_UI_LOG=build/online-privacy-tests.log
    PIVOT_UI_RESULT=build/online-privacy-tests.xcresult
    PIVOT_SIM_ENTITLEMENTS=build/online-privacy-simulator-entitlements.plist
    ;;
  v8-086-calendar-timing-regression|v8-086-weekly-and-timing-regression|v8-086-evidence-and-maps-regression|PivotUITests/SavingsEvidenceInteractionTests|PivotUITests/OnlineCoachSetupInteractionTests)
    PIVOT_PREVIEW_OUTPUT=build/Previews/QRPreflight
    PIVOT_UI_BUILD_LOG=build/qr-preflight-build.log
    PIVOT_UI_LOG=build/qr-preflight-tests.log
    PIVOT_UI_RESULT=build/qr-preflight-tests.xcresult
    PIVOT_SIM_ENTITLEMENTS=build/qr-preflight-simulator-entitlements.plist
    ;;
  v8-modern-regression)
    PIVOT_PREVIEW_OUTPUT=build/Previews/ModernPreflight
    PIVOT_UI_BUILD_LOG=build/modern-preflight-build.log
    PIVOT_UI_LOG=build/modern-preflight-tests.log
    PIVOT_UI_RESULT=build/modern-preflight-tests.xcresult
    PIVOT_SIM_ENTITLEMENTS=build/modern-preflight-simulator-entitlements.plist
    ;;
  *) printf '%s\n' 'Unsupported PIVOT_UI_ONLY_TESTING; refusing to skip arbitrary regressions.' >&2; exit 2 ;;
esac
mkdir -p "$PIVOT_PREVIEW_OUTPUT"
# Resolve the OS before the expensive build. A matching model name can exist
# on iOS 18 and 26: the former silently skipped the AlarmKit test.
xcrun simctl list devices available -j > build/devices.json
PIVOT_SIMULATOR=$(python3 Scripts/select_simulator.py build/devices.json --metadata-out build/selected-simulator.json)
cat build/selected-simulator.json
# Validate the focused selection before building, and reuse that exact list
# for result verification. A missing selected case must not waste an iOS build.
if [ "$PIVOT_UI_ONLY_TESTING" = v8-0810-health-regression ]; then
  PIVOT_PLACES_GROUP=health
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-089-planning-regression ]; then
  PIVOT_PLACES_GROUP=planning
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-088-places-regression ]; then
  PIVOT_PLACES_GROUP=places
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-088-places-controls-regression ]; then
  PIVOT_PLACES_GROUP=places-controls
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-088-chart-controls-regression ]; then
  PIVOT_PLACES_GROUP=chart
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-088-calendar-controls-regression ]; then
  PIVOT_PLACES_GROUP=calendar-controls
fi
if [ -n "$PIVOT_PLACES_GROUP" ]; then
  PIVOT_PLACES_FLAGS=$(python3 Scripts/ui_release_shards.py --preflight "$PIVOT_PLACES_GROUP")
fi
# The simulator still uses the real Security framework for the protected-QR
# persistence test. Unsigned builds have no private Keychain access group.
# Use a deliberately synthetic, per-bundle identity only in these Debug
# simulator invocations; the iPhone Release packaging remains unchanged.
PIVOT_SIM_SIGNING=(
  CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
  "CODE_SIGN_ENTITLEMENTS=$PWD/Scripts/simulator-keychain.entitlements"
)
# Standard ARM hosts have limited memory. Bound both target scheduling and
# Swift frontend parallelism; preserve inherited flags and all test coverage.
PIVOT_SIM_LIMITS=(-jobs 2 'OTHER_SWIFT_FLAGS=$(inherited) -j2')
if xcodebuild -project Pivot.xcodeproj -scheme Pivot -configuration Debug \
  -destination "platform=iOS Simulator,id=$PIVOT_SIMULATOR" ONLY_ACTIVE_ARCH=YES \
  -derivedDataPath build/DerivedData -showBuildTimingSummary "${PIVOT_SIM_SIGNING[@]}" "${PIVOT_SIM_LIMITS[@]}" build > "$PIVOT_UI_BUILD_LOG" 2>&1; then
  printf '%s\n' 'App simulator build succeeded.'
else
  PIVOT_BUILD_STATUS=$?
  # Surface compiler diagnostics immediately. A failed build must not look
  # like an unexplained exit 65 requiring a separate artifact download.
  awk '/error:|fatal error:|\*\* BUILD FAILED|The following build commands failed/ { print; fflush() }' "$PIVOT_UI_BUILD_LOG"
  exit "$PIVOT_BUILD_STATUS"
fi
PIVOT_SIM_APP=build/DerivedData/Build/Products/Debug-iphonesimulator/Pivot.app
codesign --verify --deep --strict "$PIVOT_SIM_APP"
# Simulator entitlements are linked into __TEXT,__entitlements; its ad-hoc
# code-signature entitlement dictionary can legitimately be empty.
python3 Scripts/verify_simulator_entitlements.py "$PIVOT_SIM_APP" "$PIVOT_SIM_ENTITLEMENTS"
xcrun simctl boot "$PIVOT_SIMULATOR" || true
xcrun simctl bootstatus "$PIVOT_SIMULATOR" -b
xcrun simctl status_bar "$PIVOT_SIMULATOR" override --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 --batteryState charged --batteryLevel 100
xcrun simctl install "$PIVOT_SIMULATOR" "$PIVOT_SIM_APP"
if [ -z "$PIVOT_UI_ONLY_TESTING" ] || [ "$PIVOT_RELEASE_SHARD" = profile ]; then
  for PIVOT_SCREEN in today coach income settings tutoring launch income-warning income-red duplicates birthday workout-widget strength-ranks; do
    xcrun simctl terminate "$PIVOT_SIMULATOR" app.pivot.personal || true
    xcrun simctl launch "$PIVOT_SIMULATOR" app.pivot.personal --preview "--screen=$PIVOT_SCREEN"
    sleep 3
    xcrun simctl io "$PIVOT_SIMULATOR" screenshot "$PIVOT_PREVIEW_OUTPUT/$PIVOT_SCREEN.png"
  done
  xcrun simctl terminate "$PIVOT_SIMULATOR" app.pivot.personal || true
  sleep 1
  xcrun simctl io "$PIVOT_SIMULATOR" screenshot "$PIVOT_PREVIEW_OUTPUT/home-icon.png"
fi

# A screenshot can look correct even when every touch is blocked. Exercise the
# real root refresh path with a deliberately slow background calendar import.
# Preserve the test result while exporting screenshots on failure as well.
PIVOT_UI_TEST_STATUS=0
# macOS /bin/bash can be 3.2: with nounset, expanding an empty array is fatal.
# Keep the command nonempty and append the optional, already-whitelisted filter.
PIVOT_UI_TEST_COMMAND=(
  xcodebuild -project Pivot.xcodeproj -scheme Pivot -configuration Debug
  -destination "platform=iOS Simulator,id=$PIVOT_SIMULATOR"
  ONLY_ACTIVE_ARCH=YES
  -derivedDataPath build/DerivedData -parallel-testing-enabled NO
  -test-timeouts-enabled YES
  -default-test-execution-time-allowance 600
  -maximum-test-execution-time-allowance 600
  -resultBundlePath "$PIVOT_UI_RESULT" -showBuildTimingSummary "${PIVOT_SIM_SIGNING[@]}" "${PIVOT_SIM_LIMITS[@]}" test
)
if [ -n "$PIVOT_RELEASE_SHARD" ]; then
  while IFS= read -r PIVOT_TEST_FLAG; do
    PIVOT_UI_TEST_COMMAND+=("$PIVOT_TEST_FLAG")
  done <<< "$PIVOT_RELEASE_FLAGS"
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-087-linked-travel-regression ]; then
  # Focused diagnostic only. All native cases still gate the final candidate.
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/CalendarMutationInteractionTests/testLinkedJourneyIsReviewedTogetherAndPersistsAfterRelaunch
    -only-testing:PivotUITests/CalendarMutationInteractionTests/testExternallyChangedLinkedPairIsRefusedWithoutLosingMoneyOrCreatingCopies
    -only-testing:PivotUITests/CalendarCreationInteractionTests/testNativeEditorManualJourneySurvivesRelaunchAndCreatesExactlyTwoAfterConfirmation
    -only-testing:PivotUITests/PremiumCoachInteractionTests/testExpandingCalendarScopeRevokesPreviousConversationPermissionBeforeAnyNewSend
    -only-testing:PivotUITests/PremiumCoachInteractionTests/testBusyWeekRefusesWithoutSendingAndCanBeNarrowedWithoutLosingMessage
    -only-testing:PivotUITests/PremiumCoachInteractionTests/testNamedWeekdayRecoveryOpensExactDayLocallyWithoutOnlineRequest
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-086-calendar-timing-regression ]; then
  # Remaining native failure: the centre of the plain clock row was not a
  # hit target. Keep its ordinary tap and every calendar-write assertion.
  PIVOT_UI_TEST_COMMAND+=(-only-testing:PivotUITests/CalendarTimingInteractionTests)
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-086-weekly-and-timing-regression ]; then
  # Only the two observed selector failures. The release workflow still
  # requires every native case exactly once on its own consolidated SHA.
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/CalendarTimingInteractionTests
    -only-testing:PivotUITests/SavingsInteractionTests/testWeeklyPlanIsOptInPersistsAndDeletionKeepsGoalAndMoneyWithEmptySimulationFields
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-086-evidence-and-maps-regression ]; then
  # One diagnostic build covers the two observed failures and the missing-data
  # savings control. Every release test remains mandatory, exactly once.
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/CalendarCreationInteractionTests/testMapsEstimateRequiresConsentCanBeUsedThenRemovedWithoutWriting
    -only-testing:PivotUITests/SavingsEvidenceInteractionTests
    -only-testing:PivotUITests/SavingsInteractionTests/testWeeklyPlanIsOptInPersistsAndDeletionKeepsGoalAndMoneyWithEmptySimulationFields
    -only-testing:PivotUITests/CalendarTimingInteractionTests
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-086-presentation-regression ]; then
  # Observed failures only, for diagnosis. This cannot package a release or
  # substitute for the unchanged complete, exact-once release coverage.
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/CalendarCreationInteractionTests/testMapsEstimateRequiresConsentCanBeUsedThenRemovedWithoutWriting
    -only-testing:PivotUITests/CalendarMutationInteractionTests/testPartialConversationSurvivesRelaunchAndCreatesPastEventOnlyAfterConfirmation
    -only-testing:PivotUITests/CalendarMutationInteractionTests/testOriginalArchiveWriteFailurePreventsExternalDeletion
    -only-testing:PivotUITests/OnlineCoachInteractionTests/testCalendarDraftNeedsSeparateConfirmationAndCanCancelBeforeSaving
    -only-testing:PivotUITests/OnlineCoachSetupInteractionTests/testQRCodeExplicitSavePersistsOnlyProtectedConfigurationAcrossLaunches
    -only-testing:PivotUITests/PivotInteractionTests/testSerie7DeepLinkReplacesWorkoutPageAndZeroHoldIsSkipped
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-086-rest-audio-regression ]; then
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/WorkoutRestAudioInteractionTests
    -only-testing:PivotUITests/PivotInteractionTests/testRecoveryStaysReachableAtEighthExerciseAndLastSet
    -only-testing:PivotUITests/PivotInteractionTests/testLiveActivityLayoutKeepsLargeButtonsWithinSystemHeight
    -only-testing:PivotUITests/PivotInteractionTests/testWorkoutIntentActionsPersistBothSidesAndRestState
    -only-testing:PivotUITests/PivotInteractionTests/testAlarmProbeIsExplicitAndDoesNotStartOnOpening
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-086-contact-save-regression ]; then
  # Diagnostic preflight only, not a release gate substitute. Full release
  # still requires every native test exactly once on the final source SHA.
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/ClientActivityInteractionTests
    -only-testing:PivotUITests/CalendarCreationInteractionTests
    -only-testing:PivotUITests/CalendarMutationInteractionTests
    -only-testing:PivotUITests/OnlineCoachInteractionTests/testCalendarDraftNeedsSeparateConfirmationAndCanCancelBeforeSaving
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-083-controls-regression ]; then
  # Diagnose the five observed 0.8.3 failures before another full release run.
  # This branch cannot package/promote an IPA; all 58 release cases remain required.
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/HistoricalIncomeInteractionTests/testLocalReviewCancelImportAndRelaunchKeepFundsSeparate
    -only-testing:PivotUITests/IncomeCorrectionInteractionTests/testContactDefaultsAndMultipleOriginsPersistAfterRelaunch
    -only-testing:PivotUITests/IncomeCorrectionInteractionTests/testContactPeriodsGraphAndAddPartialReceiptKeepFullHistory
    -only-testing:PivotUITests/IncomeCorrectionInteractionTests/testCorrectionsPersistAndDoNotInventAnAdditionalReceipt
    -only-testing:PivotUITests/OnlineCoachInteractionTests/testRoutingPreferencesCanBeRememberedWithoutCreatingAnEvent
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-training-controls-regression ]; then
  # Diagnose the two observed control failures without rerunning unrelated UI.
  # The release workflow still requires all 46 native cases without skips.
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/PivotInteractionTests/testTrainingPDFImportSetLoggingAndPersistence
    -only-testing:PivotUITests/TrainingConcernInteractionTests/testPainLinksTwoMovementsWithoutStartingWorkoutResolvesAndPersists
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-income-final-regression ]; then
  # Diagnose the three observed failures first; the release workflow still
  # requires every UI test, including the eleven already-green focused cases.
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/HistoricalIncomeInteractionTests
    -only-testing:PivotUITests/OnlineCoachInteractionTests/testSwitchingToLocalCancelsPreflightWithoutSendingOrLosingComposer
    -only-testing:PivotUITests/PivotInteractionTests/testIncomeSummarySwipesToChart
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-contacts-regression ]; then
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/OnlineCoachInteractionTests
    -only-testing:PivotUITests/BackupPrivacyInteractionTests
    -only-testing:PivotUITests/SavingsInteractionTests
    -only-testing:PivotUITests/HistoricalIncomeInteractionTests
    -only-testing:PivotUITests/IncomeCorrectionInteractionTests
    -only-testing:PivotUITests/PivotInteractionTests/testIncomeSummarySwipesToChart
  )
elif [ -n "$PIVOT_PLACES_GROUP" ]; then
  while IFS= read -r PIVOT_TEST_FLAG; do
    PIVOT_UI_TEST_COMMAND+=("$PIVOT_TEST_FLAG")
  done <<< "$PIVOT_PLACES_FLAGS"
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-history-regression ]; then
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/OnlineCoachInteractionTests
    -only-testing:PivotUITests/BackupPrivacyInteractionTests
    -only-testing:PivotUITests/SavingsInteractionTests
    -only-testing:PivotUITests/HistoricalIncomeInteractionTests
    -only-testing:PivotUITests/PivotInteractionTests/testIncomeSummarySwipesToChart
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-savings-regression ]; then
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/OnlineCoachInteractionTests
    -only-testing:PivotUITests/BackupPrivacyInteractionTests
    -only-testing:PivotUITests/SavingsInteractionTests
    -only-testing:PivotUITests/PivotInteractionTests/testIncomeSummarySwipesToChart
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-privacy-regression ]; then
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/OnlineCoachInteractionTests
    -only-testing:PivotUITests/BackupPrivacyInteractionTests
  )
elif [ "$PIVOT_UI_ONLY_TESTING" = v8-modern-regression ]; then
  PIVOT_UI_TEST_COMMAND+=(
    -only-testing:PivotUITests/OnlineCoachInteractionTests/testSwitchingToLocalCancelsPreflightWithoutSendingOrLosingComposer
    -only-testing:PivotUITests/PivotInteractionTests/testSerie7SevenRankSlotsAndManualProfilePersistWithoutInventedBirthDate
    -only-testing:PivotUITests/TrainingConcernInteractionTests/testPainLinksTwoMovementsWithoutStartingWorkoutResolvesAndPersists
  )
elif [ -n "$PIVOT_UI_ONLY_TESTING" ]; then
  PIVOT_UI_TEST_COMMAND+=("-only-testing:$PIVOT_UI_ONLY_TESTING")
fi
# Keep the complete synthetic QA log, but stream just milestones/errors so a
# long run exposes the current test instead of appearing stalled for hours.
"${PIVOT_UI_TEST_COMMAND[@]}" 2>&1 | tee "$PIVOT_UI_LOG" | awk '
  # XCTest assertion messages can contain a multiline synthetic AX hierarchy.
  # Retain that failure context in the durable job log, even after attachments
  # expire. Keep the original full log and every release gate unchanged.
  /error:/ { failure_context = 1; failure_lines = 0 }
  /Test Case .* (passed|failed|skipped) / { failure_context = 0 }
  /Test Case|Test Suite|Executed [0-9]+ tests|error:|\*\* (TEST|BUILD)|^SwiftEmitModule|^SwiftCompile.*InteractionTests|^CodeSign.*PivotUITests-Runner|Running tests\.\.\.|Failed to initialize|Testing failed:|Test session results|Build Timing Summary/ || (failure_context && failure_lines++ < 4000) { print; fflush() }
' || PIVOT_UI_TEST_STATUS=$?
if [ -n "$PIVOT_RELEASE_SHARD" ] && [ "$PIVOT_UI_TEST_STATUS" -eq 0 ]; then
  python3 Scripts/ui_release_shards.py --shard "$PIVOT_RELEASE_SHARD" --verify-log "$PIVOT_UI_LOG" || PIVOT_UI_TEST_STATUS=1
fi
if [ -n "$PIVOT_PLACES_GROUP" ] && [ "$PIVOT_UI_TEST_STATUS" -eq 0 ]; then
  python3 Scripts/ui_release_shards.py --preflight "$PIVOT_PLACES_GROUP" --verify-log "$PIVOT_UI_LOG" || PIVOT_UI_TEST_STATUS=1
fi
if [ -d "$PIVOT_UI_RESULT" ]; then
  xcrun xcresulttool export attachments --path "$PIVOT_UI_RESULT" --output-path "$PIVOT_PREVIEW_OUTPUT/Interactions" || {
    if [ "$PIVOT_UI_TEST_STATUS" -eq 0 ]; then PIVOT_UI_TEST_STATUS=1; fi
  }
fi
PIVOT_APP_DATA=$(xcrun simctl get_app_container "$PIVOT_SIMULATOR" app.pivot.personal data)
if { [ -z "$PIVOT_UI_ONLY_TESTING" ] || [ "$PIVOT_RELEASE_SHARD" = workout ]; } && [ -f "$PIVOT_APP_DATA/Documents/Pivot-QA-report.pdf" ]; then
  cp "$PIVOT_APP_DATA/Documents/Pivot-QA-report.pdf" build/Pivot-QA-report.pdf
fi
if { [ -z "$PIVOT_UI_ONLY_TESTING" ] || [ "$PIVOT_RELEASE_SHARD" = workout ]; } && [ -f "$PIVOT_APP_DATA/Documents/Pivot-QA-finalization.pdf" ]; then
  cp "$PIVOT_APP_DATA/Documents/Pivot-QA-finalization.pdf" build/Pivot-QA-finalization.pdf
fi
exit "$PIVOT_UI_TEST_STATUS"
