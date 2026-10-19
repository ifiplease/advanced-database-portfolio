# MIT 8103 Advanced Database Systems Portfolio

**Student:** Anjolaoluwa Adegbite
**Programme:** Master of Information Technology (2026/2027 Academic Session)
**Database system:** PostgreSQL (managed with pgAdmin 4)

---

## Selected Case Study: VanguardPay

### Organisation / Scenario

VanguardPay is a simulated fintech company based in Nigeria.

### Nature of the Business / System

VanguardPay is a digital banking and payments platform. Customers sign up through a mobile app or website, open accounts, and move money without visiting a physical branch. The platform lets customers hold balances, send money to other accounts, deposit and withdraw funds, and view their transaction history. Because VanguardPay handles real money, the database must be accurate, secure, and fully auditable. Every naira that moves must be recorded and traceable.

### Users of the Database

- **Customers:** use the app to check balances, make transfers, and view statements.
- **Customer support agents:** look up customer accounts and transactions to resolve complaints.
- **Compliance and audit officers:** review transaction logs and check that account balances are correct.
- **Fraud analysts:** monitor transactions and login activity for suspicious behaviour.
- **Database administrators:** manage the database, backups, performance, and access control.
- **The VanguardPay application backend:** reads and writes data automatically on behalf of customers.

### Major Data to be Stored

**Core Relational Data (PostgreSQL, Portfolios 1, 2, 3 and 5):**

- **Customers:** personal details, contact information, and identity verification (KYC) status.
- **Accounts:** account numbers, account types (e.g. savings, current), balances, currency, and account status.
- **Transactions:** transfers, deposits, and withdrawals, with amounts, timestamps, and status (pending, successful, failed, reversed).
- **Transaction logs:** a permanent audit record of every change to money in the system.
- **Beneficiaries:** saved recipients that customers send money to often.

**Unstructured / Semi-Structured Data (NoSQL, Portfolio 4):**

- **Login sessions and device activity:** records of when and from where customers access the platform.
- **Fraud alerts:** flagged events that need review.

### Key Operations the Database Will Support

1. **Register a customer and open an account.**
2. **Deposit funds** into an account.
3. **Withdraw funds** from an account, blocking the request if the balance is too low.
4. **Transfer funds** between two accounts safely, so that money is never lost or duplicated.
5. **Reverse failed transactions** and put the money back correctly.
6. **Audit account balances** by comparing stored balances against the transaction history.
7. **Generate account statements** for a chosen customer and date range.
8. **Detect and flag suspicious activity**, such as unusually large or very frequent transfers.

### How This Case Study Is Used Across the Portfolio

| Portfolio | How VanguardPay is used |
|---|---|
| 1. Database Design and Modelling | ER diagram and relational schema for customers, accounts, and transactions |
| 2. Query Processing and Optimisation | Queries on statements, balances, and transaction history, with indexing |
| 3. Transactions and Concurrency | Fund transfers with commit, rollback, and concurrent access to the same account |
| 4. NoSQL and Advanced Data Models | Login sessions and fraud alerts stored as flexible documents |
| 5. Distributed and Cloud Database | Replication, availability, and consistency for a platform that must stay online |

---

## AI Use Declaration

*(To be completed in the final documentation.)*
