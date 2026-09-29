# Constraints

- Same as T-0001: 8 GB M1, no Xcode builds, no simulators, no CI; one commit per issue pushed to `main`; public APIs only; Picker for enumerable choices.
- Parallel agents in separate git worktrees (`../.worktrees/<area>`), integrated by cherry-pick. Project-file conflicts were resolved by re-registering each agent's files with the target membership from its own commit; new targets were kept from the agent's project file.
- Shared hot spots were reduced up front by splitting the catalog and routing per category (#42).
