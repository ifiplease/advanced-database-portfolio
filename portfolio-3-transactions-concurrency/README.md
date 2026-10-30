# Portfolio 3: Transactions and Concurrency Control

**Case study:** VanguardPay

**Database system:** PostgreSQL, managed with pgAdmin 4

## Overview

In this Portfolio , I tested how the VanguardPay database keeps money safe when one operation needs several steps that must all succeed together, and when more than one session touches the same account at the same time. I ran all the work on the seeded database from Portfolio 2.

I split the work into three SQL scripts: `transactions_atomic.sql` (commit, rollback and atomic operations), `concurrency_locking.sql` (lost updates, row locking and deadlocks) and `isolation_levels.sql` (READ COMMITTED against REPEATABLE READ). 

## Key Operations Covered

| Key Operation | What I built |
|---|---|
| 2. Deposit funds | `fn_deposit` updates the balance, writes the `transactions` row and writes the credit log in one transaction |
| 3. Withdraw funds | `fn_withdraw` refuses the request when the balance is too low |
| 4. Transfer funds | `fn_transfer` writes the debit and the credit together, with two log rows |
| 5. Reverse failed transactions | `fn_reverse_transaction` puts the money back, logs the opposite entries and sets the status to `reversed`, the same way my seed script models reversals |
| 6. Audit account balances | `v_balance_audit` compares each stored balance with the credits minus debits in `transaction_logs`. I ran it before and after my tests |

## Stage 1: Atomic Transactions (`transactions_atomic.sql`)

### Test accounts

I picked three active accounts that belong to different customers and hold at least `50000` NGN, and stored them in a small `test_accounts` table with the labels A, B and C. Every test in this portfolio uses these same three accounts. Before any test, account A (`3000000001`) held `69700.00`, account B (`3000000002`) held `200300.00` and account C (`3000000003`) held `362100.00`.

![Test accounts A, B and C with their starting balances in pgAdmin 4](screenshots/pgadmin-test-accounts.png)

*Accounts A, B and C and their starting balances before any test.*

### What I built

- I created `seq_transaction_reference` and `fn_next_reference()` so new transaction references start at `90000001` and never clash with the seeded `VGP` references.
- I wrote three views: `v_balance_audit` (stored balance against log balance for every account), `v_test_account_balances` (the same audit for accounts A, B and C) and `v_latest_ledger` (the log rows of the most recent transaction).
- I ran the balance audit once before any test, so I had a clean starting point to compare against.
- I wrote `fn_deposit`, `fn_withdraw`, `fn_transfer` and `fn_reverse_transaction` as PL/pgSQL functions, so the balance update, the `transactions` row and the `transaction_logs` rows succeed or fail as one unit. `fn_transfer` and `fn_reverse_transaction` lock the account rows in `account_id` order.

### How I ran the script

pgAdmin 4 runs everything in the editor when no text is highlighted, so I highlighted one numbered block at a time and pressed F5. I ran every block in the same Query Tool tab, because one tab is one database session. A transaction opened with `BEGIN` belongs to that session, so if I had switched tabs between `BEGIN` and `COMMIT`, the statements would not have been part of the same transaction. Staying in one tab let me stop between steps, run a `SELECT` inside the open transaction to see the uncommitted change, and then finish with `COMMIT` or `ROLLBACK`.

### COMMIT

I opened a transaction with `BEGIN`, deposited `5000` into account A, wrote the `transactions` row and the credit log, and ended with `COMMIT`. Account A moved from `69700.00` to `74700.00`. Accounts B and C stayed at `200300.00` and `362100.00`, and the stored balance matched the log balance on all three accounts (difference `0.00`).

![Balances for accounts A, B and C after the committed deposit](screenshots/pgadmin-commit-after.png)

*After `COMMIT`, account A holds `74700.00` and every difference is `0.00`.*

### ROLLBACK

I repeated the same `5000` deposit but ended the transaction with `ROLLBACK`. Inside the open transaction, the balance check showed the deposit. After `ROLLBACK`, account A went back to `74700.00` and the deposit's `transactions` row and log row were gone, so the change never became permanent.

![Balances for accounts A, B and C after the rolled-back deposit](screenshots/pgadmin-rollback-after.png)

*After `ROLLBACK`, account A is back at `74700.00`.*

### Constraint failure

I opened a transaction, credited account B with `1000`, and then tried to debit account A by `1` naira more than its balance. The `ck_accounts_balance` constraint rejected the debit, and PostgreSQL refused every further statement until I ran `ROLLBACK`. The rollback also removed the earlier credit to account B, so B returned to `200300.00`. This showed me that one failed step cancels the whole transaction, not just the step that failed.

![ck_accounts_balance error on account A and the rollback undoing the credit to account B](screenshots/pgadmin-constraint-rollback.png)

*The ck_accounts_balance constraint error on account A aborting the open transaction.*

### Atomic functions

I tested each function with a success case and a failure case:

- `fn_deposit` added `10000` to account A.
- `fn_withdraw` took `2500` from account B.
- `fn_withdraw` refused a withdrawal of `1` naira more than account C holds.
- `fn_transfer` moved `15000` from account A to account B.
- `fn_transfer` refused a transfer of `1` naira more than account C holds.
- `fn_reverse_transaction` reversed the transfer, and a second reversal of the same transfer was refused because only `successful` transactions can be reversed.

After both refusals, account C was unchanged at `362100.00`, so a refused operation left no half-finished change behind.

The transfer was transaction `20005` (`VGP2026102790000005`) for `15000.00`. Its ledger after the reversal looked like this:

| log_id | account_id | entry_type | balance_after |
|---|---|---|---|
| `27714` | `1` | `debit` | `69700.00` |
| `27715` | `2` | `credit` | `212800.00` |
| `27716` | `2` | `debit` | `197800.00` |
| `27717` | `1` | `credit` | `84700.00` |

The first two rows are the original transfer (account A debited, account B credited). The last two rows are the reversal, which puts the `15000.00` back: account B is debited down to `197800.00` and account A is credited back up to `84700.00`. The transaction status is now `reversed`, and the original log rows stay in place, so the audit trail keeps both the transfer and its reversal.

![Ledger rows for the transfer after fn_transfer and fn_reverse_transaction](screenshots/pgadmin-fn-transfer-and-reverse.png)

*The four ledger rows for transaction `20005`: the transfer legs and the reversal legs.*

The transfer got `transaction_id` `20005` and `log_id` `27714` to `27717` even though the rolled-back deposit never became permanent. PostgreSQL does not give identity numbers back when a transaction rolls back, so the rolled-back deposit still used up an id, and gaps in the numbering are normal.

### Final audit

After all the Stage 1 tests, account A held `84700.00`, account B held `197800.00` and account C held `362100.00`, with a difference of `0.00` on each. Across the whole database, the balance audit checked `800` accounts and found `0` out of balance.

![Final Stage 1 balances for accounts A, B and C and the balance audit count](screenshots/pgadmin-stage1-audit.png)

*Final Stage 1 balances for accounts A, B and C showing zero variance between stored and ledger balances.*

### Results

- `COMMIT` made the deposit permanent, and `ROLLBACK` removed it completely, including its `transactions` row and log row.
- A constraint failure in the middle of a transaction cancelled the whole transaction, including the earlier credit to account B.
- Each function wrote the balance change, the `transactions` row and the log rows as one unit, and the refused operations changed nothing.
- The reversal restored accounts A and B to their earlier balances and kept both the transfer and the reversal in the ledger.
- Stored balances still equalled the sum of the logs on every account after all of these tests.


## Stage 2: Concurrency and Locking (`concurrency_locking.sql`)
 
### How I tested two sessions
 
I opened two Query Tool tabs in pgAdmin 4 on the same database, which I call Tab 1 and Tab 2. Each tab is its own session, so I could play two customers acting at the same moment. To make the overlap repeatable, I wrote my demo functions with a `pg_sleep(30)` pause between reading a balance and writing it. I started the call in Tab 1, switched to Tab 2 straight away, and started the matching call there while Tab 1 was still paused.
 
### What I built
 
- I created `test_checkpoint`, `fn_take_test_checkpoint()` and `fn_reset_to_checkpoint()`. The checkpoint saves the balances of accounts A, B and C and the latest `transaction_id` and `log_id`. The reset deletes only the rows created after the checkpoint and restores those three balances, so I could undo a test that deliberately damages the data. I only used it on my three test accounts.
- I created the view `v_test_activity`, which lists the ledger rows created since the last checkpoint.
- I wrote `fn_withdraw_no_lock` and `fn_withdraw_locked`. They are identical except that the locked version reads the balance with `SELECT ... FOR UPDATE`.
- I wrote `fn_transfer_demo`, which locks the first account, pauses, and then locks the second account. Its `p_ordered` flag decides whether it locks the source first or the lower `account_id` first.
### Lost update and double-spend without locking
 
Account C held `362100.00`. In both tabs, I called `fn_withdraw_no_lock` for 60% of C's balance, which is `217260.00` each. Together the two withdrawals ask for 120% of the balance. Both sessions read `362100.00` before either one wrote, so both passed the balance check, and both returned a `transaction_id` with no error.
 
| transaction_id | reference | amount | log_id | account_id | entry_type | balance_after |
|---|---|---|---|---|---|---|
| `20006` | `VGP2026102990000006` | `217260.00` | `27718` | `3` | `debit` | `144840.00` |
| `20007` | `VGP2026102990000007` | `217260.00` | `27719` | `3` | `debit` | `144840.00` |
 
![Two withdrawals of 217260.00 from account C, both with a balance after of 144840.00](screenshots/pgadmin-lost-update-ledger.png)
 
*Both withdrawals ended at the same balance, because the second session overwrote the first.*
 
The balance audit exposed the damage. Account C's stored balance was `144840.00`, but the logs add up to `-72420.00`, a difference of `217260.00`. C paid out `434520.00` against a balance of `362100.00`, and the stored balance hid it. Accounts A and B stayed at `84700.00` and `197800.00` with a difference of `0.00`.
 
![Balance audit showing a difference of 217260.00 on account C](screenshots/pgadmin-lost-update-audit.png)
 
*The audit catches the lost update: account C's stored balance is `217260.00` higher than its ledger.*
 
After taking my screenshots, I ran `fn_reset_to_checkpoint()` to delete both withdrawals and put account C back to `362100.00`, so the screenshots are my evidence for this test.
 
### Fix with SELECT ... FOR UPDATE
 
I ran the same two calls again with `fn_withdraw_locked`. Tab 1 locked account C's row when it read the balance. Tab 2 reached the same row and had to wait.
 
![Tab 2 still running while it waits for the row lock on account C](screenshots/pgadmin-lock-waiting.png)
 
*Tab 2 waiting on the row lock that Tab 1 holds.*
 
When Tab 1 finished, Tab 2 read the new balance and refused the withdrawal:
 
```
ERROR:  Withdrawal of 217260.00 refused: balance is only 144840.00
CONTEXT:  PL/pgSQL function fn_withdraw_locked(bigint,numeric,integer) line 13 at RAISE
SQL state: P0001
```
 
![Row-locking refusal error in Tab 2](screenshots/pgadmin-lock-refused.png)
 
*The second withdrawal is refused because it saw the balance after the first one.*
 
The audit confirmed it. Account C's stored balance and log balance both equal `144840.00` (difference `0.00`), and accounts A and B are unchanged. The lock turned a double-spend into one successful withdrawal and one refusal.
 
![Balance audit after the locked withdrawals showing a difference of 0.00](screenshots/pgadmin-lock-audit.png)
 
*With the lock, account C's stored balance equals its ledger.*
 
### Deadlock
 
I took a new checkpoint and ran `fn_transfer_demo` with `p_ordered` set to `false`. In Tab 1, I transferred `1000` from account A to account B, which locks A first. In Tab 2, I transferred `2000` from account B to account A, which locks B first. After the pause, each tab needed the row the other one held. PostgreSQL detected the cycle and cancelled one transaction:
 
```
ERROR:  deadlock detected
Process 24240 waits for ShareLock on transaction 810; blocked by process 13880.
Process 13880 waits for ShareLock on transaction 811; blocked by process 24240.
SQL state: 40P01
Context: while locking tuple (9,1) in relation "accounts"
SQL statement "SELECT 1 FROM accounts WHERE account_id = v_second FOR UPDATE"
PL/pgSQL function fn_transfer_demo(bigint,bigint,numeric,integer,boolean) line 19 at PERFORM
```
 
![Deadlock detected error from the opposite transfers between accounts A and B](screenshots/pgadmin-deadlock-error.png)
 
*PostgreSQL cancels one of the two opposite transfers with `deadlock detected`.*
 
The `1000` transfer from A to B committed, and the cancelled `2000` transfer from B to A was rolled back completely, so no half-finished transfer was left behind.
 
### Deadlock prevention
 
I took another checkpoint and ran the same opposite transfers with `p_ordered` set to `true`, so both sessions lock the lower `account_id` first. Tab 1 transferred `1500` from A to B and Tab 2 transferred `2500` from B to A. Tab 2 waited for account A, because Tab 1 held it, and carried on once Tab 1 finished. Nothing was cancelled, and both transfers succeeded:
 
| transaction_id | reference | amount | log_id | account_id | entry_type | balance_after |
|---|---|---|---|---|---|---|
| `20011` | `VGP2026102990000011` | `1500.00` | `27724` | `1` | `debit` | `82200.00` |
| `20011` | `VGP2026102990000011` | `1500.00` | `27725` | `2` | `credit` | `200300.00` |
| `20012` | `VGP2026102990000012` | `2500.00` | `27726` | `2` | `debit` | `197800.00` |
| `20012` | `VGP2026102990000012` | `2500.00` | `27727` | `1` | `credit` | `84700.00` |
 
![Both opposite transfers completing without a deadlock when accounts are locked in account_id order](screenshots/pgadmin-deadlock-fixed.png)
 
*With a fixed lock order, both transfers complete and the ledger holds all four rows.*
 
### Final audit
 
After the Stage 2 tests, account A held `84700.00`, account B held `197800.00` and account C held `144840.00`, with a difference of `0.00` on each. Account C is lower than at the end of Stage 1 because the locked withdrawal of `217260.00` was a valid transaction that stayed. The balance audit checked `800` accounts and found `0` out of balance.
 
### Results
 
- Without a lock, two sessions that read the same balance both passed the balance check, and the second write overwrote the first. The audit showed a difference of `217260.00` on account C.
- `SELECT ... FOR UPDATE` made the second session wait, re-read the new balance and refuse the withdrawal. Stored balance and ledger matched.
- Opposite transfers that lock accounts in different orders caused a deadlock, and PostgreSQL cancelled one of them with SQL state `40P01`.
- Locking the lower `account_id` first removed the deadlock, and both transfers completed.
- Every balance matched its ledger after the fixes, and the audit found `0` of `800` accounts out of balance.
