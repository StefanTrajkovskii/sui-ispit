// =============================================================================
// Task Management & Reward System - Sui Move Final Project (Topic 2)
// =============================================================================

#[allow(duplicate_alias, unused_const, lint(public_entry))]
module task_manager::task_manager {

    use std::string::String;
    use sui::table::{Self, Table};
    use sui::event;
    use sui::display;
    use sui::package;

    // =========================================================================
    // Constants
    // =========================================================================

    /// Points required per level (level N requires N * 100 cumulative points)
    const POINTS_PER_LEVEL: u64 = 100;

    /// Task status: Pending
    const STATUS_PENDING: u8 = 0;
    /// Task status: Completed
    const STATUS_COMPLETED: u8 = 1;
    /// Task status: Cancelled (admin only)
    const STATUS_CANCELLED: u8 = 2;

    // =========================================================================
    // Error Codes
    // =========================================================================

    const ETaskNotFound: u64 = 1;
    const ETaskNotPending: u64 = 2;
    const ENotAssignee: u64 = 3;
    const ENotCreator: u64 = 4;
    const EUserProfileNotFound: u64 = 5;
    const ETaskAlreadyAssigned: u64 = 6;
    const EInvalidRewardPoints: u64 = 7;

    // =========================================================================
    // One-Time Witness (OTW)
    // =========================================================================

    /// One-time witness type for package init (name = upper-case module name).
    public struct TASK_MANAGER has drop {}

    // =========================================================================
    // Events
    // =========================================================================

    /// Emitted when a new task is created.
    public struct TaskCreated has copy, drop {
        task_id: u64,
        creator: address,
        title: String,
        reward_points: u64,
    }

    /// Emitted when a task is assigned to a user.
    public struct TaskAssigned has copy, drop {
        task_id: u64,
        assignee: address,
    }

    /// Emitted when a task is marked complete and points are awarded.
    public struct TaskCompleted has copy, drop {
        task_id: u64,
        assignee: address,
        points_awarded: u64,
    }

    /// Emitted when a user levels up.
    public struct UserLeveledUp has copy, drop {
        user: address,
        new_level: u8,
    }

    /// Emitted when a task is cancelled by admin.
    public struct TaskCancelled has copy, drop {
        task_id: u64,
        cancelled_by: address,
    }

    // =========================================================================
    // Structs
    // =========================================================================

    /// A single task with reward points. Stored inside TaskBoard (no UID; keyed by task_id in table).
    public struct Task has store, drop {
        title: String,
        description: String,
        reward_points: u64,
        status: u8,
        creator: address,
        assignee: option::Option<address>,
    }

    /// Shared object: registry of all tasks.
    public struct TaskBoard has key, store {
        id: object::UID,
        task_count: u64,
        tasks: Table<u64, Task>,
    }

    /// User profile: owned object tracking stats and level.
    public struct UserProfile has key, store {
        id: object::UID,
        owner: address,
        total_tasks_completed: u64,
        total_points_earned: u64,
        level: u8,
    }

    /// Capability granting admin rights (e.g. cancel task).
    public struct AdminCap has key, store {
        id: object::UID,
    }

    // =========================================================================
    // Init (OTW + Publisher + Display + AdminCap + TaskBoard)
    // =========================================================================

    fun init(witness: TASK_MANAGER, ctx: &mut TxContext) {
        let publisher = package::claim(witness, ctx);
        let sender = tx_context::sender(ctx);

        // Display for TaskBoard
        let mut display_board = display::new<TaskBoard>(&publisher, ctx);
        display::add(&mut display_board, std::string::utf8(b"name"), std::string::utf8(b"TaskBoard"));
        display::add(&mut display_board, std::string::utf8(b"description"), std::string::utf8(b"Shared task registry"));
        display::update_version(&mut display_board);
        transfer::public_transfer(display_board, sender);

        // Display for UserProfile
        let mut display_profile = display::new<UserProfile>(&publisher, ctx);
        display::add(&mut display_profile, std::string::utf8(b"name"), std::string::utf8(b"UserProfile"));
        display::add(&mut display_profile, std::string::utf8(b"description"), std::string::utf8(b"User stats and level"));
        display::update_version(&mut display_profile);
        transfer::public_transfer(display_profile, sender);

        transfer::public_transfer(publisher, sender);

        // Shared TaskBoard
        let board = TaskBoard {
            id: object::new(ctx),
            task_count: 0,
            tasks: table::new(ctx),
        };
        transfer::share_object(board);

        // Admin capability to deployer
        let admin_cap = AdminCap {
            id: object::new(ctx),
        };
        transfer::transfer(admin_cap, sender);
    }

    // =========================================================================
    // Public Entry Functions
    // =========================================================================

    /// Create a new task and add it to the board. Anyone can create.
    public entry fun create_task(
        board: &mut TaskBoard,
        title: vector<u8>,
        description: vector<u8>,
        reward_points: u64,
        ctx: &mut TxContext,
    ) {
        assert!(reward_points > 0, EInvalidRewardPoints);
        let creator = tx_context::sender(ctx);
        let task_count = board.task_count;
        let task_id = task_count;
        board.task_count = task_count + 1;

        let task = Task {
            title: std::string::utf8(title),
            description: std::string::utf8(description),
            reward_points,
            status: STATUS_PENDING,
            creator,
            assignee: option::none(),
        };
        table::add(&mut board.tasks, task_id, task);

        event::emit(TaskCreated {
            task_id,
            creator,
            title: std::string::utf8(title),
            reward_points,
        });
    }

    /// Assign a task to an address. Only the task creator can assign.
    public entry fun assign_task(
        board: &mut TaskBoard,
        task_id: u64,
        assignee: address,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&board.tasks, task_id), ETaskNotFound);
        let task = table::borrow_mut(&mut board.tasks, task_id);
        assert!(task.status == STATUS_PENDING, ETaskNotPending);
        assert!(option::is_none(&task.assignee), ETaskAlreadyAssigned);
        assert!(task.creator == tx_context::sender(ctx), ENotCreator);

        option::fill(&mut task.assignee, assignee);

        event::emit(TaskAssigned {
            task_id,
            assignee,
        });
    }

    /// Complete a task: caller must be the assignee. Awards points and may level up.
    public entry fun complete_task(
        board: &mut TaskBoard,
        task_id: u64,
        profile: &mut UserProfile,
        ctx: &mut TxContext,
    ) {
        let sender = tx_context::sender(ctx);
        assert!(profile.owner == sender, EUserProfileNotFound);
        assert!(table::contains(&board.tasks, task_id), ETaskNotFound);

        let task = table::borrow_mut(&mut board.tasks, task_id);
        assert!(task.status == STATUS_PENDING, ETaskNotPending);
        let assignee = *option::borrow(&task.assignee);
        assert!(assignee == sender, ENotAssignee);

        task.status = STATUS_COMPLETED;
        let points = task.reward_points;

        profile.total_tasks_completed = profile.total_tasks_completed + 1;
        profile.total_points_earned = profile.total_points_earned + points;

        let old_level = profile.level;
        level_up(profile);
        let new_level = profile.level;

        event::emit(TaskCompleted {
            task_id,
            assignee: sender,
            points_awarded: points,
        });
        if (new_level > old_level) {
            event::emit(UserLeveledUp {
                user: sender,
                new_level,
            });
        };
    }

    /// Admin only: cancel a task (removes from circulation).
    public entry fun cancel_task(
        _admin: &AdminCap,
        board: &mut TaskBoard,
        task_id: u64,
        ctx: &mut TxContext,
    ) {
        assert!(table::contains(&board.tasks, task_id), ETaskNotFound);
        let task = table::borrow_mut(&mut board.tasks, task_id);
        assert!(task.status == STATUS_PENDING, ETaskNotPending);
        task.status = STATUS_CANCELLED;

        event::emit(TaskCancelled {
            task_id,
            cancelled_by: tx_context::sender(ctx),
        });
    }

    /// Create and receive a UserProfile. Call once per user.
    public entry fun create_user_profile(ctx: &mut TxContext) {
        let sender = tx_context::sender(ctx);
        let profile = UserProfile {
            id: object::new(ctx),
            owner: sender,
            total_tasks_completed: 0,
            total_points_earned: 0,
            level: 0,
        };
        transfer::transfer(profile, sender);
    }

    // =========================================================================
    // Private Helpers
    // =========================================================================

    /// Level up when total points cross threshold: level = min(255, points / POINTS_PER_LEVEL).
    fun level_up(profile: &mut UserProfile) {
        let level_from_points = (profile.total_points_earned / POINTS_PER_LEVEL) as u8;
        if (level_from_points > 255u8) {
            profile.level = 255;
        } else {
            profile.level = level_from_points;
        };
    }

    // =========================================================================
    // Getter Functions
    // =========================================================================

    /// Get task count on the board.
    public fun task_count(board: &TaskBoard): u64 {
        board.task_count
    }

    /// Check if a task exists.
    public fun task_exists(board: &TaskBoard, task_id: u64): bool {
        table::contains(&board.tasks, task_id)
    }

    /// Get task title.
    public fun get_task_title(board: &TaskBoard, task_id: u64): String {
        assert!(table::contains(&board.tasks, task_id), ETaskNotFound);
        let task = table::borrow(&board.tasks, task_id);
        task.title
    }

    /// Get task description.
    public fun get_task_description(board: &TaskBoard, task_id: u64): String {
        assert!(table::contains(&board.tasks, task_id), ETaskNotFound);
        let task = table::borrow(&board.tasks, task_id);
        task.description
    }

    /// Get task reward points.
    public fun get_task_reward_points(board: &TaskBoard, task_id: u64): u64 {
        assert!(table::contains(&board.tasks, task_id), ETaskNotFound);
        let task = table::borrow(&board.tasks, task_id);
        task.reward_points
    }

    /// Get task status (0=Pending, 1=Completed, 2=Cancelled).
    public fun get_task_status(board: &TaskBoard, task_id: u64): u8 {
        assert!(table::contains(&board.tasks, task_id), ETaskNotFound);
        let task = table::borrow(&board.tasks, task_id);
        task.status
    }

    /// Check if task is available (pending and unassigned).
    public fun is_task_available(board: &TaskBoard, task_id: u64): bool {
        if (!table::contains(&board.tasks, task_id)) return false;
        let task = table::borrow(&board.tasks, task_id);
        task.status == STATUS_PENDING && option::is_none(&task.assignee)
    }

    /// Get task creator.
    public fun get_task_creator(board: &TaskBoard, task_id: u64): address {
        assert!(table::contains(&board.tasks, task_id), ETaskNotFound);
        let task = table::borrow(&board.tasks, task_id);
        task.creator
    }

    /// Get task assignee (optional); returns a default address if none.
    public fun get_task_assignee(board: &TaskBoard, task_id: u64): address {
        assert!(table::contains(&board.tasks, task_id), ETaskNotFound);
        let task = table::borrow(&board.tasks, task_id);
        if (option::is_some(&task.assignee)) {
            *option::borrow(&task.assignee)
        } else {
            @0x0
        }
    }

    /// Get user total tasks completed.
    public fun get_user_tasks_completed(profile: &UserProfile): u64 {
        profile.total_tasks_completed
    }

    /// Get user total points earned.
    public fun get_user_points_earned(profile: &UserProfile): u64 {
        profile.total_points_earned
    }

    /// Get user level.
    public fun get_user_level(profile: &UserProfile): u8 {
        profile.level
    }

    /// Get UserProfile owner.
    public fun get_profile_owner(profile: &UserProfile): address {
        profile.owner
    }

    // =========================================================================
    // Test Helpers (#[test_only])
    // =========================================================================

    #[test_only]
    /// Create a TaskBoard for testing (not shared; caller can pass to entry functions).
    public fun create_test_task_board(ctx: &mut TxContext): TaskBoard {
        TaskBoard {
            id: object::new(ctx),
            task_count: 0,
            tasks: table::new(ctx),
        }
    }

    #[test_only]
    /// Create a UserProfile owned by the given address (for testing).
    public fun create_test_user_profile(owner: address, ctx: &mut TxContext): UserProfile {
        UserProfile {
            id: object::new(ctx),
            owner,
            total_tasks_completed: 0,
            total_points_earned: 0,
            level: 0,
        }
    }

    #[test_only]
    /// Create an AdminCap for testing.
    public fun create_test_admin_cap(ctx: &mut TxContext): AdminCap {
        AdminCap {
            id: object::new(ctx),
        }
    }
}
