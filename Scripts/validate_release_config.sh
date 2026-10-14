#!/bin/sh
# Xcode build phase: catches release-blocking configuration mistakes.
# - Any Release build with ads enabled must have real (non-test) AdMob IDs.
# - Archiving (ACTION=install) a Release build without an AdMob app ID fails, because the
#   Google Mobile Ads SDK expects GADApplicationIdentifier to be present.
TEST_PUB="ca-app-pub-3940256099942544"
if [ "${CONFIGURATION}" = "Release" ]; then
  case "${LUMA_GAD_APP_ID}${LUMA_GAD_INTERSTITIAL_ID}${LUMA_GAD_REWARDED_ID}" in
    *"${TEST_PUB}"*)
      echo "error: Release build contains Google sample ad IDs. Set real IDs in Config/Secrets.xcconfig."
      exit 1 ;;
  esac
  if [ -z "${LUMA_GAD_APP_ID}" ]; then
    if [ "${ACTION}" = "install" ]; then
      echo "error: LUMA_GAD_APP_ID is empty. Archived builds need a real AdMob app ID (see README > Ads)."
      exit 1
    fi
    echo "warning: LUMA_GAD_APP_ID is empty; ads are disabled in this Release build. Configure it before archiving."
  fi
  case "${PRODUCT_BUNDLE_IDENTIFIER}" in
    com.example.*) echo "warning: Bundle identifier is still the placeholder ${PRODUCT_BUNDLE_IDENTIFIER}." ;;
  esac
fi
exit 0
