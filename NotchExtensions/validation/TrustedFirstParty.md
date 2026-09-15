# Validating trusted first-party manifests

These commands validate the **trusted first-party** manifests that live in this
repository. They are metadata-only linting: see the security disclaimer at the
end of `README.md`. A pass is not a security review or approval.

Run everything from `NotchExtensions/validation`:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift build
```

## The canonical reference example

```sh
swift run ext-validate ../examples/HelloExtension/manifest.json
```

Expected: no output, exit code `0`.

## First-party extensions

Once `NotchExtensions/FirstParty/*/manifest.json` exists, validate all of them
in one invocation. This fails with exit code `1` if any manifest has an error,
or `2` if a manifest is missing/unreadable:

```sh
swift run ext-validate ../FirstParty/*/manifest.json
```

To loop explicitly (useful for per-file reporting and to see the exit code of
each manifest):

```sh
for manifest in ../FirstParty/*/manifest.json ../examples/HelloExtension/manifest.json; do
  echo "== $manifest"
  swift run ext-validate "$manifest"
  echo "   exit=$?"
done
```

To validate against the host and SDK versions this checkout ships with, pass
them explicitly rather than relying on the CLI defaults:

```sh
swift run ext-validate ../FirstParty/*/manifest.json \
  --host-version 1.0.0 --sdk-version 1.0.0
```

## CI-style check

The command fails fast on the first error only if you invoke one file at a
time; with multiple paths `ext-validate` reports every issue and exits `1` if
any error was seen. A minimal CI step is therefore:

```sh
swift run ext-validate ../FirstParty/*/manifest.json ../examples/HelloExtension/manifest.json
```

Non-zero exit status fails the step. Note that manifests that are currently
non-conformant will produce `ERR` lines; fix the manifest rather than waiving
the check.
