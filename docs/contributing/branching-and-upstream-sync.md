# Branching and upstream sync

NotchKit is a fork of [`TheBoredTeam/boring.notch`](https://github.com/TheBoredTeam/boring.notch).
We keep a clean separation between upstream code and NotchKit work.

## Branches

| Branch | Purpose | Rules |
| --- | --- | --- |
| `main` | Upstream mirror | Only fast-forward updates from `upstream/main`. No NotchKit feature commits. |
| `master` | Stable NotchKit baseline | Selectively merge reviewed upstream changes from `main`. Integration-ready. |
| `development` | Active NotchKit integration | Approved NotchKit work lands here. Target of feature PRs. |
| `feature/*` | Individual work | Branch from `development`, target `development` when done. |

Never blindly merge upstream PRs or the upstream `dev` branch. Port changes
deliberately; see below.

## One-time setup

```sh
git remote add upstream https://github.com/TheBoredTeam/boring.notch.git
git fetch upstream
```

## Routine flow

1. **Refresh the mirror.**
   ```sh
   git fetch upstream
   git switch main
   git merge --ff-only upstream/main
   ```
   If the fast-forward fails, stop: someone has committed on `main`, which
   breaks the mirror invariant.

2. **Sync the stable baseline.** Compare and review, then merge selectively:
   ```sh
   git switch master
   git merge --no-ff main
   ```
   Resolve conflicts here, not on `main`.

3. **Integrate.** Merge `master` into `development` when the baseline moves:
   ```sh
   git switch development
   git merge --no-ff master
   ```

4. **Feature work.**
   ```sh
   git switch development
   git switch -c feature/<short-name>
   # ... work ...
   git switch development
   git merge --no-ff feature/<short-name>
   ```
   Open PRs against `development`.

## Safe diff-and-port procedure

Use this to evaluate an upstream change without merging the branch.

1. Identify the commit(s):
   ```sh
   git fetch upstream
   git log --oneline upstream/main -n 40
   ```

2. Inspect the change in isolation:
   ```sh
   git show <sha> --stat
   git diff <sha>^ <sha>
   ```

3. Decide fit. Ask:
   - Does it touch files we changed on `master`/`development`?
   - Does it affect notch geometry, windowing, permissions, or persistence?
     If so, port carefully and re-test.
   - Does it add a dependency or raise the deployment target?

4. Apply as a deliberate, reviewable commit. Prefer cherry-pick with `-x` or a
   hand port over merging an upstream branch:
   ```sh
   git switch master
   git cherry-pick -x <sha>
   ```
   If the pick conflicts or carries unrelated commits, hand-port the minimal
   change instead.

5. If the change is large or structural, split it into multiple commits, each
   with a reason.

6. Record divergences. When we intentionally skip or adapt an upstream change,
   note it in the PR description or a follow-up issue.

## Review checklist for upstream ports

- [ ] Builds at the macOS 14 deployment target.
- [ ] No new `ExtensionFoundation`/`ExtensionKit` dependency.
- [ ] No network calls or marketplace/backend surface.
- [ ] Notch geometry, windowing, permissions, and persistence ownership
      unchanged or deliberately reviewed.
- [ ] Core rendering/routing seams still go through `NotchAPI`/
      `NotchExtensions`.

## Guardrails

- Never commit directly to `main` or `master`.
- Never force-push `main`, `master`, or `development`.
- Keep `main` a strict mirror so `git log --oneline main` is always upstream.
- Prefer small, reviewed ports over broad merges.
