# Step 06 - Authoritative Git/GitHub baseline publication

Date: 2026-09-27. Repository: ArdaHFO/FrenchApp. This is repository establishment only; no application behavior or API integration was changed.

## A. Purpose

The working application after Steps 00-05 needed a trustworthy source-history rollback point before API/content architecture decisions. The old local index was not a baseline. This task selected the current working-tree files, verified them, committed them on `main` and published them normally to the designated GitHub repository.

Report 05 and its preservation conclusions were reviewed before acting. The current validation results below are newly executed, not copied from that report.

## B. Pre-existing Git state and preserved evidence

Before modifying any file/index/branch/remote:

- Local branch: unborn `master`.
- `git rev-parse --verify HEAD`: exit 128, `fatal: Needed a single revision`.
- No remotes configured.
- Partial historical index: 17 status entries, including staged/modified files and two indexed-but-absent prototype files. Most of the current implementation was untracked.
- Initial index SHA-256: `6a21249c9265d474b15a4e37ac924abac5bd443f7b781832f434b38059018bee`.

Preservation record: `%TEMP%/frenchapp-step06-sl3px7hp/initial_state.json`. It contains exact short and full untracked Git status, branch/HEAD/remotes results including stderr/exit codes, original index hash, top-level path inventory and a 684-file SHA-256/byte-size inventory. Exclusions from broad hashing: `.git`, build, `.dart_tool`, `.gradle`, `.idea`, Python cache directories. Existing local checkpoints, staging, delivery/editorial files and the root APK were included where not in those excluded cache directories. Thus the inventory can verify that excluded authored/operational material was not deleted or rewritten.

Small byte-preservation copies are `index.before`, `config.before`, `gitignore.before`, and `android-gitignore.before` in the same OS temporary folder. No additional source checkpoint was created. `staging_manifest.json` records all 206 selected paths with mode, SHA-256 and size; `staged-stat.txt`, `safety_scan.json`, `sensitive_paths.json` and `ignored-boundary.txt` preserve local audit detail. These temporary records are not published as source.

### Destination discrepancy: existing license-only history preserved

Contrary to the empty-repository assumption, read-only `git ls-remote --symref` found remote `main` at `1c356099a4af805cbdc660bc465810d31ad58058`, message `Initial commit`. Fetch and tree inspection established that it contains **only `LICENSE`**, a 1,064-byte MIT license with the existing ArdaHFO copyright. No README or application history existed there. An attempted README read correctly reported that it was absent.

That existing commit is retained as the application baseline's parent, and its LICENSE blob is retained unchanged. This task did not choose a new license or force-push over remote history. Consequently the initial **application** commit is not the repository's root commit; it is the first complete application snapshot after the pre-existing license-only root.

### Safe index normalization

`git read-tree -h` confirmed `--empty` only empties the index and `-u` is the separate working-tree update option. This task used `git read-tree --empty` **without `-u`**, followed by `git add --all` under the reviewed ignore rules. No checkout, destructive reset, clean, file deletion or resurrection of historical prototypes occurred.

`refs/heads/main` was created at the fetched license commit and HEAD pointed to it using Git metadata operations. `origin` was added (there was no old origin to overwrite). Local `core.autocrlf=false` prevents staged byte normalization; previously effective autocrlf was true. All 206 staged blobs were compared byte-for-byte against working files, not merely by text diff. `android/gradlew` was marked executable in the index (100755), without changing its already-LF file bytes.

## C. Publication boundary and concise staging manifest

The application baseline contains **206 files / 27,177,516 uncompressed blob bytes**. Relative to its license-only parent it adds **205 files / 76,251 text insertions**, with no deletions. The existing LICENSE is the remaining tree entry.

| Category | Files | Selection |
|---|---:|---|
| `lib/` | 71 | Current application including Step 02-05 repairs and the existing prototype screen |
| `test/` | 20 | Current test suites and real-SQLite probe helper |
| `android/` | 26 | Portable manifests/resources/Gradle config/wrapper, signing placeholder example; no SDK paths or real signing files |
| `assets/` | 2 | `assets/db/content.db`, `assets/db/content.version` |
| `content/grammar/` | 19 | Authored lessons |
| `content/overrides/` | 3 | Stable authored overrides |
| `content/tools/` | 31 | Tools, tool tests and tooling README; no mutable review jobs |
| `content/reports/` | 16 | Historical measurements/build/source-resolution reports and missing-translation CSV; useful provenance, not required runtime source |
| `codex_reports/` | 6 | Reports 00-05, original bytes |
| `.github/` | 1 | Existing quality workflow unchanged |
| Root portable files | 11 | `.gitignore`, `.metadata`, `LICENSE`, `analysis_options.yaml`, `pubspec.yaml`, `pubspec.lock`, README, PLAN, DATA_PIPELINE, TEST, THIRD_PARTY_NOTICES |

Required DB/version/generated Dart marker, all current source/tests and six workflow reports were explicitly verified in the index. `lib/features/prototype/fake_words.dart` and `word_card.dart` were absent before and remain absent; old index entries did not recreate them. The current `prototype_screen.dart` is included because it exists in the current application.

Full durable path/mode/object manifest can be reconstructed using `git ls-tree -r --long 34f30d6a6db92cb606cf4d73e45026f5bee1e569`. A filename-by-filename staged review, staged-size audit, deleted-entry check, exclusion check and blob-vs-working-byte comparison preceded commit.

## D. Secret/local-file audit

The focused audit checked file names for `.env` variants, signing keys/keystores, private-key extensions, key.properties, service-account/credential JSON and local SDK configuration. Candidate authored text was scanned for private-key headers, common GitHub/AWS/Google token formats, password/secret/key/token assignments and machine-specific absolute paths. Matching values were not logged. Generated caches and excluded checkpoint/editorial/transfer copies were not treated as publication candidates; a wider filename search also checked local secret-file names.

Findings:

- `android/local.properties`: machine-specific SDK configuration, excluded and retained locally.
- `android/key.properties.example`: inspected; placeholder passwords and a clearly illustrative keystore path, not actual signing material. Included.
- `android/app/build.gradle.kts`: assignment matches are property lookups for externally supplied signing data, not literal credentials. Included unchanged.
- `codex_reports/01_CRITICAL_RUNTIME_INTEGRITY_AUDIT.md`: an existing local path in historical audit evidence, not executable machine configuration or a credential. Report retained byte-identically as requested.
- No actual credential, private key, `.env` file, signing keystore or service-account secret was found in the selected publication set. No secret values are reproduced in this report.

The bundled SQLite file is the existing runtime content asset, not a learner progress DB. Mutable review-work SQLite/job state is excluded. This is a focused source safety audit, not a claim of exhaustive secret-detection capability.

## E. Intentional ignore/configuration changes

Root `.gitignore` retains its existing Flutter/Dart, Python bytecode, IDE, Android SDK/signing, source-download/stage/output, SQLite sidecar and OS-trash rules. Added rules:

| Rules | Purpose |
|---|---|
| `.checkpoints/`, `.staging/`, `deliveries/`, `content/review_work/` | Local recovery, handoff and mutable editorial operations |
| `/*.zip` | Root transfer/export archives |
| `.gradle/`, `.kotlin/` | Build/compiler caches at any depth |
| `*.apk`, `*.aab` | Application build binaries, beyond the existing specific root APK rule |
| `*.log`, `*.tmp` | Generated logs/temp files; excludes `content/reports/fetch.log` |
| `*.swo`, `*~` | Additional editor leftovers |
| `.env`, `.env.*`, `!.env.example` | Local environments/secrets, retaining explicit example convention |
| `*.pem`, `*.p12`, `*.pfx`, `*.key`, `credentials.json`, `service-account*.json` | Private key and credential-file categories |

`android/.gitignore`: removed only the three rules `gradle-wrapper.jar`, `/gradlew`, `/gradlew.bat`. These are portable Gradle bootstrap inputs, not machine-specific caches. The 53,636-byte wrapper JAR, shell/batch wrappers and existing version properties are included. All remaining Android ignores remain, including local SDK/signing properties and generated registrant/native caches.

Local Git metadata changes: branch/HEAD establishment on main, origin URL, `core.autocrlf=false`, rebuilt index, executable index mode for `gradlew`, and upstream tracking. These changes do not alter app behavior. No authored source directory, runtime DB or workflow reports are ignored.

## F. Current validation

Existing dependencies only; no local `pub get`, upgrade, APK build or corpus rebuild was run. Python tests create disposable copies/temporary DBs, not a bundled-corpus rebuild.

| Exact command | Exit | Runner result | Wall seconds |
|---|---:|---|---:|
| `flutter analyze --fatal-infos --no-pub` | 0 | No issues found (analyzer 12.0 s) | 15.062 |
| `flutter test --no-pub` | 0 | 198 passed, no reported skips | 333.181 |
| `python -B -m unittest discover -s content/tools/tests -p "test_*.py"` | 0 | 86 run, OK, skipped=10 (76 non-skipped) | 42.629 |
| `python -B content/tools/14_validate_db.py` | 0 | Structural and learning-safety checks passed | 0.283 |
| `python -B content/tools/journey_revision_audit.py --db assets/db/content.db --json` | 0 | All six level revisions match; JSON exit_code=0 | 0.111 |
| `python -B -m unittest discover -s content/tools/tests -p "test_output_paths.py" -v` | 0 | 35 run, OK, skipped=10 | 12.108 |

The focused Python follow-up was run to resolve skip reasons, not to conceal a failed suite. All ten skips are symlink tests with `OSError`, errno 22, **WinError 1314: required privilege not held**. Cases are dart_db_symlink, dart_marker_symlink, dart_source_symlink, marker_db_symlink and marker_source_symlink, each for CLI and writer modes. Hardlink and other applicable cases ran. Detailed scenario output is `%TEMP%/frenchapp-step06-path-scenarios.json`.

Warnings/attempts:

- The initial Flutter launch attempt could not open logs inside the sandbox-created preservation directory (access denied), so no analyzer/test executed in that attempt. The same commands were rerun successfully using logs directly in OS temp. This was not an application failure or dependency change.
- Full Flutter run logs two handled `flutter_tts` MissingPluginException diagnostics for `getLanguages` and one existing sqflite default-factory warning block bracketed by two warning markers. No test failures.
- unittest writes its successful runner output to stderr, which PowerShell decorates as NativeCommandError; the actual exit code is zero. The expected `invalid content output plan` diagnostic is from output-collision validation, followed by an OK runner result, not a corpus failure.
- Sandboxed Git reads warn that the external global ignore file is inaccessible; repository-controlled ignore rules were explicitly inspected and exclusions verified. Git mutations/pushes used the authorized external execution context.

Validation logs: `%TEMP%/frenchapp-step06-{analyze,full,python-tests,validate-db,journey-audit,path-tests}.log`. Local validation is established; this report does not assert GitHub Actions completion or an Android APK/device build. The pre-existing quality workflow is published unchanged.

## G. Initial application commit

- Message: `chore: establish stable pre-API migration baseline`
- SHA: **`34f30d6a6db92cb606cf4d73e45026f5bee1e569`**
- Branch: **`main`**
- Parent: existing license-only `1c356099a4af805cbdc660bc465810d31ad58058`.

Commit was created only after successful validation and staging review. Working Git status was clean after committing. This commit contains the current application, not the partial historical index. It will not be amended or rewritten.

## H. GitHub remote and publication sequence

- Repository: `ArdaHFO/FrenchApp`.
- Origin: `https://github.com/ArdaHFO/FrenchApp.git`.
- `git push -u origin main`: successful normal fast-forward `1c35609..34f30d6`.
- `git ls-remote origin refs/heads/main`: **`34f30d6a6db92cb606cf4d73e45026f5bee1e569`**, equal to local application baseline HEAD.
- Upstream established: `origin/main`.

This report was created **after** that initial commit was successfully pushed and verified. It is to be committed separately with `docs: record GitHub baseline publication`, staging only this report. Its own commit SHA cannot be embedded in its content without self-reference; it is recorded in the final implementation handoff. The initial application commit remains unchanged.

After that documentation commit is pushed, the authorized annotated rollback tag is `baseline-pre-api-migration-2026-09-27`, annotation `Stable FrenchApp baseline before API/content architecture migration`, pointing at the report-containing main commit. Final execution verifies the local/remote main SHA, tag object and peeled tag commit and reports those results in the handoff. This paragraph describes that final publication procedure; it does not pre-claim a future push before execution.

## I. Largest published files

| File | Bytes |
|---|---:|
| `assets/db/content.db` | 24,387,584 |
| `content/reports/missing_tr.csv` | 370,245 |
| `content/overrides/editorial_fa010b.json` | 170,623 |
| `codex_reports/00_REPOSITORY_DEEP_ANALYSIS.md` | 127,410 |
| `test/progress_consistency_test.dart` | 112,234 |
| `content/overrides/manual.json` | 95,710 |
| `codex_reports/01_CRITICAL_RUNTIME_INTEGRITY_AUDIT.md` | 83,268 |
| `test/app_smoke_test.dart` | 58,438 |
| `android/gradle/wrapper/gradle-wrapper.jar` | 53,636 |
| `lib/data/repositories.dart` | 48,559 |

No selected file reaches 100 MiB; the runtime DB is about 23.26 MiB and remains ordinary Git. No LFS was introduced. GitHub's documented hard file limit is 100 MiB, with warnings above 50 MiB. [GitHub large-file documentation](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github).

## J. Excluded local material

Confirmed not staged and still present locally: `.checkpoints/`, `.staging/`, `deliveries/`, `content/review_work/`, `build/`, `.dart_tool/`, root `FrenchApp.apk`, root `FA-013-run-004-handoff.zip`, and `android/local.properties`. Existing IDE state, Gradle/Kotlin caches, Python caches, source downloads/stages/outputs remain ignored. Private signing paths are ignored; no actual signing files were discovered inside the workspace.

No excluded files were deleted to achieve a clean status. Historical stable content reports are intentionally versioned; mutable jobs, build logs and transfer artifacts are not. Existing checkpoints and report-preservation evidence remain on disk for local recovery.

## K. Integrity and final source boundary

All 684 inventory entries were rechecked after staging/validation/application publication. The only modified pre-existing authored files are **`.gitignore` and `android/.gitignore`**. App source, tests, runtime DB/markers, lockfile and reports 00-05 are unchanged. The only new non-report source-tree file is the exact LICENSE copied from the existing remote commit. Every application-baseline Git blob equals the selected working file's original bytes (with the two intentional ignore edits); executable mode is the only wrapper metadata change.

| Protected path | Bytes | SHA-256 before = after |
|---|---:|---|
| `assets/db/content.db` | 24387584 | `6cb13e39aa05fc372033b204a1b68d41776018d519b6813ecdbf04b6581c7417` |
| `assets/db/content.version` | 74 | `3fc22e0ffec33e0a297546256fa7d2eed4815afd39da4e80f888cb57ecfaad9a` |
| `lib/data/content_version.dart` | 213 | `97caaaa95d35e3c3f8484451347d12fe68bf46bd4083bd8aa6aff6c6e8a3d8d6` |
| `pubspec.lock` | 20279 | `b3819b55fa193d12665d185e6b00f5bc717b81e4e5fd7ac9ca9f7044a0c90fbf` |
| `lib/app/app_state.dart` | 21472 | `e8f1be8ca503a50dd5ae392fc27d4fe58ca107aa779cd0be9dc283b8251346ef` |
| `lib/data/repositories.dart` | 48559 | `3c59dc621ae2e0606db248c03bd819a94f5b16848b3a780e1c0844c6624670d6` |
| `test/progress_consistency_test.dart` | 112234 | `70ee9627fea265ac5a21933810dc23cf916315b2147b107277c57e014c1d063d` |
| `codex_reports/00_REPOSITORY_DEEP_ANALYSIS.md` | 127410 | `7132f9501d6e1a1ab87cde206c3a89e28df1fac9fc27b8720648a0f3355b9b7b` |
| `codex_reports/01_CRITICAL_RUNTIME_INTEGRITY_AUDIT.md` | 83268 | `fd0767a078866173ad64d63928dda6610249c7c3879994915828dfd1e8a1019f` |
| `codex_reports/02_PERSISTENCE_CACHE_COMMIT_FIX.md` | 21232 | `04f9e38141648a6e13f48071c444c76bcedd03aa9001a6ca80c0e7fa5ef5f8b8` |
| `codex_reports/03_COMPLETION_ATOMICITY_FIX.md` | 30488 | `9856713e19a4063368ca096ca8c3c19a7d36b50460c8b68dfce0c8557f05b27c` |
| `codex_reports/04_FREE_QUIZ_ATOMICITY_FIX.md` | 28709 | `e5c8a5c93d5fbd2e1fc0304e9f446655fd79d4e511a71f7992cea96a6ad88afc` |
| `codex_reports/05_SONG_STAR_STALE_WRITE_AUDIT_FIX.md` | 28794 | `d90ed3c0058def66ccb5845d5c9e29de2be9f8a7e6c23472d551d366f3f96a6f` |

The Git index was intentionally replaced, as authorized; its original bytes/hash are preserved locally, not claimed unchanged. No application source/content was changed merely for Git publication. Obsolete absent prototype files remain absent.

The second commit is documentation-only. After it, expected tracked/untracked status is clean; ignored local artifacts remain outside the authoritative source boundary. Actual main/tag remote equality and final `git status` are checked after the report/tag pushes rather than asserted prematurely inside this self-referential report.

## L. Next phase

The next planned engineering decision phase is API feasibility benchmarking. No API migration has begun yet.
