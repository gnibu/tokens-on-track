# make publish-store   test, archive and upload the Store edition to App Store Connect.
#
# Signs in with the Apple account in Xcode. Without one (CI), export an App Store
# Connect API key: ASC_KEY_PATH=AuthKey_X.p8 ASC_KEY_ID=X ASC_ISSUER_ID=uuid.
# STORE_BUILD_NUMBER / STORE_MARKETING_VERSION override the version, as in
# docs/app-store-build.md.

ARCHIVE := .build/Tokens on Track.xcarchive
AUTH := $(if $(ASC_KEY_PATH),-authenticationKeyPath "$(ASC_KEY_PATH)" -authenticationKeyID "$(ASC_KEY_ID)" -authenticationKeyIssuerID "$(ASC_ISSUER_ID)")

.PHONY: publish-store
publish-store:
	./test.sh --store
	xcodebuild -project TokensOnTrack.xcodeproj -scheme 'Tokens on Track' \
		-configuration AppStore -destination 'generic/platform=macOS' \
		-derivedDataPath .build/store -archivePath "$(ARCHIVE)" \
		-allowProvisioningUpdates $(AUTH) archive
	sed 's|<string>export</string>|<string>upload</string>|' Config/ExportOptions.plist > .build/ExportOptions-upload.plist
	xcodebuild -exportArchive -archivePath "$(ARCHIVE)" \
		-exportPath .build/store-export -exportOptionsPlist .build/ExportOptions-upload.plist \
		-allowProvisioningUpdates $(AUTH)
