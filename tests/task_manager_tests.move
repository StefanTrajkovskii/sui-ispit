// =============================================================================
// Task Manager — Unit tests (separate test file per PDF repository structure)
// =============================================================================

module task_manager::task_manager_tests {

    use task_manager::task_manager::{
        create_task,
        assign_task,
        complete_task,
        cancel_task,
        task_count,
        task_exists,
        get_task_title,
        get_task_reward_points,
        get_task_status,
        is_task_available,
        get_task_assignee,
        get_user_tasks_completed,
        get_user_points_earned,
        get_user_level,
        create_test_task_board,
        create_test_user_profile,
        create_test_admin_cap,
        ETaskNotFound,
        ETaskNotPending,
        ENotCreator,
        ENotAssignee,
        EInvalidRewardPoints,
    };

    // =========================================================================
    // Happy path tests
    // =========================================================================

    #[test]
    /// Create a task and verify task_count and getters.
    fun test_create_task_success() {
        let mut ctx = tx_context::new(@0x1, tx_context::dummy_tx_hash_with_hint(0), 0, 0, 0);
        let mut board = create_test_task_board(&mut ctx);
        create_task(&mut board, b"Fix bug", b"Fix the login bug", 50, &mut ctx);
        assert!(task_count(&board) == 1, 0);
        assert!(task_exists(&board, 0), 1);
        assert!(get_task_title(&board, 0) == std::string::utf8(b"Fix bug"), 2);
        assert!(get_task_reward_points(&board, 0) == 50, 3);
        assert!(get_task_status(&board, 0) == 0, 4); // STATUS_PENDING
        assert!(is_task_available(&board, 0), 5);
        transfer::public_transfer(board, @0x0);
    }

    #[test]
    /// Assign a task and verify assignee.
    fun test_assign_task_success() {
        let mut ctx = tx_context::new(@0x1, tx_context::dummy_tx_hash_with_hint(0), 0, 0, 0);
        let mut board = create_test_task_board(&mut ctx);
        create_task(&mut board, b"Task", b"Desc", 100, &mut ctx);
        assign_task(&mut board, 0, @0x2, &mut ctx);
        assert!(get_task_assignee(&board, 0) == @0x2, 0);
        assert!(!is_task_available(&board, 0), 1);
        transfer::public_transfer(board, @0x0);
    }

    #[test]
    /// Complete a task and verify points and level.
    fun test_complete_task_success() {
        let mut ctx = tx_context::new(@0x1, tx_context::dummy_tx_hash_with_hint(0), 0, 0, 0);
        let mut board = create_test_task_board(&mut ctx);
        create_task(&mut board, b"Task", b"Desc", 100, &mut ctx);
        assign_task(&mut board, 0, @0x1, &mut ctx);
        let mut profile = create_test_user_profile(@0x1, &mut ctx);
        complete_task(&mut board, 0, &mut profile, &mut ctx);
        assert!(get_user_tasks_completed(&profile) == 1, 0);
        assert!(get_user_points_earned(&profile) == 100, 1);
        assert!(get_user_level(&profile) == 1, 2);
        assert!(get_task_status(&board, 0) == 1, 3); // STATUS_COMPLETED
        transfer::public_transfer(board, @0x0);
        transfer::public_transfer(profile, @0x0);
    }

    #[test]
    /// Admin can cancel a pending task.
    fun test_cancel_task_success() {
        let mut ctx = tx_context::new(@0x1, tx_context::dummy_tx_hash_with_hint(0), 0, 0, 0);
        let mut board = create_test_task_board(&mut ctx);
        create_task(&mut board, b"Task", b"Desc", 50, &mut ctx);
        let admin = create_test_admin_cap(&mut ctx);
        cancel_task(&admin, &mut board, 0, &mut ctx);
        assert!(get_task_status(&board, 0) == 2, 0); // STATUS_CANCELLED
        transfer::public_transfer(admin, @0x0);
        transfer::public_transfer(board, @0x0);
    }

    #[test]
    /// Level up: multiple completions increase level.
    fun test_level_up_multiple_tasks() {
        let mut ctx = tx_context::new(@0x1, tx_context::dummy_tx_hash_with_hint(0), 0, 0, 0);
        let mut board = create_test_task_board(&mut ctx);
        create_task(&mut board, b"T1", b"D1", 50, &mut ctx);
        create_task(&mut board, b"T2", b"D2", 50, &mut ctx);
        assign_task(&mut board, 0, @0x1, &mut ctx);
        assign_task(&mut board, 1, @0x1, &mut ctx);
        let mut profile = create_test_user_profile(@0x1, &mut ctx);
        complete_task(&mut board, 0, &mut profile, &mut ctx);
        assert!(get_user_level(&profile) == 0, 0);
        complete_task(&mut board, 1, &mut profile, &mut ctx);
        assert!(get_user_level(&profile) == 1, 1);
        assert!(get_user_points_earned(&profile) == 100, 2);
        transfer::public_transfer(board, @0x0);
        transfer::public_transfer(profile, @0x0);
    }

    // =========================================================================
    // Failure tests (#[expected_failure])
    // =========================================================================

    #[test]
    /// Creating a task with 0 reward points must fail.
    #[expected_failure(abort_code = EInvalidRewardPoints)]
    fun test_create_task_zero_reward_fails() {
        let mut ctx = tx_context::new(@0x1, tx_context::dummy_tx_hash_with_hint(0), 0, 0, 0);
        let mut board = create_test_task_board(&mut ctx);
        create_task(&mut board, b"Task", b"Desc", 0, &mut ctx);
        transfer::public_transfer(board, @0x0);
    }

    #[test]
    /// Only creator can assign; non-creator fails.
    #[expected_failure(abort_code = ENotCreator)]
    fun test_assign_task_not_creator_fails() {
        let mut ctx1 = tx_context::new(@0x1, tx_context::dummy_tx_hash_with_hint(0), 0, 0, 0);
        let mut board = create_test_task_board(&mut ctx1);
        create_task(&mut board, b"Task", b"Desc", 50, &mut ctx1);
        let mut ctx2 = tx_context::new(@0x2, tx_context::dummy_tx_hash_with_hint(1), 0, 0, 0);
        assign_task(&mut board, 0, @0x2, &mut ctx2);
        transfer::public_transfer(board, @0x0);
    }

    #[test]
    /// Only assignee can complete; wrong user fails.
    #[expected_failure(abort_code = ENotAssignee)]
    fun test_complete_task_not_assignee_fails() {
        let mut ctx1 = tx_context::new(@0x1, tx_context::dummy_tx_hash_with_hint(0), 0, 0, 0);
        let mut board = create_test_task_board(&mut ctx1);
        create_task(&mut board, b"Task", b"Desc", 50, &mut ctx1);
        assign_task(&mut board, 0, @0x2, &mut ctx1);
        let mut ctx3 = tx_context::new(@0x3, tx_context::dummy_tx_hash_with_hint(1), 0, 0, 0);
        let mut profile = create_test_user_profile(@0x3, &mut ctx3);
        complete_task(&mut board, 0, &mut profile, &mut ctx3);
        transfer::public_transfer(board, @0x0);
        transfer::public_transfer(profile, @0x0);
    }

    #[test]
    /// Completing an already completed task fails.
    #[expected_failure(abort_code = ETaskNotPending)]
    fun test_complete_task_already_completed_fails() {
        let mut ctx = tx_context::new(@0x1, tx_context::dummy_tx_hash_with_hint(0), 0, 0, 0);
        let mut board = create_test_task_board(&mut ctx);
        create_task(&mut board, b"Task", b"Desc", 50, &mut ctx);
        assign_task(&mut board, 0, @0x1, &mut ctx);
        let mut profile = create_test_user_profile(@0x1, &mut ctx);
        complete_task(&mut board, 0, &mut profile, &mut ctx);
        complete_task(&mut board, 0, &mut profile, &mut ctx);
        transfer::public_transfer(board, @0x0);
        transfer::public_transfer(profile, @0x0);
    }

    #[test]
    /// Getter for non-existent task fails.
    #[expected_failure(abort_code = ETaskNotFound)]
    fun test_get_task_nonexistent_fails() {
        let mut ctx = tx_context::dummy();
        let board = create_test_task_board(&mut ctx);
        get_task_title(&board, 99);
        transfer::public_transfer(board, @0x0);
    }
}
