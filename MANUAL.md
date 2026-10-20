# Bet Desk: instruction manual

How to create a bet, fund it, settle it, and collect the winnings using Bet Desk on the Sepolia test network.

## Roles

| Role | What they do |
|---|---|
| **Bettor** | One side of the bet. Usually proposes it. |
| **Taker** | The other side. |
| **Arbiter** (optional) | A trusted third party who declares the winner if the loser won't concede. Can't be either player and never holds the money. |

## Before you start (every participant)

1. Install **MetaMask** in your browser and create or import an account.
2. Turn on test networks (**Settings → Advanced → Show test networks**) and select **Sepolia**.
3. Get free Sepolia ETH from a faucet. You need enough for your stake plus a little for gas fees.
4. Open Bet Desk: **https://nelsp.github.io/betting_contract/**
5. Click **Connect MetaMask**. If you have several accounts, click **Change account** and tick the one you're using for this bet.

## 1. Agree on the bet

Before anything goes on-chain, the bettor and taker agree on:

- **Terms**: one exact sentence stating what is being bet on, which data source decides it, the date and timezone, and who wins in each case. Example:
  > S&P 500 index official closing price on 2026-10-01 is below 7200.00 per S&P Dow Jones Indices; bettor wins if true, taker wins if false
- **Stakes**: how much each side puts in. Different amounts set the odds.
- **Arbiter**: an address, or none.
- **Dates**: when funding closes, the event date, and the resolution deadline.

## 2. Create the bet (bettor or taker)

1. Paste the **BetFactory address** at the top of the page and click **Use this factory**.
2. On the **Create bet** tab, fill in:
   - **Bettor / Taker**: wallet addresses. Click **Me** to insert your own.
   - **Arbiter**: an address, or leave it blank for none.
   - **Stakes**: in ETH.
   - **Terms**: paste the exact agreed text. Every character counts.
   - **Funding closes**: the last moment both deposits can be made.
   - **Event date**: when the outcome is known. The arbiter can rule from this point on.
   - **Resolution deadline**: at least 1 hour after the event date. If the bet is still unsettled after this, it can be expired and both stakes refunded.
3. Click **Create bet** and confirm in MetaMask. The new bet opens in **Bet details**.
4. Click **Copy share link** and send it to the other player (and the arbiter). The link includes the terms so they can verify them.

## 3. Fund the bet (both players, before funding closes)

1. Open the share link, or paste the bet address into **Bet details**.
2. Paste the agreed terms into the **Terms** box and check it says **✓ Matches the on-chain hash**. Don't deposit if it doesn't match.
3. Click **Deposit** and confirm. The page sends your exact stake automatically.

When both deposits are in, the bet changes to **Active**.

> **If the other player never deposits**: once you've deposited you can click **Cancel & refund** at any time while the bet is still funding. After the funding deadline anyone can cancel. Then go to step 5 to collect your refund.

## 4. Settle the bet (after the outcome is known)

Exactly one of these happens:

| Situation | Who acts | Button |
|---|---|---|
| The loser accepts the result | **Loser** | **Concede**. Gives the whole pot to the other player. Final. |
| The loser won't concede | **Arbiter**, on or after the event date | **Rule winner**: pick Bettor or Taker. Final. |
| Nobody settles it by the resolution deadline | **Anyone** | **Expire & refund both**. Each player gets their own stake back. |

Settling doesn't move any money yet. It only records who is owed what.

## 5. Collect your money (winner, or each player after a refund)

1. Open the bet in **Bet details** while connected as the account that is owed money.
2. Click **Withdraw** and confirm. The ETH arrives in your wallet.

There's no deadline to withdraw. Your balance stays in the contract until you collect it.

## Quick reference: bet states

| State | Meaning | What can happen next |
|---|---|---|
| **Funding** | Waiting for deposits | Deposit, Cancel |
| **Active** | Both stakes locked in | Concede, Rule winner, Expire |
| **Resolved** | Winner decided | Winner withdraws |
| **Cancelled** | Not fully funded | Depositors withdraw refunds |
| **Expired** | Never settled | Both players withdraw refunds |

## Troubleshooting

| Problem | Fix |
|---|---|
| A button is greyed out | Read the note next to it. It says exactly why (wrong account, wrong state, too early, and so on). |
| Page doesn't recognise your account | Click **Change account** and tick the right account. MetaMask only shares accounts you've connected to the site. |
| "Wrong network" | Switch MetaMask to **Sepolia**. |
| "No contract at that address" / "not a BetFactory" | Check the address. The factory and each bet have different addresses. |
| Terms don't match the hash | The text differs from what was used at creation, even by a space or capital letter. Get the exact text from the creator. |
| Wallet balance didn't change after settling | Expected. Money only moves on **Deposit** and **Withdraw**. |

*This runs on the Sepolia test network with test ETH, which has no real value.*
