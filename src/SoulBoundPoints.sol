// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/ISoulBoundToken.sol";

/**
 * @title SoulBound Points (SBP)
 * @notice ERC-20 reward points for SoulBound Finance platform activity.
 *         Standard ERC-20 compliant — compatible with Uniswap, DEX aggregators,
 *         and all ERC-20 integrations. No transfer restrictions.
 *
 * @dev    Custom ERC-20 with operator-gated minting via EIP-712 signed claim
 *         approvals. Points are earned for in-platform and on-chain activity
 *         including SoulBound transfers, referrals, and engagement. Claiming
 *         requires a valid SoulBound Token (SBT) and proof of recent protocol
 *         usage. No burn function — minted tokens are permanent.
 *
 *         This token represents non-monetary reward points within the SoulBound
 *         Finance ecosystem. It is not a security, investment contract, financial
 *         instrument, or governance token. It confers no ownership, equity,
 *         revenue share, or voting rights in any entity.
 *
 * @custom:security-contact security@soulboundsecurity.io
 */
contract SoulBoundPoints {
    string public constant name = "Soulbound Points";
    string public constant symbol = "SBP";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) private _totalClaimed;
    mapping(address => uint256) private _lastClaimedNonce;

    address public minter;
    address public controller;
    ISoulBoundToken public immutable sbt;

    bytes32 private immutable DOMAIN_SEPARATOR;
    bytes32 private constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant CLAIM_TYPEHASH = keccak256(
        "ClaimApproval(address user,uint256 cumulativeAmount,uint256 sbtNonce,uint256 deadline)"
    );

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event PointsClaimed(address indexed user, uint256 amount, uint256 cumulativeTotal, uint256 sbtNonce);
    event MinterUpdated(address indexed oldMinter, address indexed newMinter);
    event ControllerTransferred(address indexed oldController, address indexed newController);

    error ClaimExpired();
    error NoSBT();
    error NonceMismatch();
    error NonceNotAdvanced();
    error InvalidSignature();
    error NothingToClaim();
    error UnauthorizedAccess();
    error InvalidAddress();
    error InsufficientBalance();
    error InsufficientAllowance();

    modifier onlyController() {
        if (msg.sender != controller) revert UnauthorizedAccess();
        _;
    }

    modifier validAddress(address addr) {
        if (addr == address(0)) revert InvalidAddress();
        _;
    }

    constructor(
        address _sbt,
        address _minter,
        address _controller
    ) validAddress(_sbt) validAddress(_minter) validAddress(_controller) {
        sbt = ISoulBoundToken(_sbt);
        minter = _minter;
        controller = _controller;

        DOMAIN_SEPARATOR = keccak256(abi.encode(
            DOMAIN_TYPEHASH,
            keccak256("Soulbound Points"),
            keccak256("1"),
            block.chainid,
            address(this)
        ));
    }

    function claimPoints(
        address user,
        uint256 cumulativeAmount,
        uint256 sbtNonce,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) revert ClaimExpired();
        if (!sbt.hasSBT(user)) revert NoSBT();

        (, uint256 currentNonce) = sbt.getAccountData(user);
        if (currentNonce != sbtNonce) revert NonceMismatch();
        if (sbtNonce <= _lastClaimedNonce[user]) revert NonceNotAdvanced();

        bytes32 structHash = keccak256(abi.encode(
            CLAIM_TYPEHASH, user, cumulativeAmount, sbtNonce, deadline
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01", DOMAIN_SEPARATOR, structHash
        ));
        if (_recoverSigner(digest, signature) != minter) revert InvalidSignature();

        if (cumulativeAmount <= _totalClaimed[user]) revert NothingToClaim();

        uint256 mintAmount = cumulativeAmount - _totalClaimed[user];
        _totalClaimed[user] = cumulativeAmount;
        _lastClaimedNonce[user] = sbtNonce;
        _mint(user, mintAmount);

        emit PointsClaimed(user, mintAmount, cumulativeAmount, sbtNonce);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InsufficientAllowance();
            unchecked { _allowances[from][msg.sender] = currentAllowance - amount; }
        }
        return _transfer(from, to, amount);
    }

    function getClaimState(address user) external view returns (uint256 totalClaimed, uint256 lastClaimedNonce) {
        return (_totalClaimed[user], _lastClaimedNonce[user]);
    }

    function getDomainSeparator() external view returns (bytes32) {
        return DOMAIN_SEPARATOR;
    }

    function setMinter(address _newMinter) external onlyController validAddress(_newMinter) {
        address old = minter;
        minter = _newMinter;
        emit MinterUpdated(old, _newMinter);
    }

    function transferController(address _newController) external onlyController validAddress(_newController) {
        address old = controller;
        controller = _newController;
        emit ControllerTransferred(old, _newController);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        if (to == address(0)) revert InvalidAddress();
        if (_balances[from] < amount) revert InsufficientBalance();
        unchecked { _balances[from] -= amount; }
        _balances[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function _recoverSigner(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        if (sig.length != 65) revert InvalidSignature();
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert InvalidSignature();
        }
        if (v != 27 && v != 28) revert InvalidSignature();
        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0)) revert InvalidSignature();
        return recovered;
    }
}
