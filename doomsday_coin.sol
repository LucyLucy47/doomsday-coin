// SPDX-License-Identifier: MIT
/*
 *  Doomsday Coin (DDC) Proof‑of‑Concept Smart Contract
 *
 *  This smart contract implements a simplified version of the Doomsday Coin
 *  described in the MUAI foundation white paper (V3.0). It illustrates
 *  several of the key ideas articulated in the document including: a
 *  fixed and indivisible total supply, human‑only ownership, automatic
 *  redistribution when non‑human accounts are detected, and the ability
 *  to gradually sell previously uncirculated shares. For brevity and
 *  readability, sensitive biometric and AI‑based verifications are not
 *  implemented on‑chain. In a production deployment these checks would be
 *  handled off‑chain through decentralized identity systems and oracles.
 */

pragma solidity ^0.8.20;

/**
 * @title DoomsdayCoin
 * @dev Minimal ERC‑20–like token with fixed supply of one unit (1 * 10^18
 * decimals). The contract owner may release unsold shares, flag addresses as
 * ineligible (simulating detection of corporate or AI accounts), and
 * redistribute their holdings to legitimate human participants. The contract
 * also includes a simple transfer function that enforces the human‑only rule.
 */
contract DoomsdayCoin {
    // Token metadata
    string public constant name = "Doomsday Coin";
    string public constant symbol = "DDC";
    uint8 public constant decimals = 18;

    // The total supply is one whole coin represented with 18 decimals.
    uint256 public constant totalSupply = 1e18;

    // Address of the contract administrator (e.g. MUAI foundation). Only the
    // admin can perform privileged operations such as releasing new shares
    // or flagging non‑human accounts. In a production system this could be
    // replaced by a decentralized governance mechanism.
    address public admin;

    // Track balances of each holder
    mapping(address => uint256) private balances;
    // Track allowances for ERC‑20 compatibility
    mapping(address => mapping(address => uint256)) private allowances;

    // Reserve of unsold shares that have not yet been issued. Initially
    // the entire supply resides in the reserve. When `releaseShares()` is
    // called, a portion of the reserve is minted to a specified recipient
    // (e.g. a sale contract or individual). Remaining tokens stay locked in
    // reserve until future releases.
    uint256 public reserve;

    // List of current token holders. We maintain this list to redistribute
    // balances when an ineligible account is flagged. This is not gas
    // efficient for large communities but suffices for a simplified demo. A
    // more scalable design would use a snapshot‑based or merkle tree
    // mechanism.
    address[] private holders;
    mapping(address => bool) private isHolder;

    // Mapping of flagged addresses that are considered non‑human. Once
    // flagged, an address cannot receive tokens and its balance will be
    // redistributed. Only the admin may flag accounts.
    mapping(address => bool) public flagged;

    // Events for transparency
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Flagged(address indexed account, uint256 balanceRedistributed);
    event SharesReleased(address indexed to, uint256 amount);

    /**
     * @dev Initialize the contract, setting the deployer as admin and
     * placing the entire supply in reserve.
     */
    constructor() {
        admin = msg.sender;
        reserve = totalSupply;
    }

    /**
     * @dev Modifier to restrict functions to the contract admin.
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }

    /**
     * @dev Returns the balance of an account.
     * @param account The address to query the balance of.
     */
    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    /**
     * @dev Internal function to add a new holder to the list. This keeps the
     * holders array up to date for redistribution. It is called whenever
     * tokens are transferred to an address that previously had zero balance.
     */
    function _addHolder(address account) internal {
        if (!isHolder[account]) {
            isHolder[account] = true;
            holders.push(account);
        }
    }

    /**
     * @dev Transfer tokens to another address. Transfers are blocked if
     * either the sender or recipient is flagged as non‑human. Upon a
     * successful transfer, the recipient is recorded in the holders list if
     * they were not already present.
     * @param to Recipient address
     * @param value Amount to transfer (in smallest units)
     * @return True on success
     */
    function transfer(address to, uint256 value) public returns (bool) {
        require(!flagged[msg.sender], "Sender address is flagged as ineligible");
        require(!flagged[to], "Recipient address is flagged as ineligible");
        require(balances[msg.sender] >= value, "Insufficient balance");

        balances[msg.sender] -= value;
        balances[to] += value;
        _addHolder(to);
        emit Transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @dev Approve another address to spend tokens on your behalf. ERC‑20
     * compatibility is provided for interoperability with DeFi protocols.
     * @param spender Address allowed to spend
     * @param value Maximum amount they can spend
     * @return True on success
     */
    function approve(address spender, uint256 value) public returns (bool) {
        require(!flagged[msg.sender], "Owner address is flagged");
        allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Transfer tokens on behalf of another address. The sender must have
     * sufficient allowance and both the owner and recipient must be
     * unflagged.
     */
    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        require(!flagged[from], "From address is flagged as ineligible");
        require(!flagged[to], "Recipient address is flagged as ineligible");
        require(allowances[from][msg.sender] >= value, "Allowance exceeded");
        require(balances[from] >= value, "Insufficient balance");

        allowances[from][msg.sender] -= value;
        balances[from] -= value;
        balances[to] += value;
        _addHolder(to);
        emit Transfer(from, to, value);
        return true;
    }

    /**
     * @dev Returns the remaining allowance a spender has on an owner's
     * account.
     */
    function allowance(address owner_, address spender) public view returns (uint256) {
        return allowances[owner_][spender];
    }

    /**
     * @dev Admin function to release a portion of the reserved supply to a
     * recipient. This simulates the "new coin sale" described in the
     * white paper. When new shares are released, existing holders' balances
     * remain unchanged but their relative ownership decreases. The amount
     * released must not exceed the reserve.
     * @param to Address receiving the newly released tokens
     * @param amount Amount to release (in smallest units)
     */
    function releaseShares(address to, uint256 amount) external onlyAdmin {
        require(amount > 0, "Amount must be greater than zero");
        require(amount <= reserve, "Not enough reserve available");
        require(!flagged[to], "Recipient is flagged as ineligible");

        reserve -= amount;
        balances[to] += amount;
        _addHolder(to);
        emit SharesReleased(to, amount);
        emit Transfer(address(0), to, amount);
    }

    /**
     * @dev Admin function to flag an account as non‑human (e.g. corporate or
     * AI agent). The flagged account's balance is burned and redistributed
     * proportionally among all remaining human holders. Once flagged, the
     * account cannot receive tokens in the future.
     * @param account The address to flag
     */
    function flagAccount(address account) external onlyAdmin {
        require(!flagged[account], "Account already flagged");
        uint256 balanceToRedistribute = balances[account];
        flagged[account] = true;
        balances[account] = 0;

        // Sum the total balances of eligible accounts for redistribution
        uint256 totalEligible = 0;
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            if (!flagged[holder] && balances[holder] > 0) {
                totalEligible += balances[holder];
            }
        }

        // Distribute the seized balance proportionally to eligible holders
        if (balanceToRedistribute > 0 && totalEligible > 0) {
            for (uint256 i = 0; i < holders.length; i++) {
                address holder = holders[i];
                if (!flagged[holder] && balances[holder] > 0) {
                    uint256 share = (balanceToRedistribute * balances[holder]) / totalEligible;
                    balances[holder] += share;
                }
            }
        } else if (balanceToRedistribute > 0 && totalEligible == 0) {
            // If no eligible holders exist, return seized tokens to reserve
            reserve += balanceToRedistribute;
        }

        emit Flagged(account, balanceToRedistribute);
        emit Transfer(account, address(0), balanceToRedistribute);
    }

    /**
     * @dev Admin function to simulate a death or end‑of‑civilization event
     * by redistributing a deceased account's holdings among remaining
     * participants. In a production environment this would be triggered by
     * off‑chain proof of death/absence delivered via an oracle. Here the
     * admin specifies the account to clear.
     * @param account The deceased account
     */
    function redistributeOnDeath(address account) external onlyAdmin {
        require(!flagged[account], "Account already flagged");
        uint256 balanceToRedistribute = balances[account];
        balances[account] = 0;

        uint256 totalEligible = 0;
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            if (!flagged[holder] && balances[holder] > 0 && holder != account) {
                totalEligible += balances[holder];
            }
        }

        if (balanceToRedistribute > 0 && totalEligible > 0) {
            for (uint256 i = 0; i < holders.length; i++) {
                address holder = holders[i];
                if (!flagged[holder] && balances[holder] > 0 && holder != account) {
                    uint256 share = (balanceToRedistribute * balances[holder]) / totalEligible;
                    balances[holder] += share;
                }
            }
        } else if (balanceToRedistribute > 0 && totalEligible == 0) {
            reserve += balanceToRedistribute;
        }

        emit Transfer(account, address(0), balanceToRedistribute);
    }
}