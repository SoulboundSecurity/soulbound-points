# SoulBound Points (SBP)

A minimal, MIT-licensed ERC-20 reward points token with **cryptographically
enforced proof-of-protocol-usage** on every mint. No admin mint. No airdrop
function. No batch grant. Every token in circulation is the direct
consequence of a user holding a valid identity token, advancing an on-chain
activity nonce, and claiming against a signed cumulative balance.

Originally designed for the [SoulBound Finance](https://soulbound.finance)
privacy-preserving transfer platform, but drop-in usable against any SBT-like
identity contract that exposes an activity nonce.

## Reference implementation

A canonical, **immutable** deployment of this exact contract is live on
Arbitrum One:

| Network | Address |
|---------|---------|
| Arbitrum One | [`0x559677B6F22f5Ab32D8a185836be25Deb725B274`](https://arbiscan.io/address/0x559677B6F22f5Ab32D8a185836be25Deb725B274) |

No proxy, no upgrade path, no initializer — the deployed bytecode is final
and corresponds to the source in this repo. The Arbiscan page exposes the
verified source and the constructor arguments; anyone can reproduce the
bytecode from this repo and confirm byte-equality against the on-chain
runtime.

Treat this deployment as the reference interpretation of the design. Fork
the repo for your own chain/SBT pairing, but consult the reference address
when you need to confirm real-world behavior on an EIP-712 claim flow.

---

## Contents

- [What this is](#what-this-is)
- [What this is not](#what-this-is-not)
- [Why it matters — the four guarantees](#why-it-matters--the-four-guarantees)
- [How it works — claim mechanics](#how-it-works--claim-mechanics)
- [Security features](#security-features)
- [Key separation and role model](#key-separation-and-role-model)
- [Integration — backend signer](#integration--backend-signer)
- [Integration — user-facing claim](#integration--user-facing-claim)
- [Deployment](#deployment)
- [Verification](#verification)
- [Audit surface](#audit-surface)

---

## What this is

`SoulBoundPoints` is a custom ERC-20 implementation with one extra non-ERC-20
function: `claimPoints(user, cumulativeAmount, sbtNonce, deadline, signature)`.

Claiming is the **only** mint path. Every call to `claimPoints` requires:

1. A valid EIP-712 signature from the currently-authorized `minter` address
2. The `user` must currently hold a token in the SBT (identity) contract
3. The user's SBT activity nonce must be **strictly greater** than the nonce
   at which they last claimed — proof they have done *something* on the
   underlying protocol since their prior claim
4. The claim must not be expired (`deadline`)
5. The `cumulativeAmount` must be greater than the user's previously claimed
   total (the contract mints the delta, not the argument)

Once minted, SBP is a standard ERC-20: `transfer`, `approve`, `transferFrom`,
full compatibility with DEX aggregators, wallets, portfolio trackers, and any
ERC-20 integration. There are **no transfer restrictions** of any kind on
post-claim balances. The "soulbound" in the name refers to the claim gate,
not the post-claim token behavior.

## What this is not

SBP is **not**:

- A security, investment contract, or financial instrument
- A governance token (no voting, no proposals, no treasury authority)
- A revenue share or equity claim on any entity
- A freezable / clawbackable token — the issuer cannot take points back
  or block a user's balance
- A burnable token — once minted, supply only grows
- An admin-mintable token — there is **no code path that mints SBP without
  a valid user-bound, nonce-advanced, signed claim**

## Why it matters — the four guarantees

The contract enforces four properties that together make SBP a faithful
signal of protocol activity, independent of whether you trust the issuer:

### 1. No unearned supply

There is no function that mints SBP to an address without executing the full
claim validation. Not for the deployer, not for the controller, not for the
minter. Compile the contract, read the source, search for `_mint(` — it
appears exactly twice: the internal helper definition and one callsite inside
`claimPoints` after all five gates have passed.

A compromised minter key cannot mint to arbitrary addresses outside the
claim flow — it can only sign approvals that still require the target user
to hold an SBT and have an advanced nonce.

### 2. Proof of protocol usage

The `sbtNonce <= _lastClaimedNonce[user]` gate means the user's SBT nonce
must have **advanced since their last claim**. If the backing protocol only
advances the nonce in response to real user activity (transfers, deposits,
redemptions, etc.), then claiming more SBP is structurally impossible
without that activity having occurred on-chain.

An attacker who steals the minter key cannot grant themselves tokens without
also operating a protocol account whose nonce is advancing. The activity
nonce is a liveness proof.

### 3. Idempotent cumulative-amount claims

The claim payload carries `cumulativeAmount` — the total the backend believes
this user has earned to date — not a delta. The contract stores
`_totalClaimed[user]`, sets it to the new cumulative value, and mints only
the difference. A replay of an old signature can never mint more, because
the old cumulative is already ≤ the current stored total (`NothingToClaim`).

This means a buggy or compromised backend that over-signs cannot double-mint.
The worst a forward-progress bug can do is skip a claim that the user later
recovers with any valid signature carrying their true cumulative.

### 4. No admin control over balances

After mint, the contract has **no** admin functions over balances. No pause,
no freeze, no blacklist, no reassignment, no reclaim. The `controller` role
can rotate the `minter` key and transfer the controller role itself; neither
can touch user balances.

SBP holders own their balance against the contract in the same way USDC
holders do not (USDC has freeze/blacklist). SBP is strictly less admin-heavy
than most stablecoins.

## How it works — claim mechanics

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  User activity on backing protocol                                   │
│    ↓                                                                 │
│  SBT nonce advances on-chain (incrementNonce on the SBT contract)    │
│    ↓                                                                 │
│  Backend observes earnings + new SBT nonce                           │
│    ↓                                                                 │
│  Backend signs EIP-712 ClaimApproval(user, cumulativeAmount,         │
│                                     sbtNonce, deadline) with minter  │
│    ↓                                                                 │
│  User (or anyone) submits claimPoints(...) to SBP contract           │
│    ↓                                                                 │
│  Contract verifies:  valid signature                                 │
│                      user holds SBT                                  │
│                      signed sbtNonce == on-chain SBT nonce now       │
│                      signed sbtNonce  >  user's last claimed nonce   │
│                      cumulativeAmount >  _totalClaimed[user]         │
│                      block.timestamp  <= deadline                    │
│    ↓                                                                 │
│  Contract mints (cumulativeAmount - _totalClaimed[user]) to user     │
│  Contract stores new _totalClaimed and _lastClaimedNonce             │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

The EIP-712 domain: `name: "Soulbound Points"`, `version: "1"`, current
`chainId`, contract address as `verifyingContract`.

The `ClaimApproval` typed struct:

```solidity
ClaimApproval(address user, uint256 cumulativeAmount, uint256 sbtNonce, uint256 deadline)
```

## Security features

| Defense | Mechanism |
|---------|-----------|
| Signature malleability | s-value upper-bound check (rejects high-s signatures per EIP-2) |
| Invalid v values | Rejects any `v` other than 27 or 28 |
| Zero-address recovery | `ecrecover` returning zero is treated as invalid signature |
| Signature length | Strict 65 bytes — mismatched length reverts |
| Replay within a nonce | `NothingToClaim` revert when `cumulativeAmount <= _totalClaimed[user]` |
| Replay across nonces | `NonceNotAdvanced` revert when SBT nonce hasn't moved since last claim |
| Stale signatures | `ClaimExpired` revert past `deadline` |
| Forged SBT claim | `NoSBT` revert if user doesn't currently hold an SBT |
| Nonce desync | `NonceMismatch` revert if signed nonce differs from live on-chain nonce |
| Unauthorized minter rotation | Only the `controller` can call `setMinter` |
| Unauthorized controller transfer | Only the current `controller` can transfer the role |
| Zero-address writes | `InvalidAddress` revert on any administrative zero-address |
| Allowance race (approve-attack) | Standard ERC-20; callers should use `increaseAllowance` pattern in integrations |
| Integer overflow | Solidity 0.8+ checked arithmetic throughout; `unchecked` blocks used only where proven safe |

## Key separation and role model

Three distinct concerns, three distinct keys:

| Role | Power | Recommended key type |
|------|-------|----------------------|
| **controller** | Rotate the minter; transfer controller role | Multisig (2-of-3 or 3-of-N) |
| **minter** | Sign EIP-712 claim approvals (off-chain only; never holds funds) | Hot EOA, isolated from all other platform keys, rotatable |
| **user (caller)** | Submit claim tx on-chain, pay gas | Any EOA holding an SBT |

Critically: **the minter key does NOT need to be a protocol admin key.** It
signs messages off-chain. It never touches user funds, never calls the
contract, never has on-chain privilege beyond being the designated signer
recognized by the contract's signature check.

If the minter key is compromised:
- The attacker can sign arbitrary `ClaimApproval` messages
- But they can only authorize claims for addresses **that currently hold an
  SBT** and **whose SBT nonce has advanced since their last claim**
- They cannot backfill history: the cumulative-amount monotonic rule means
  signed approvals only ever add to a user's total, never issue new tokens
  to unrelated addresses
- The controller rotates the minter and invalidates all future signatures
  from the old key; unclaimed in-flight approvals from the old key remain
  valid against their specific users only

If the controller key is compromised: the attacker can rotate the minter
to themselves. They still face every other gate. Mitigation is a multisig
controller.

## Integration — backend signer

Minimal Node.js / TypeScript example using viem:

```ts
import { privateKeyToAccount } from 'viem/accounts';
import { keccak256, encodeAbiParameters } from 'viem';

const MINTER_KEY = process.env.SBP_MINTER_PRIVATE_KEY as `0x${string}`;
const account = privateKeyToAccount(MINTER_KEY);

const domain = {
  name: 'Soulbound Points',
  version: '1',
  chainId: 42161n,                         // Arbitrum One
  verifyingContract: SBP_ADDRESS,
};

const types = {
  ClaimApproval: [
    { name: 'user',             type: 'address' },
    { name: 'cumulativeAmount', type: 'uint256' },
    { name: 'sbtNonce',         type: 'uint256' },
    { name: 'deadline',         type: 'uint256' },
  ],
};

const message = {
  user:             '0x...',
  cumulativeAmount: 123_456n * 10n ** 18n,  // 123,456 SBP total-to-date
  sbtNonce:         currentSbtNonce,        // read live from SBT contract
  deadline:         BigInt(Math.floor(Date.now() / 1000) + 300), // 5 min
};

const signature = await account.signTypedData({ domain, types,
  primaryType: 'ClaimApproval', message });

// return signature + message to the user for them to submit on-chain
```

## Integration — user-facing claim

The user (or any third party — the claim is delegatable by design since it
carries a signature authorizing a specific outcome) submits:

```solidity
sbp.claimPoints(user, cumulativeAmount, sbtNonce, deadline, signature);
```

The user pays gas. The claim credits `user`. No centralized relayer is
required, though one can be provided for UX.

## Deployment

### Constructor

```solidity
constructor(address _sbt, address _minter, address _controller)
```

| Argument | Value |
|----------|-------|
| `_sbt` | Address of the SoulBound Token (identity) contract. Must expose `hasSBT(address)` and `getAccountData(address) returns (bytes32, uint256)`. |
| `_minter` | EOA that will sign claim approvals. Keep this key cold-ish — online only for signing. |
| `_controller` | Multisig (recommended) or EOA that can rotate the minter and transfer the controller role. |

All three must be non-zero. `_sbt` is `immutable` and cannot change after
deployment.

### Optimal deploy flow (Arbitrum One)

Using [Foundry](https://getfoundry.sh):

```bash
# 1. Clone this repo
git clone https://github.com/<your-org>/soulbound-points.git
cd soulbound-points

# 2. Set env
export PRIVATE_KEY=0x...                    # deployer EOA (one-time use)
export SBT_ADDRESS=0x...                    # identity contract address
export MINTER_ADDRESS=0x...                 # EOA that will sign claims
export CONTROLLER_ADDRESS=0x...             # multisig address
export RPC_URL=https://arb1.arbitrum.io/rpc
export ARBISCAN_API_KEY=...

# 3. Deploy + verify in one command
forge create \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY \
  --constructor-args $SBT_ADDRESS $MINTER_ADDRESS $CONTROLLER_ADDRESS \
  src/SoulBoundPoints.sol:SoulBoundPoints
```

### Recommended post-deploy checklist

1. **Verify bytecode** on Arbiscan — confirm constructor args render as
   expected (SBT, minter, controller addresses match what you intended).
2. **Confirm `minter()`** returns the EOA that will sign off-chain. Never the
   deployer EOA.
3. **Confirm `controller()`** returns the multisig address, not the deployer.
   If you deployed from a hot EOA, transfer controller immediately:
   ```bash
   cast send $SBP_ADDRESS "transferController(address)" $MULTISIG_ADDRESS \
     --rpc-url $RPC_URL --private-key $DEPLOYER_KEY
   ```
4. **Burn the deployer key** once controller is transferred and the deployer
   has no further role. The deployer retains zero privilege after the
   transfer — this is a hygiene step, not a security requirement.
5. **Test a claim** on a throwaway wallet with a minimal `cumulativeAmount`
   before the backend signer starts processing real user claims.
6. **Document the EIP-712 domain** (`name`, `version`, `chainId`,
   `verifyingContract`) for integrators. These are deterministic from the
   constructor and the chain, but pinning them in your docs saves future
   integrators a round trip.

### Alternative: forge script

For a more repeatable deploy (especially for multi-chain):

```solidity
// script/Deploy.s.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {SoulBoundPoints} from "../src/SoulBoundPoints.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();
        new SoulBoundPoints(
            vm.envAddress("SBT_ADDRESS"),
            vm.envAddress("MINTER_ADDRESS"),
            vm.envAddress("CONTROLLER_ADDRESS")
        );
        vm.stopBroadcast();
    }
}
```

Run:

```bash
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

### Gas estimate

At `optimizer_runs = 1_000_000`, deployment is approximately **~730k gas**
and a single `claimPoints` call runs **~105k gas** (first claim, cold storage)
or **~65k gas** (subsequent claims, warm storage). Numbers are Arbitrum-One
ballpark as of 2026 and will vary slightly with EVM pricing changes.

## Verification

Once deployed, verify with:

```bash
forge verify-contract $SBP_ADDRESS \
  --chain arbitrum_one \
  --constructor-args $(cast abi-encode "constructor(address,address,address)" \
    $SBT_ADDRESS $MINTER_ADDRESS $CONTROLLER_ADDRESS) \
  src/SoulBoundPoints.sol:SoulBoundPoints
```

Post-verification, the source will be visible on Arbiscan and the bytecode
can be independently reproduced by any third party from this repo.

## Audit surface

The contract is intentionally small — **~200 lines** — and written to be
auditable in a single sitting.

Areas that warrant the most attention during a review:

- `claimPoints` — the entire trust boundary lives here. The ordering of
  the five gates matters: each gate short-circuits before the next to
  minimize gas on failure paths.
- `_recoverSigner` — custom signature recovery. Verify the s-value range
  check against EIP-2 (`0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0`)
  and the v-value check (`27` or `28` only).
- `_mint` — verify it is only called from `claimPoints`. Grep for
  `_mint(` and confirm exactly one callsite outside the definition.
- `DOMAIN_SEPARATOR` — constructed in the constructor and `immutable`.
  Confirm `chainId` is read at deploy time, not cached statically, so the
  contract is safe against cross-chain replay if you happen to deploy to
  the same address on multiple chains.
- Role modifiers — `onlyController` on `setMinter` and `transferController`.
  No `onlyMinter` modifier exists on-chain; the minter's only power is
  signing messages, which has no corresponding on-chain function.

No upgradeability, no proxy, no delegatecall. What you deploy is what runs.

---

**Security contact:** security@soulboundsecurity.io

**License:** MIT — see [LICENSE](./LICENSE).
