# Import slice: editable JW timetable name

## What

Aligned the JW direct-import confirmation screen with Android 1.0.51 by adding an
editable timetable-name field before the start-date field.

- The field uses the existing localized `import_table_name` label and the existing
  iOS surface/shape tokens.
- It is prefilled with `jw_import_title(学校名)` after HTML parsing.
- The user-entered value is trimmed before import.
- An empty or whitespace-only value falls back to the localized default template.
- The field has the stable accessibility identifier `jw_config_table_name`.
- The existing JW error-banner Button conversion in the same dirty file was
  preserved; no parser, repository, DAO, or preference behavior was changed.

## Evidence

- Android source: `app/src/main/java/com/lingion/sleepy/ui/screen/imports/JwImportActivity.kt`
  (`ConfigureConfirm` timetable-name `OutlinedTextField`).
- iOS source: `Sleepy/ui/screen/imports/JwImportFlow.swift`.
- Existing `import_table_name` localization entries were confirmed in all five
  supported locales; no duplicate key was added.
- Generic iOS build: `** BUILD SUCCEEDED **`.
- `git diff --check`: passed.
- `rg -n 'onTapGesture|TODO|FIXME' Sleepy/ui`: no matches.

## Scope

This increment changes only the JW import confirmation behavior and its slice
report. Existing unrelated worktree changes were preserved.

## Known remaining Import work

The matrix remains `in-progress`. Android-equivalent WebView fetch timeout,
additional protocol-specific JavaScript paths, frame-capture retry behavior, and
diagnostic error hints still require separate comparison and implementation.
