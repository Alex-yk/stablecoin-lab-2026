# STUDENT-QUESTIONS.md — Discussion questions (submit with your repo)

Answer directly under each question. 150–300 words each — **reasoning over length**.

---

## A. Permission design

**A1.** The vault holds `MINTER_ROLE`, so it can `burn` any user's balance. Explain why that is a risk, then write out how you would change `Vault` and `SimpleStablecoin` to remove it.

> Your answer: The function `burn` only verifies whether the caller has `MINTER_ROLE`. It does not require the token holder's approval, so an address with this role can burn any other user's sUSD without authorization. For example, if a privileged caller burn 100 of Alice's sUSD, the total supply falls from 1,000 to 900, while the vault's total collateral remains unchanged and Alice receives no collateral in return. The collateral invariant still holds, but Alice has lost part of her balance. This shows that sufficient collateral alone does not protect users from misuse of privileged permissions. If an attacker gains `MINTER_ROLE`, they could destroy users' balances without compensation, causing financial losses and undermining trust in the system.

> In `SimpleStablecoin`, I would replace the unrestricted privileged `burn` function with `burnFrom`, which requires both `MINTER_ROLE` and sufficient approvement from the token holder. It would check and spend that allowance before burning the tokens. In `Vault`, I would update `redeem` to call this new `burnFrom(msg.sender, amount)` before returning collateral. Users would be required to first approve the vault to spend their sUSD.

```
SimpleStablecoin.sol
function burnFrom(address from, uint256 amount) external onlyRole(MINTER_ROLE){
    ...

    _spendAllowance(from, msg.sender, amount);
    _burn(from, amount);
}
```


<br><br><br>

**A2.** In this contract `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` all go to the same address. How would you split them in production, and who holds each?

> Your answer: All three roles go to the same address may cause single point of failure. if its private key is compromised, an attacker could control role assignment, mint or burn tokens, and pause the system. 

> `DEFAULT_ADMIN_ROLE` can grant and revoke roles. It should be the most privilege role even though it does not has the permission to mint tokens, but it can grant `MINTER_ROLE` to itself. Therefore, this role should be held by a governance multisignature wallet, requiring approval from multiple independent signers. Important role changes should also pass a timelock, giving the admin users time to detect and respond to suspicious changes.

> `MINTER_ROLE` can mint and burn tokens. It should only be granted to the `vault`, which is reponsible for deposits and redemptions. This ensures that normal minting follows the collateral-backed deposit process. And the depolyer's minting permission should be revoked after the deployment.

> `PAUSER_ROLE` can pause or unpause the system and revert the redemption. This role should be held by an security group independently and required multiple approval from team members before important action has been made. This team should be able to pause immediately when an attack is detected. While unpausing should require more strict procedure after fixing all the potential risk holes. But this authority should not be abuse in case stopping users from doing redemption regularly.

<br><br><br>

---

## B. Pausing and redemption

**B1.** `_update` is the single entry point for every balance change, so `pause()` freezes transfers, minting and redemption together. If you wanted "pause transfers but **allow redemption**", how would you change it? Give the approach — full code not required.

> Your answer: I would seperating each situation using `from` and `to` address passed to `_update`. Minting uses the zero address as `from`, while burning uses the zero address as `to`. During redemption, the vault bruns the holder's sUSD directly instead of transfering the token to the vault.

|Action|`from`|`to`|
|---|---|---|
|Transfer|sender|receiver|
|Mint|address(0)|receiver|
|Redeem|token holder|address(0)|


> I would change the original function based on the difference of `to` address since only redemption's `to` address is `address(0)`. Therefore, remove the `whenNotPaused` and replace it with a conditional check. When paused, operations with a nonzero `to` address would revert (both transfer and minting). Burning would remain allow because its `to` address is zero.

```
function _update(address from, address to, uint256 value)
    internal
    override(ERC20)
    {
        if (paused() && to != address(0)){
            // pause transfer and mint
        }
        super._update(from, to, value);
    }
```

<br><br><br>

**B2.** In 2008, when a money-market fund "broke the buck", redemptions were frozen for days. In 2023 USDC depegged to $0.87 after a reserve bank failed, but redemptions were **not** shut. Compare the two responses — what does closing the redemption channel, or leaving it open, do to a stablecoin?

> Your answer: In the 2008 case, freezing redemptions could slow down the cash flow out and give the market fund more time to arrange liquidity, potentially avoiding forced asset sales ath distressed prices. However, stopping users from withdrawing could increase uncertainty and undermine confidence. Investors unable to redeem might trade with lower prices in the secondary market, and further deepening the discount.

> In the USDC case, keeping the redemption channel open could support the peg through arbitrage. For example, if investors can buy a token at the price of $0.87 and reliably redeem it for $1, they would have an incentive to buy discounted tokens. This buying demand could help the market price back toward $1. However, reliable redemption depends on enough settlement， and the public confidence in the accessibility and safty of reserves also mattered.

> The disadvantage of keeping redemptions available is that the issuer must have both sufficient reserves and enough liquidity to satisfy redeem. If reserves are insufficient, early redeemers may get all their money back while later holders bear the losses. Therefore, an open redemption channel supports stability only when the promise of repayment is credible and operationally achievable.

<br><br><br>

---

## C. Depeg analysis

**C1.** Under what conditions does this coin depeg? Distinguish at least two classes of cause, and say how each one shows up in the invariant `totalCollateral() >= totalSupply()`.

> Your answer: 1. One cause of depegging is unauthorized minting. An attacker may gains a `MINTER_ROLE` and mints tokens without depositing collateral. Supply would increase and the total collateral remains unchanged, so **the invariant could fail**. Since the collateral is lower than total supply, not all users can redeem at full value, and that can weaken confidence and cause the market price to fall.

> 2.A second cause is the loss of access to redemption. If the issuer pauses the system, users can not transfer or redeem at all. In this case, collateral and supply remain unchanged, so the **invariant still holds**. But all the users cannot exchange sUSD for collateral and arbitrages become unavailable. Uncertainty about when redemption will resume may further undermine confidence.

> These cases show that the invariant only check whether collateral covers the total supply, it does not guarantee that holders can get their reserves. Therefore, the invariant can remain valid even when depegging.

<br><br><br>

**C2.** Suppose an attacker bribes their way to `MINTER_ROLE`, mints 1,000,000 sUSD out of nothing and redeems it all. Describe the flow of funds, and name the step that could have stopped them.

> Your answer: Assume the vault initially holds 2,000,000 mUSDC, backing a total supply of 2,000,000 sUSD. After unauthorized minting by the attacker, total supply raises to 3,000,000 sUSD while collateral remains unchanged. After the attacker redeems all newly minted tokens, the remaining 2,000,000 sUSD is now backed by only 1,000,000 mUSDC in the vault, leaving other legitimate holders exposed to a reserve shorfall.

> The earliest prevention step is process to grant a `MINTER_ROLE`. Minting should be restricted to the vault, and role changes should be protected by multisignature governance and a timelock. Once the attacker gains the role, `onlyRole(MINTER_ROLE)` will accept their mint call.

> A second intervention step is checking the invariant before redemption and reverting the transaction if collateral is below total supply. Although this step can prevent dangerous withdrawal, it would also block legitimate users from redeeming.

<br><br><br>

---

## D. Toward RWA

**D1.** Right now the collateral is `MockUSDC` and `totalCollateral()` just reads an on-chain balance — simple and reliable. If the collateral were **US Treasuries**, could this invariant still be written that way? What new problems appear?

> Your answer: If the collateral consisted of US Treasuries, an on-chain balance alone would no longer be sufficient to demonstrate full backing. Treasuries are securities held through off-chain custody arrangements. Token representing claims on those securities could be placed in the vault, but counting the tokens would not establish the value or availability of the underlying reserves.

 > Although Treasuries are expected to repay their face value at maturity, their market price may fluctuate before maturity as interest rates change. Therefore a balance-based check could miss this shortfall. The invariant should introducce reliablely assessed value of reserves, including appropriate treatment of accrued interest.

> Data reliability should be accounted for. Smart contract depends on off-chain oracles, stale price or inaccurate data could make an apparently healthy invariant misleading. 

> Custody and legal ownership also matter. The system must claim clearly whether token holders own the securities and whether the assets are protected if the custodian becomes insolvent. Finally, market hour and settlement delays may prevent immediate redemption even when reserves are sufficient.

<br><br><br>

**D2.** If the collateral were **a building**, how would you put it inside this vault? Which off-chain roles or legal structures would you have to introduce?

> Your answer: A building is a real-world asset and cannot be put into the vault directly. I would introduce a SPV, which is a legal entity, to own the building and issue tokens representing rights to the building. These might represent shares in the SPV or rights to rental income, but the distincution must be clearly defined before tokenization. The vault would hold these tokens as collateral and  issues sUSD according to the assessed value.

> I would introduce several off-chain roles:
1) Introduce **SPV** to hold legal ownership of the building.
2) Introduce **independent appraiser** to estimate the building's value.
3) Introduce  **property manager** to handle tenants, rent, maintenance and operating expenses.
4) Introduce **security agent** to protect and enforce token holders' claims, particularly after default.
5) Introduce **oracle** to monitor the supply valuation and reserve infromation to the contract.

<br><br><br>

---

## E. Tests (Tier 1 required — this is Ex4)

Turn the red tests green in `test/exercises/01_LoopTasks.t.sol` to cover the scenarios below, and write your test function names here:

| Scenario | Your test function name |
|---|---|
| Minting by a non-minter reverts | test_Ex4_Mint_RevertsForNonMinter |
| Transfers revert while paused | test_Ex4_Pause_BlocksTransfers |
| **Redemption** reverts while paused | test_Ex4_Pause_BlocksRedeem |
| An attacker cannot burn someone else's balance | test_Ex4_AttackerCannotBurnOthersBalance |
| ...but the vault holding `MINTER_ROLE` can | test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance |

That last pair is meant to be read together: the guard is written correctly, but the key was handed to the vault. Keep it in mind when you answer A1.

Now write one more scenario you consider **most likely to be attacked**, and say why you picked it:

> Your answer: An attacker obtains `MINTER_ROLE`, mints unbacked sUSD, and redeems it to withdraw existing collateral just like the case described in C2. I choose this scenario because minting authority is an attractive attack target: abusing it can mint tokens without any collateral and turn the tokens into real reserve assets. This may lead to the violation of the invariant `totalCollateral() >= totalSupply()`, leaving token holders exposed to financial loosses and unvermining confidence in the system. The highlights the importance of protecting role assignments and restricting minting to the intended collateral-backed process.