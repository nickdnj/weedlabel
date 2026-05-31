fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build the Beta scheme and upload to TestFlight

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Push App Store listing metadata + screenshots (no binary)

### ios check_metadata

```sh
[bundle exec] fastlane ios check_metadata
```

Verify metadata locally without uploading (lengths, assets)

### ios make_app

```sh
[bundle exec] fastlane ios make_app
```

Register the bundle ID via API (the app RECORD must be made in the web UI)

### ios auth_check

```sh
[bundle exec] fastlane ios auth_check
```

Verify the API key authenticates and report whether the app record exists

### ios internal_testing

```sh
[bundle exec] fastlane ios internal_testing
```

Create an internal TestFlight group + add the account holder as tester

### ios tf_status

```sh
[bundle exec] fastlane ios tf_status
```

List TestFlight builds + their processing state

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
