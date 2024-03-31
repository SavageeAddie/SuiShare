module SuiShare::board {
    use std::vector;
    use sui::transfer;
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::object::{Self, UID};
    use std::string::{Self, String}; // for names
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};

    // use sui::tx_context::{TxContext, sender};
    use sui::transfer::{transfer, share_object};

    const NotEnoughMoney: u64 = 228;

    struct Debt has key, store {
        id: UID,
        addr: address, // the address of the person to whom the debt is dedicated
        val: u64 // amount of debt
    }

    struct Person has key, store {
        id: UID,
        addr: address,
        name: String,
        debts: vector<Debt>,
        balance: Balance<SUI>
    }

    struct Case has key, store {
        id: UID,
        val: u64, // amount of money spent
        name: String, // Case name, ex: Buying bus tickets
        owner_addr: address // address of man who paid
    }

    struct Group has key, store {
        id: UID,
        name: String, // ex: Travel to Paris
        finished: bool, // are all debts were paid or not
        cases: vector<Case>,
        persons: vector<Person>
    }

    struct Board has key, store {
        id: UID,
        groups: vector<Group>
    }

    fun init(ctx: &mut TxContext)
    {
        let board_id = object::new(ctx);

        let board = Board {
            id: board_id,
            groups: vector::empty<Group>()
        };

        share_object(board);
    }

    fun get_groups(board: &mut Board) : &mut vector<Group>
    {
        return &mut board.groups
    }

    fun get_persons(group: &mut Group) : &mut vector<Person>
    {
        return &mut group.persons
    }

    public fun add_person(group: &mut Group, name: String, ctx: &mut TxContext)
    {
        let persons = get_persons(group);

        let new_person_id = object::new(ctx);
        let sender_addr = sui::tx_context::sender(ctx);
        let new_person = Person {
            id : new_person_id,
            addr: sender_addr,
            name: name,
            debts: vector::empty<Debt>(),
            balance: balance::zero()
        };

        vector::push_back(persons, new_person);

        // share_object(new_person); // PROBABLY NOT NEEDED
    }

    public fun add_group(board: &mut Board, name: String, author_name: String, ctx: &mut TxContext)
    {
        let groups = get_groups(board);
        let new_group_id = object::new(ctx);
        let new_group = Group {
            id : new_group_id,
            name,
            finished : false,
            cases: vector::empty<Case>(),
            persons: vector::empty<Person>()
        };

        add_person(&mut new_group, author_name, ctx);

        vector::push_back(groups, new_group);
        // share_object(new_group); // PROBABLY NOT NEEDED
    }

    fun get_cases(group: &mut Group) : &mut vector<Case>
    {
        return &mut group.cases
    }

    public fun add_debt(person: &mut Person, val: u64, ctx: &mut TxContext)
    {
        let new_debt_id = object::new(ctx);

        let new_debt = Debt {
            id: new_debt_id,
            addr: sui::tx_context::sender(ctx),
            val
        };

        vector::push_back(&mut person.debts, new_debt);

        // share_object(new_debt); // PROBABLY NOT NEEDED
    }

    public fun add_case(group: &mut Group, val: u64, name: String, ctx: &mut TxContext)
    {
        let cases = get_cases(group);
        let sender_addr = sui::tx_context::sender(ctx);

        let new_case_id = object::new(ctx);
        let new_case = Case {
            id: new_case_id,
            val,
            name,
            owner_addr: sender_addr
        };

        vector::push_back(cases, new_case);

        // share_object(new_case); // PROBABLY NOT NEEDED

        let persons = get_persons(group);
        let persons_count = vector::length(persons);
        let splited_value = val / persons_count;

        let i = 0;
        while (i < persons_count) {
            let person = vector::borrow_mut(persons, i);
            if (person.addr != sender_addr) {
                add_debt(person, splited_value, ctx);
            };

            i = i + 1;
        };

    }

    fun get_debts(person: &mut Person) : &mut vector<Debt>
    {
        return &mut person.debts
    }

    public entry fun pay_debt(
        group: &mut Group, payment: &mut Coin<SUI>, ctx: &mut TxContext) {

        let sender_addr = sui::tx_context::sender(ctx);

        let persons = get_persons(group);
        let persons_count = vector::length(persons);

        let i = 0;
        while (i < persons_count) {
            let person = vector::borrow_mut(persons, i);
            if (person.addr == sender_addr) {
                
                // let person_copy = &mut person;
                let debts = &mut person.debts; //get_debts(person_copy);
                let debts_count = vector::length(debts);

                let j = 0;
                while (j < debts_count) {
                    let debt = vector::borrow_mut(debts, j);
                    
                    assert!(coin::value(payment) >= debt.val, NotEnoughMoney);
                    let coin_balance = coin::balance_mut(payment);

                    let paid = balance::split(coin_balance, debt.val);

                    balance::join(&mut person.balance, paid);

                    j = j + 1;
                };
            };

            i = i + 1;
        };

    }





}