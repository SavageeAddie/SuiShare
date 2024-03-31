module SuiShare::board {
    // Import necessary modules and types
    use std::vector;
    use sui::transfer;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use std::string::{Self, String};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer::{transfer, share_object};
    use sui::event::{Self, Event};

    // Custom error codes
    const ENotEnoughMoney: u64 = 0;
    const EInvalidIndex: u64 = 1;
    const EUnauthorizedAccess: u64 = 2;
    const EInvalidInput: u64 = 3;

    // Debt struct represents a debt owed by a borrower to a lender
    struct Debt has key, store {
        id: UID,
        lender: address,
        borrower: address,
        name: String,
        amount: u64,
        paid: bool
    }

    // Person struct represents a member of a group
    struct Person has key, store {
        id: UID,
        addr: address,
        name: String,
        debts: vector<Debt>,
        balance: Balance<SUI>
    }

    // Case struct represents an expense case within a group
    struct Case has key, store {
        id: UID,
        amount: u64,
        name: String,
        owner_addr: address,
        contributors: vector<address>
    }

    // Group struct represents a group of people sharing expenses
    struct Group has key, store {
        id: UID,
        name: String,
        finished: bool,
        admin: address,
        cases: vector<Case>,
        persons: vector<Person>
    }

    // Board struct represents the main board containing all groups
    struct Board has key, store {
        id: UID,
        groups: vector<Group>
    }

    // Event structs for emitting notifications
    struct GroupCreatedEvent has copy, drop {
        group_id: UID,
        group_name: String,
        admin: address
    }

    struct PersonAddedEvent has copy, drop {
        group_id: UID,
        person_id: UID,
        person_name: String,
        person_addr: address
    }

    struct CaseAddedEvent has copy, drop {
        group_id: UID,
        case_id: UID,
        case_name: String,
        case_amount: u64,
        owner_addr: address
    }

    struct DebtCreatedEvent has copy, drop {
        group_id: UID,
        debt_id: UID,
        lender: address,
        borrower: address,
        debt_name: String,
        debt_amount: u64
    }

    // Initialize a new board
    fun init(ctx: &mut TxContext) {
        let board_id = object::new(ctx);
        let board = Board {
            id: board_id,
            groups: vector::empty<Group>()
        };
        share_object(board);
    }

    // Create a new group
    public fun create_group(board: &mut Board, name: String, ctx: &mut TxContext) {
        // Validate input
        assert!(!string::is_empty(&name), EInvalidInput);
        let group_id = object::new(ctx);
        let sender_addr = tx_context::sender(ctx);
        let new_group = Group {
            id: group_id,
            name,
            finished: false,
            admin: sender_addr,
            cases: vector::empty<Case>(),
            persons: vector::empty<Person>()
        };
        vector::push_back(&mut board.groups, new_group);
        // Emit GroupCreatedEvent
        event::emit(GroupCreatedEvent {
            group_id,
            group_name: name,
            admin: sender_addr
        });
    }

    // Add a new person to a group
    public fun add_person(group_index: u64, board: &mut Board, name: String, ctx: &mut TxContext) {
        // Validate input
        assert!(!string::is_empty(&name), EInvalidInput);
        let groups = &mut board.groups;
        // Validate group index
        assert!(group_index < vector::length(groups), EInvalidIndex);
        let group = vector::borrow_mut(groups, group_index);
        // Validate sender as group admin
        assert!(tx_context::sender(ctx) == group.admin, EUnauthorizedAccess);
        let new_person_id = object::new(ctx);
        let sender_addr = tx_context::sender(ctx);
        let new_person = Person {
            id: new_person_id,
            addr: sender_addr,
            name,
            debts: vector::empty<Debt>(),
            balance: balance::zero()
        };
        vector::push_back(&mut group.persons, new_person);
        // Emit PersonAddedEvent
        event::emit(PersonAddedEvent {
            group_id: group.id,
            person_id: new_person_id,
            person_name: name,
            person_addr: sender_addr
        });
    }

    // Add a new case (expense) to a group
    public fun add_case(group_index: u64, board: &mut Board, name: String, amount: u64, ctx: &mut TxContext) {
        // Validate input
        assert!(!string::is_empty(&name), EInvalidInput);
        let groups = &mut board.groups;
        // Validate group index
        assert!(group_index < vector::length(groups), EInvalidIndex);
        let group = vector::borrow_mut(groups, group_index);
        // Validate sender as group admin
        assert!(tx_context::sender(ctx) == group.admin, EUnauthorizedAccess);
        let new_case_id = object::new(ctx);
        let sender_addr = tx_context::sender(ctx);
        let new_case = Case {
            id: new_case_id,
            amount,
            name,
            owner_addr: sender_addr,
            contributors: vector::empty<address>()
        };
        vector::push_back(&mut group.cases, new_case);
        let persons = &mut group.persons;
        let persons_count = vector::length(persons);
        let splited_amount = amount / (persons_count as u64);
        let i = 0;
        while (i < persons_count) {
            let person = vector::borrow_mut(persons, i);
            if (person.addr != sender_addr) {
                let new_debt_id = object::new(ctx);
                let new_debt = Debt {
                    id: new_debt_id,
                    lender: sender_addr,
                    borrower: person.addr,
                    name: name,
                    amount: splited_amount,
                    paid: false
                };
                vector::push_back(&mut person.debts, new_debt);
                // Emit DebtCreatedEvent
                event::emit(DebtCreatedEvent {
                    group_id: group.id,
                    debt_id: new_debt_id,
                    lender: sender_addr,
                    borrower: person.addr,
                    debt_name: name,
                    debt_amount: splited_amount
                });
            } else {
                vector::push_back(&mut new_case.contributors, sender_addr);
            };
            i = i + 1;
        };
        // Emit CaseAddedEvent
        event::emit(CaseAddedEvent {
            group_id: group.id,
            case_id: new_case_id,
            case_name: name,
            case_amount: amount,
            owner_addr: sender_addr
        });
    }

    // Pay a debt owed by the sender to a lender
    public fun pay_debt(group_index: u64, board: &mut Board, debt_index: u64, payment: &mut Coin<SUI>, ctx: &mut TxContext) {
        let groups = &mut board.groups;
        // Validate group index
        assert!(group_index < vector::length(groups), EInvalidIndex);
        let group = vector::borrow_mut(groups, group_index);
        let persons = &mut group.persons;
        let sender_addr = tx_context::sender(ctx);
        let i = 0;
        let persons_count = vector::length(persons);
        while (i < persons_count) {
            let person = vector::borrow_mut(persons, i);
            if (person.addr == sender_addr) {
                let debts = &mut person.debts;
                // Validate debt index
                assert!(debt_index < vector::length(debts), EInvalidIndex);
                let debt = vector::borrow_mut(debts, debt_index);
                // Validate debt not already paid
                assert!(!debt.paid, EInvalidInput);
                // Validate sufficient payment amount
                assert!(coin::value(payment) >= debt.amount, ENotEnoughMoney);
                let coin_balance = coin::balance_mut(payment);
                let paid = balance::split(coin_balance, debt.amount);
                let lender = debt.lender;
                let j = 0;
                while (j < persons_count) {
                    let lender_person = vector::borrow_mut(persons, j);
                    if (lender_person.addr == lender) {
                        balance::join(&mut lender_person.balance, paid);
                    };
                    j = j + 1;
                };
                debt.paid = true;
            };
            i = i + 1;
        };
    }

    // Collect any outstanding balance owed to the sender
    public fun collect_money(group_index: u64, board: &mut Board, ctx: &mut TxContext) {
        let groups = &mut board.groups;
        // Validate group index
        assert!(group_index < vector::length(groups), EInvalidIndex);
        let group = vector::borrow_mut(groups, group_index);
        let persons = &mut group.persons;
        let sender_addr = tx_context::sender(ctx);
        let i = 0;
        let persons_count = vector::length(persons);
        while (i < persons_count) {
            let person = vector::borrow_mut(persons, i);
            if (person.addr == sender_addr) {
                let amount = balance::value(&person.balance);
                let profits = coin::take(&mut person.balance, amount, ctx);
                transfer::public_transfer(profits, sender_addr)
            };
            i = i + 1;
        };
    }

    // Mark a group as finished (all debts paid)
    public fun mark_group_finished(group_index: u64, board: &mut Board, ctx: &mut TxContext) {
        let groups = &mut board.groups;
        // Validate group index
        assert!(group_index < vector::length(groups), EInvalidIndex);
        let group = vector::borrow_mut(groups, group_index);
        // Validate sender as group admin
        assert!(tx_context::sender(ctx) == group.admin, EUnauthorizedAccess);
        group.finished = true;
    }

    // Remove a person from a group
    public fun remove_person(group_index: u64, person_index: u64, board: &mut Board, ctx: &mut TxContext) {
        let groups = &mut board.groups;
        // Validate group index
        assert!(group_index < vector::length(groups), EInvalidIndex);
        let group = vector::borrow_mut(groups, group_index);
        // Validate sender as group admin
        assert!(tx_context::sender(ctx) == group.admin, EUnauthorizedAccess);
        let persons = &mut group.persons;
        // Validate person index
        assert!(person_index < vector::length(persons), EInvalidIndex);
        vector::remove(persons, person_index);
    }

    // Update the name of a group
    public fun update_group_name(group_index: u64, new_name: String, board: &mut Board, ctx: &mut TxContext) {
        // Validate input
        assert!(!string::is_empty(&new_name), EInvalidInput);
        let groups = &mut board.groups;
        // Validate group index
        assert!(group_index < vector::length(groups), EInvalidIndex);
        let group = vector::borrow_mut(groups, group_index);
        // Validate sender as group admin
        assert!(tx_context::sender(ctx) == group.admin, EUnauthorizedAccess);
        group.name = new_name;
    }

    // Transfer group ownership to a new admin
    public fun transfer_group_ownership(group_index: u64, new_admin: address, board: &mut Board, ctx: &mut TxContext) {
        let groups = &mut board.groups;
        // Validate group index
        assert!(group_index < vector::length(groups), EInvalidIndex);
        let group = vector::borrow_mut(groups, group_index);
        // Validate sender as current group admin
        assert!(tx_context::sender(ctx) == group.admin, EUnauthorizedAccess);
        group.admin = new_admin;
    }
}