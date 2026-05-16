# Bill Splitting Instructions

## Overview
I have two rentors, **J** and **R**, who each pay a portion of the monthly utility bills. Given a list of bills, calculate what each rentor owes and the optimal date for them to send a single combined payment.

---

## Rentor Payment Splits

| Bill Type | Rentor J | Rentor R |
|-----------|----------|----------|
| Electric  | 35%      | 35%      |
| Gas       | 35%      | 35%      |
| Internet  | —        | 50%      |

> Note: J does not contribute to the internet bill.

---

## Bill Input Format
Bills will be provided in this format:
```
Bill Name, Amount, Due Date (YYYY/MM/DD)
```

Example:
```
Gas bill Crown Crest, $47.60, 2026/04/01
Gas bill Enbridge, $154, 2026/04/27
Electric bill Alectra, $212.95, 2026/04/20
Internet bill, $184.19, 2026/04/23
```

---

## Calculation Rules

### 1. Merge gas bills
If there are multiple gas bills, combine them into one total first, then calculate each rentor's 35% share from the combined amount.

### 2. Weighted average due date (per bill type)
If a bill type has multiple entries (e.g. two gas bills), calculate a **weighted average due date** based on each bill's amount before calculating the rentor share.

Formula:
```
Blended due date = Σ(amount × days_since_epoch) / Σ(amount)
```

### 3. Single payment date per rentor
Each rentor sends **one combined payment**. Calculate a **weighted average due date** across all bills they contribute to, weighted by the amount they owe on each bill.

### 4. Buffer
Apply a **3-day buffer** before the weighted average due date to get the final "send by" date.

---

## Output Format

### 1. Summary cards
Show each rentor's total owing and their "send by" date.

### 2. Bill breakdown table
Columns: Bill | Total | J owes | R owes | Blended due date

### 3. Text messages
Generate a ready-to-send text message for each rentor in this format:

> Hello [Rentor], the electric bill is [amount], the gas bill is [amount], and the internet bill is [amount]. Please send your payment by [send by date]. Thank you!

- Omit any bill the rentor does not contribute to.
- Do **not** include totals in the text message.

---

## Notes
- Flag any bills whose due date has already passed as **overdue**.
- Both rentors may land on the same send-by date — this is expected and convenient.
- The remaining portion of any bill not covered by J or R (e.g. 30% of internet) is assumed to be the landlord's share and is not calculated.
