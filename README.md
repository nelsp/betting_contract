# betting_contract

A two-party ETH bet with an optional arbiter, plus **Bet Desk**, a web page for creating and settling bets.

- `revised_bet.sol`: the `Bet` contract and `BetFactory`
- `docs/`: Bet Desk (served by GitHub Pages at https://nelsp.github.io/betting_contract/)

## Using Bet Desk
1. Install MetaMask, switch it to the **Sepolia** test network, and get Sepolia ETH from a faucet.
2. Open the page, connect MetaMask, and paste a deployed **BetFactory** address.
3. Create a bet, then send the other player the link from **Copy share link**. It includes the terms so they can verify them against the on-chain hash before depositing.

## Running it locally
MetaMask does not work on `file://` pages, so serve the folder over http:

```
powershell -ExecutionPolicy Bypass -File docs\serve.ps1
```

Then open http://localhost:8000.
