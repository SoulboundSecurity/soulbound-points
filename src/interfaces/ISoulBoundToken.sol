// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title ISoulBoundToken
 * @notice Minimal interface consumed by SoulBoundPoints — the two
 *         read functions needed to verify SBT ownership and nonce
 *         liveness at claim time. This file is an MIT-licensed
 *         extraction of the upstream interface, reduced to exactly
 *         the surface SBP depends on.
 *
 *         Any SBT-like contract that implements these two functions
 *         with semantics equivalent to "does this address hold a
 *         bound identity token?" and "what is the monotonic activity
 *         nonce for this address?" can back a SoulBoundPoints
 *         deployment.
 */
interface ISoulBoundToken {
    /// @notice Returns true iff the account currently holds a bound identity token.
    function hasSBT(address account) external view returns (bool);

    /// @notice Returns the opaque encrypted account id and the monotonic
    ///         activity nonce for the given address. SBP reads only the nonce.
    function getAccountData(address account) external view returns (bytes32 encryptedAccountId, uint256 nonce);
}
