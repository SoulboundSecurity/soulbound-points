# Internal Adversarial Review — SoulBound Points — 2026-10-11

Adversarial review of `SoulBoundPoints.sol` (205 lines, reviewed in
full), the minimal interface, and every claim the README makes, treating
the repository as a standalone artifact. The deployed Arbitrum One
instance (`0x559677B6F22f5Ab32D8a185836be25Deb725B274`) is immutable and
byte-identical to this source; nothing in this review alters it.

**External review is welcome.** We publish our own findings as a matter
of course (see the
[sbf-protocol audits log](https://github.com/SoulboundSecurity/sbf-protocol/tree/master/audits)
for the house convention), we accept responsible disclosures at
security@soulboundsecurity.io, and pull requests are welcome under the
MIT license.

---

## Fixed in this revision (documentation only)

### LOW · README recommended an allowance function the contract does not have

The security table advised integrators to "use the `increaseAllowance`
pattern" for the standard ERC-20 approve race; the contract deliberately
ships only plain `approve`, and the deployed instance is immutable, so
the advice was unactionable as written. The README now states the real
mitigations: zero-then-set, or an infinite allowance, which
`transferFrom` supports natively by skipping the decrement at
`type(uint256).max`. No code change; the contract was always correct.

## Documented characteristics (deliberate; no action)

| Item | The characteristic |
| --- | --- |
| Fork-of-chain replay residual | `DOMAIN_SEPARATOR` caches `block.chainid` at deployment, so a chain split would allow claim replay on both resulting forks. The multi-deployment case (same address, different chains) is correctly bound at deploy time; a chain split is an ecosystem-level event this contract deliberately does not defend against |
| Nonce freshness race | Protocol activity between approval signing and claim submission advances the live SBT nonce and the claim reverts `NonceMismatch`; the user re-requests an approval. Fail-closed by design |
| Distinguishable reverts | Unlike an authentication boundary, the typed errors here are deliberately distinguishable: they are the integration contract, not an information-hiding surface |

## Reviewed and found sound

The claim gauntlet's ordering (checks, effects, event; all external
calls are view STATICCALLs, so even a hostile SBT implementation in a
fork cannot reenter; `_mint` has no hooks). Replay, exhaustively: the
deadline, strictly-increasing claimed nonce, and monotonic cumulative
total close every shape tried — a consumed approval dies on
`NothingToClaim`, a same-nonce second approval on `NonceNotAdvanced`, a
stale approval on `NonceMismatch`, and a malleated signature recovers
the same signer into the same consumed state, with low-s, v, and
zero-recovery checks present regardless. Front-running a claim executes
the victim's own mint (delegation is a documented feature). Minter
compromise is bounded per-user by SBT possession plus nonce advance and
is instantly revocable by controller rotation, which invalidates every
signature the old key ever produced. ERC-20 internals: infinite-
allowance shortcut correct, zero-address and balance guards present,
self-transfer nets correctly, checked arithmetic where it matters and
proven-safe `unchecked` where it does not.

## Verdict

No code findings. One documentation defect, fixed in this revision. The
contract does what its README claims, in a form reviewable in a single
sitting, and its claim mechanics — cumulative amounts, nonce liveness,
appointment-semantics role administration — survived the same
adversarial pass applied across the SoulBound Security estate.
