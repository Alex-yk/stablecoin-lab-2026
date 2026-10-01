# EXERCISES.md — the hands-on list

This file is **what you have to write**. The README tells you what the lab is; this tells you what to do.

Every exercise has one command that answers "am I done?". Red means not done, green means done.
The tests under `test/exercises/` are **deliberately red** — that is not a bug report, that is your task.

---

## Overview

| # | What you will do | Acceptance command | Where to look if stuck |
|---|---|---|---|
| Ex0 | Set up the environment, get the core tests passing | `make test` (7 green) | `README.md` "1. Setup" |
| Ex1 | Walk the mint/redeem loop once on the command line | `make mint` then `make balance` | `README.md` "2. Quick start", the Ex1 commands below |
| Ex2 | Catch the 6-vs-18-decimal trap in a test | the two `Ex2` tests under `01_*` in `make exercise` | the Ex2 "hint" below, `test/exercises/01_LoopTasks.t.sol` |
| Ex3 | Break a stablecoin's peg with your own hands | a screenshot of `supply >> collateral` | the four Ex3 commands below |
| Ex4 | Write tests for permissions and pausing | the five `Ex4` tests under `01_*` | `STUDENT-QUESTIONS.md` A1/B1, `test/exercises/01_LoopTasks.t.sol` |
| Ex5 | Implement the over-collateralized vault and liquidation | all of `03_*` green | `src/exercises/OverCollateralizedVault.sol`, the decimals table below |
| Ex6 | Write invariant tests (the machine calls things at random and hunts for a counterexample) | all of `02_*` green | `test/exercises/02_InvariantTasks.t.sol`, the Ex6 "hint" below |
| Ex7 | Make a real vault stop serving | `make challenge` (**red** until you solve it) | `test/challenges/Unstoppable.t.sol` |

The deck has three reference pages worth keeping open:
P18 decimals, P25 the invariant handler, P27 if you are stuck look here.

---

## Ex0 · Environment

```bash
make doctor    # 30 seconds: is this machine ready? anything ✗ comes with its own fix
make test      # acceptance: 7 passed
```

`lib/` (forge-std + OpenZeppelin v5.0.2) **ships inside this repository** — a plain
`git clone` compiles as-is. There is nothing to install, and you do not need `make setup`
unless `lib/` is somehow empty (then `git checkout -- lib` restores it).

Installing Foundry on your own machine is the one step that can fail on a mainland
network; the Setup section of `README.md` covers the `gh-proxy.com` mirror, and
Track B (Codespaces) installs nothing locally.

---

## Ex1 · Walk the loop once

```bash
make anvil                  # terminal A, leave it running
make deploy-anvil           # terminal B
export VAULT=... SUSD=... USDC=...   # the three addresses deploy printed
make mint AMOUNT=1000000000
make balance TO=<your address>
```

Look at three numbers: `totalSupply()`, `totalCollateral()`, `balanceOf(you)`.
**They must be equal.** That is the whole secret of the system.

---

## Ex2 · The decimals trap

Open `test/exercises/01_LoopTasks.t.sol` and write two tests:

1. `test_Ex2_DepositIncreasesSupplyByExactly` — for any legitimate amount x,
   the supply must increase by exactly x after `deposit(x)`.
2. `test_Ex2_DecimalsTrap` — run it with `1000e18` (instead of `1000e6`) and assert what you observe.

The second one has no expected answer. Run it, read the numbers carefully, then ask yourself one question:

> This operation **did not revert**, and the invariant **still holds**.
> So what exactly went wrong?

> Hint: `MockUSDC` has 6 decimals. `1000e18` units is **10^15** coins,
> not 1000 — off by a factor of 10^12. 18-decimal intuition does not transfer to a 6-decimal coin.

---

## Ex3 · Break the peg by hand (command line, no tests)

```bash
# 1. The attacker (no MINTER_ROLE) mints for themselves -- this must fail
cast send $SUSD "mint(address,uint256)" $ATTACKER 1000000000000 \
  --rpc-url $RPC --private-key $ATTACK_KEY

# 2. Now grant MINTER_ROLE to the attacker (simulating a leaked key / insider / bribe)
cast send $SUSD "grantRole(bytes32,address)" \
  $(cast keccak "MINTER_ROLE") $ATTACKER --rpc-url $RPC --private-key $ANVIL_KEY

# 3. Mint again -- this time it succeeds
# 4. Read totalSupply() and totalCollateral(), screenshot both numbers
```

Deliverable: one screenshot where `totalSupply()` is far greater than `totalCollateral()`.
**That is a depeg.** Not a line of code changed, and the peg is gone.

---

## Ex4 · Permissions and pausing

Same file, `01_LoopTasks.t.sol`, five tests:

| Function | What you are proving |
|---|---|
| `test_Ex4_Mint_RevertsForNonMinter` | no MINTER_ROLE, no minting |
| `test_Ex4_Pause_BlocksTransfers` | a transfer reverts after `pause()` |
| `test_Ex4_Pause_BlocksRedeem` | **redemption is frozen along with everything else** |
| `test_Ex4_AttackerCannotBurnOthersBalance` | an attacker cannot touch someone else's balance |
| `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance` | **but the vault can** |

The last one is not there to justify it, it is there to **prove the backdoor really exists**.
It maps to A1 in `STUDENT-QUESTIONS.md` — think it through, then go back and answer A1.

The third one maps to B1/B2: if you wanted "freeze transfers but allow redemption", how would you change it?

---

## Ex5 · Over-collateralization + liquidation

Open `src/exercises/OverCollateralizedVault.sol` and fill in the four TODOs:

| TODO | What to do | The hard part |
|---|---|---|
| Ex5.1 `collateralValue` | turn collateral into a value in sUSD | 18 decimals × 8 decimals -> 6 decimals: divide by 10 to what power? |
| Ex5.2 `mintStable` | the ratio after minting must not fall below 150% | record first, or check first? |
| Ex5.3 `redeemCollateral` | the ratio after withdrawing must not fall below 150% | as above |
| Ex5.4 `liquidate` | below 120% anyone may liquidate | the bonus can exceed the collateral that is left |

Acceptance:

```bash
make exercise   # just the 03_* group
```

Three decimal counts you must keep apart — this is the sequel to Ex2:

```
collateral mWETH   18 decimals
stablecoin sUSD     6 decimals
price feed          8 decimals   ->   18 + 8 - 6 = 20
```

About Ex5.4, one question to think through:

> When the price falls hard enough, "debt value × 110%" can be more than the collateral the user
> deposited. Who eats the shortfall? Why can't real lending protocols escape this either?

---

## Ex6 · Invariant testing

Open `test/exercises/02_InvariantTasks.t.sol`.

Every test so far has been "I set up a situation and check the result".
Invariant testing flips that around: **let the machine call a pile of operations at random and in
sequence**, then ask "no matter how it thrashes, has this property been broken?"

Three things to do:

1. Implement the handler's `redeem` (the parameters have no names yet — name them first)
2. Turn `invariant_CollateralBacksSupply` into the property you actually want to defend
3. Do the same for `invariant_VaultHoldsNoStablecoin`

```bash
make exercise   # just the 02_* group
```

When an assertion fails, Foundry prints the **counterexample call sequence** — walk that sequence by
hand and you will see exactly at which step, and with which arguments, the invariant broke. This is
the closest thing in the lab to a real security audit.

> Hint: why must `invariant_VaultHoldsNoStablecoin` hold?
> The vault only ever mints sUSD to users and should keep none for itself. If it did hold sUSD,
> what would that mean?

---

## Ex7 · Make a real vault stop serving

```bash
make challenge     # should be red right now -- that is the puzzle, not a bug
```

The material is in `test/challenges/Unstoppable.t.sol`, ported from Damn Vulnerable DeFi v4.
You are holding 10 DVT, and the goal is to make the vault **stop offering flash loans**.

The only function you need to change is `test_unstoppable()`. The hint is already in there:

> What assumption does the vault make about its own balance?

---

## Deliverables

The homework requirements, grading weights and how to submit are in the "4. Homework" and
"6. Submission" sections of `README.md`.
The discussion questions are in `STUDENT-QUESTIONS.md`.
