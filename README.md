# Task Management & Reward System

**Sui Move · Topic 2**

A Sui Move module for creating tasks, assigning them to users, completing them for reward points, and leveling up user profiles.

**Repository:** [github.com/StefanTrajkovskii/sui-ispit](https://github.com/StefanTrajkovskii/sui-ispit)

---

## Overview

- **TaskBoard** (shared): Holds all tasks. Anyone can create; creators assign; assignees complete and earn points.
- **UserProfile** (owned): Tracks tasks completed, points earned, and level (every 100 points = 1 level).
- **AdminCap** (owned, deployer only): Allows cancelling pending tasks.

Flow: `create_task` → `assign_task` (creator) → `complete_task` (assignee + UserProfile). Events: TaskCreated, TaskAssigned, TaskCompleted, UserLeveledUp, TaskCancelled.

---

## Project structure

```
├── sources/
│   └── task_manager.move
├── tests/
│   └── task_manager_tests.move
├── Move.toml
├── README.md
└── .gitignore
```

---

## Build & test

```bash
sui move build
sui move test
```

Expect **10 tests** to pass.

---

## Deploy

1. Configure Sui client (e.g. testnet): `sui client active-env`, `sui client active-address`
2. Publish: `sui client publish --gas-budget 100000000`
3. Note **Package ID** and **TaskBoard** ID from the output.

---

## Testnet deployment

| Item | Value |
|------|--------|
| **Package ID** | `0x747a7ffd60eac9df3ee974bed9d53d767e4edabc89bbe12f623eef63f8c7b66c` |
| **Transaction digest** | `7R21Br7h1fmsqEdkUPMeLGz2JwZbmvd51Yy358V9yTob` |
| **TaskBoard** | `0xfeb971cf703acc83dd95ebe534fad57f692f96bf7ad73735c539d58ed39608c3` |
| **AdminCap** | `0x80299a0673da41e644969f37a28f3874c8ca0c409d9afa2ab7f5e6888342bd67` |

### Example: create_task

```bash
sui client call --package 0x747a7ffd60eac9df3ee974bed9d53d767e4edabc89bbe12f623eef63f8c7b66c --module task_manager --function create_task --args 0xfeb971cf703acc83dd95ebe534fad57f692f96bf7ad73735c539d58ed39608c3 "[70,105,120,32,98,117,103]" "[70,105,120,32,108,111,103,105,110]" "50" --gas-budget 10000000
```

- Digest: `4wk18RUXxUrLcA6j7dMXTt5t9chVrXD1BfpBRsY95VX1`

### Example: create_user_profile

```bash
sui client call --package 0x747a7ffd60eac9df3ee974bed9d53d767e4edabc89bbe12f623eef63f8c7b66c --module task_manager --function create_user_profile --gas-budget 10000000
```

---

## API

### Entry / public functions

| Function | Description |
|----------|-------------|
| `create_task(board, title, description, reward_points, ctx)` | Add task. `title`/`description` = `vector<u8>`, reward > 0. Emits TaskCreated. |
| `assign_task(board, task_id, assignee, ctx)` | Assign task (creator only). Emits TaskAssigned. |
| `complete_task(board, task_id, profile, ctx)` | Complete task (assignee only, pass UserProfile). Awards points, may level up. Emits TaskCompleted, UserLeveledUp. |
| `cancel_task(admin, board, task_id, ctx)` | Cancel pending task (AdminCap). Emits TaskCancelled. |
| `create_user_profile(ctx)` | Create UserProfile for sender (call once before completing tasks). |

### Getters

| Function | Returns |
|----------|---------|
| `task_count(board)` | Number of tasks |
| `task_exists(board, task_id)` | bool |
| `get_task_title`, `get_task_description`, `get_task_reward_points`, `get_task_status` | Task fields |
| `get_task_creator`, `get_task_assignee` | address |
| `is_task_available(board, task_id)` | bool (pending & unassigned) |
| `get_user_tasks_completed`, `get_user_points_earned`, `get_user_level(profile)` | UserProfile stats |
| `get_profile_owner(profile)` | address |

Status: `0` = Pending, `1` = Completed, `2` = Cancelled.

### Events

- **TaskCreated** — task_id, creator, title, reward_points  
- **TaskAssigned** — task_id, assignee  
- **TaskCompleted** — task_id, assignee, points_awarded  
- **UserLeveledUp** — user, new_level  
- **TaskCancelled** — task_id, cancelled_by  

---

## Example usage (replace IDs)

```bash
# Create task (title "Fix bug", description "Fix login", 50 pts)
sui client call --package PACKAGE_ID --module task_manager --function create_task --args TASK_BOARD_ID '[70,105,120,32,98,117,103]' '[70,105,120,32,108,111,103,105,110]' '50' --gas-budget 10000000

# Create user profile
sui client call --package PACKAGE_ID --module task_manager --function create_user_profile --gas-budget 10000000

# Assign task 0 (creator only)
sui client call --package PACKAGE_ID --module task_manager --function assign_task --args TASK_BOARD_ID '0' '0xASSIGNEE' --gas-budget 10000000

# Complete task 0 (assignee + UserProfile object ID)
sui client call --package PACKAGE_ID --module task_manager --function complete_task --args TASK_BOARD_ID '0' USER_PROFILE_ID --gas-budget 10000000

# Cancel task 0 (AdminCap)
sui client call --package PACKAGE_ID --module task_manager --function cancel_task --args ADMIN_CAP_ID TASK_BOARD_ID '0' --gas-budget 10000000
```
