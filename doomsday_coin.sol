// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title DoomsdayCoin
 * @notice Production-ready implementation with founder allocation
 * @dev Total supply: 1 DDC | Founders: 0.2 DDC | Public: 0.8 DDC
 */
contract DoomsdayCoin is ReentrancyGuard, Pausable, AccessControl, Initializable {
    
    // ============ Constants ============
    
    string public constant NAME = "Doomsday Coin";
    string public constant SYMBOL = "DDC";
    uint8 public constant DECIMALS = 18;
    uint256 public constant TOTAL_SUPPLY = 1e18; // 1 coin
    uint256 public constant FOUNDER_ALLOCATION = 2e17; // 0.2 coin (20%)
    uint256 public constant PUBLIC_ALLOCATION = 8e17; // 0.8 coin (80%)
    
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");
    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant FOUNDER_ROLE = keccak256("FOUNDER_ROLE");
    
    // Time-lock period for critical operations (24 hours)
    uint256 public constant TIMELOCK_PERIOD = 24 hours;
    
    // Vesting period for founders (2 years)
    uint256 public constant VESTING_PERIOD = 730 days;
    
    // Cliff period (6 months before any vesting)
    uint256 public constant CLIFF_PERIOD = 180 days;
    
    // ============ State Variables ============
    
    // Token balances
    mapping(address => uint256) private _balances;
    
    // Token allowances
    mapping(address => mapping(address => uint256)) private _allowances;
    
    // Public reserve (0.8 DDC available for distribution)
    uint256 public publicReserve;
    
    // Founder reserve (0.2 DDC for founders)
    uint256 public founderReserve;
    
    // Circulating supply (released from reserves)
    uint256 public circulatingSupply;
    
    // Founder vesting tracking
    struct FounderVesting {
        uint256 totalAllocation;
        uint256 claimed;
        uint256 startTime;
        bool initialized;
    }
    mapping(address => FounderVesting) public founderVesting;
    address[] public founders;
    uint256 public totalFoundersClaimed;
    
    // Holder tracking
    address[] private _holders;
    mapping(address => bool) private _isHolder;
    mapping(address => uint256) private _holderIndex;
    
    // Verification system
    enum VerificationStatus {
        Unverified,
        Pending,
        Verified,
        Flagged
    }
    mapping(address => VerificationStatus) public verificationStatus;
    mapping(address => uint256) public lastVerificationTime;
    uint256 public verificationExpiry = 180 days;
    
    // Time-locked operations
    struct TimeLockOperation {
        uint256 executeAfter;
        bool executed;
        bytes data;
    }
    mapping(bytes32 => TimeLockOperation) public timeLockedOps;
    
    // Multi-chain support
    uint256 public chainId;
    mapping(uint256 => bool) public supportedChains;
    mapping(bytes32 => bool) public processedBridgeTransactions;
    
    // Contract deployment time
    uint256 public immutable deploymentTime;
    
    // ============ Events ============
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    event SharesReleased(address indexed to, uint256 amount, uint256 newCirculatingSupply);
    event TokensSeized(address indexed account, uint256 amount, string reason);
    
    event AccountVerified(address indexed account, address indexed verifier);
    event AccountFlagged(address indexed account, address indexed flagger, string reason);
    event VerificationExpired(address indexed account);
    
    event OperationScheduled(bytes32 indexed opHash, uint256 executeAfter);
    event OperationExecuted(bytes32 indexed opHash);
    event OperationCancelled(bytes32 indexed opHash);
    
    event BridgeTransfer(
        address indexed from,
        uint256 amount,
        uint256 indexed toChainId,
        bytes32 indexed txHash
    );
    event BridgeReceive(
        address indexed to,
        uint256 amount,
        uint256 indexed fromChainId,
        bytes32 indexed txHash
    );
    
    event FounderAdded(address indexed founder, uint256 allocation);
    event FounderVestingClaimed(address indexed founder, uint256 amount, uint256 totalClaimed);
    
    // ============ Modifiers ============
    
    modifier onlyVerified() {
        require(
            verificationStatus[msg.sender] == VerificationStatus.Verified,
            "DDC: Account not verified"
        );
        require(
            block.timestamp <= lastVerificationTime[msg.sender] + verificationExpiry,
            "DDC: Verification expired"
        );
        _;
    }
    
    modifier notFlagged(address account) {
        require(
            verificationStatus[account] != VerificationStatus.Flagged,
            "DDC: Account is flagged"
        );
        _;
    }
    
    // ============ Constructor & Initialization ============
    
    constructor(address initialAdmin) {
        require(initialAdmin != address(0), "DDC: Invalid admin address");
        
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);
        
        chainId = block.chainid;
        publicReserve = PUBLIC_ALLOCATION; // 0.8 DDC
        founderReserve = FOUNDER_ALLOCATION; // 0.2 DDC
        circulatingSupply = 0;
        
        deploymentTime = block.timestamp;
    }
    
    /**
     * @dev Initialize founder allocations with equal distribution
     * @param founderAddresses Array of founder addresses
     */
    function initializeFounders(address[] calldata founderAddresses) 
        external 
        onlyRole(ADMIN_ROLE)
    {
        require(founders.length == 0, "DDC: Founders already initialized");
        require(founderAddresses.length > 0, "DDC: No founders provided");
        require(founderAddresses.length <= 10, "DDC: Too many founders");
        
        uint256 allocationPerFounder = FOUNDER_ALLOCATION / founderAddresses.length;
        
        for (uint256 i = 0; i < founderAddresses.length; i++) {
            address founder = founderAddresses[i];
            require(founder != address(0), "DDC: Invalid founder address");
            require(!founderVesting[founder].initialized, "DDC: Founder already added");
            
            founders.push(founder);
            founderVesting[founder] = FounderVesting({
                totalAllocation: allocationPerFounder,
                claimed: 0,
                startTime: block.timestamp,
                initialized: true
            });
            
            _grantRole(FOUNDER_ROLE, founder);
            
            // Auto-verify founders
            verificationStatus[founder] = VerificationStatus.Verified;
            lastVerificationTime[founder] = block.timestamp;
            
            emit FounderAdded(founder, allocationPerFounder);
            emit AccountVerified(founder, msg.sender);
        }
    }
    
    /**
     * @dev Initialize supported chains
     */
    function initializeSupportedChains(uint256[] calldata chains) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        for (uint256 i = 0; i < chains.length; i++) {
            supportedChains[chains[i]] = true;
        }
    }
    
    // ============ ERC-20 Core Functions ============
    
    function name() public pure returns (string memory) {
        return NAME;
    }
    
    function symbol() public pure returns (string memory) {
        return SYMBOL;
    }
    
    function decimals() public pure returns (uint8) {
        return DECIMALS;
    }
    
    function totalSupply() public pure returns (uint256) {
        return TOTAL_SUPPLY;
    }
    
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
    
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }
    
    function transfer(address to, uint256 amount) 
        public 
        virtual 
        whenNotPaused 
        nonReentrant
        onlyVerified
        notFlagged(to)
        returns (bool) 
    {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) 
        public 
        virtual 
        whenNotPaused
        onlyVerified
        returns (bool) 
    {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        whenNotPaused
        nonReentrant
        notFlagged(from)
        notFlagged(to)
        returns (bool)
    {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }
    
    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        whenNotPaused
        onlyVerified
        returns (bool)
    {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }
    
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        whenNotPaused
        onlyVerified
        returns (bool)
    {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "DDC: Decreased below zero");
        unchecked {
            _approve(msg.sender, spender, currentAllowance - subtractedValue);
        }
        return true;
    }
    
    // ============ Internal Transfer Logic ============
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "DDC: Transfer from zero address");
        require(to != address(0), "DDC: Transfer to zero address");
        require(_balances[from] >= amount, "DDC: Insufficient balance");
        
        require(
            verificationStatus[to] == VerificationStatus.Verified &&
            block.timestamp <= lastVerificationTime[to] + verificationExpiry,
            "DDC: Recipient not verified or expired"
        );
        
        unchecked {
            _balances[from] -= amount;
            _balances[to] += amount;
        }
        
        if (_balances[to] > 0 && !_isHolder[to]) {
            _addHolder(to);
        }
        if (_balances[from] == 0 && _isHolder[from]) {
            _removeHolder(from);
        }
        
        emit Transfer(from, to, amount);
    }
    
    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "DDC: Approve from zero address");
        require(spender != address(0), "DDC: Approve to zero address");
        
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    
    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "DDC: Insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }
    
    // ============ Holder Management ============
    
    function _addHolder(address account) internal {
        if (!_isHolder[account]) {
            _isHolder[account] = true;
            _holderIndex[account] = _holders.length;
            _holders.push(account);
        }
    }
    
    function _removeHolder(address account) internal {
        if (!_isHolder[account]) {
            return;
        }
        
        uint256 index = _holderIndex[account];
        uint256 lastIndex = _holders.length - 1;
        
        if (index != lastIndex) {
            address lastHolder = _holders[lastIndex];
            _holders[index] = lastHolder;
            _holderIndex[lastHolder] = index;
        }
        
        _holders.pop();
        _isHolder[account] = false;
    }
    
    function getHolders() external view returns (address[] memory) {
        return _holders;
    }
    
    function getHolderCount() external view returns (uint256) {
        return _holders.length;
    }
    
    // ============ Founder Vesting ============
    
    /**
     * @dev Calculate vested amount for a founder
     */
    function calculateVestedAmount(address founder) public view returns (uint256) {
        FounderVesting memory vesting = founderVesting[founder];
        
        if (!vesting.initialized) {
            return 0;
        }
        
        uint256 elapsedTime = block.timestamp - vesting.startTime;
        
        // Before cliff, nothing is vested
        if (elapsedTime < CLIFF_PERIOD) {
            return 0;
        }
        
        // After full vesting period, everything is vested
        if (elapsedTime >= VESTING_PERIOD) {
            return vesting.totalAllocation;
        }
        
        // Linear vesting after cliff
        uint256 vestedAmount = (vesting.totalAllocation * elapsedTime) / VESTING_PERIOD;
        return vestedAmount;
    }
    
    /**
     * @dev Calculate claimable amount (vested - already claimed)
     */
    function calculateClaimableAmount(address founder) public view returns (uint256) {
        uint256 vested = calculateVestedAmount(founder);
        uint256 claimed = founderVesting[founder].claimed;
        
        if (vested <= claimed) {
            return 0;
        }
        
        return vested - claimed;
    }
    
    /**
     * @dev Founder claims their vested tokens
     */
    function claimFounderTokens() external onlyRole(FOUNDER_ROLE) nonReentrant {
        address founder = msg.sender;
        uint256 claimable = calculateClaimableAmount(founder);
        
        require(claimable > 0, "DDC: No tokens to claim");
        require(founderReserve >= claimable, "DDC: Insufficient founder reserve");
        
        founderVesting[founder].claimed += claimable;
        totalFoundersClaimed += claimable;
        
        unchecked {
            founderReserve -= claimable;
            circulatingSupply += claimable;
            _balances[founder] += claimable;
        }
        
        if (!_isHolder[founder]) {
            _addHolder(founder);
        }
        
        emit FounderVestingClaimed(founder, claimable, founderVesting[founder].claimed);
        emit Transfer(address(0), founder, claimable);
    }
    
    /**
     * @dev Get all founders and their vesting info
     */
    function getFoundersInfo() external view returns (
        address[] memory founderAddresses,
        uint256[] memory totalAllocations,
        uint256[] memory claimedAmounts,
        uint256[] memory claimableAmounts
    ) {
        uint256 length = founders.length;
        founderAddresses = new address[](length);
        totalAllocations = new uint256[](length);
        claimedAmounts = new uint256[](length);
        claimableAmounts = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            address founder = founders[i];
            founderAddresses[i] = founder;
            totalAllocations[i] = founderVesting[founder].totalAllocation;
            claimedAmounts[i] = founderVesting[founder].claimed;
            claimableAmounts[i] = calculateClaimableAmount(founder);
        }
        
        return (founderAddresses, totalAllocations, claimedAmounts, claimableAmounts);
    }
    
    // ============ Verification System ============
    
    function verifyAccount(address account) 
        external 
        onlyRole(VERIFIER_ROLE) 
    {
        require(account != address(0), "DDC: Invalid address");
        require(
            verificationStatus[account] != VerificationStatus.Flagged,
            "DDC: Cannot verify flagged account"
        );
        
        verificationStatus[account] = VerificationStatus.Verified;
        lastVerificationTime[account] = block.timestamp;
        
        emit AccountVerified(account, msg.sender);
    }
    
    function batchVerifyAccounts(address[] calldata accounts)
        external
        onlyRole(VERIFIER_ROLE)
    {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (
                accounts[i] != address(0) &&
                verificationStatus[accounts[i]] != VerificationStatus.Flagged
            ) {
                verificationStatus[accounts[i]] = VerificationStatus.Verified;
                lastVerificationTime[accounts[i]] = block.timestamp;
                emit AccountVerified(accounts[i], msg.sender);
            }
        }
    }
    
    function renewVerification() external {
        require(
            verificationStatus[msg.sender] == VerificationStatus.Verified,
            "DDC: Not verified"
        );
        
        lastVerificationTime[msg.sender] = block.timestamp;
        emit AccountVerified(msg.sender, msg.sender);
    }
    
    function isVerificationValid(address account) public view returns (bool) {
        return verificationStatus[account] == VerificationStatus.Verified &&
               block.timestamp <= lastVerificationTime[account] + verificationExpiry;
    }
    
    // ============ Public Share Management ============
    
    /**
     * @dev Release PUBLIC shares from reserve (not founder allocation)
     */
    function scheduleShareRelease(address to, uint256 amount)
        external
        onlyRole(ADMIN_ROLE)
        returns (bytes32)
    {
        require(to != address(0), "DDC: Invalid recipient");
        require(amount > 0, "DDC: Amount must be positive");
        require(amount <= publicReserve, "DDC: Insufficient public reserve");
        require(isVerificationValid(to), "DDC: Recipient not verified");
        
        bytes32 opHash = keccak256(
            abi.encodePacked("RELEASE", to, amount, block.timestamp)
        );
        
        timeLockedOps[opHash] = TimeLockOperation({
            executeAfter: block.timestamp + TIMELOCK_PERIOD,
            executed: false,
            data: abi.encode(to, amount)
        });
        
        emit OperationScheduled(opHash, block.timestamp + TIMELOCK_PERIOD);
        return opHash;
    }
    
    function executeShareRelease(bytes32 opHash)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        TimeLockOperation storage op = timeLockedOps[opHash];
        require(op.executeAfter > 0, "DDC: Operation not found");
        require(!op.executed, "DDC: Already executed");
        require(block.timestamp >= op.executeAfter, "DDC: Time-lock active");
        
        op.executed = true;
        
        (address to, uint256 amount) = abi.decode(op.data, (address, uint256));
        
        require(amount <= publicReserve, "DDC: Insufficient public reserve");
        require(isVerificationValid(to), "DDC: Recipient verification expired");
        
        unchecked {
            publicReserve -= amount;
            circulatingSupply += amount;
            _balances[to] += amount;
        }
        
        if (!_isHolder[to]) {
            _addHolder(to);
        }
        
        emit SharesReleased(to, amount, circulatingSupply);
        emit Transfer(address(0), to, amount);
        emit OperationExecuted(opHash);
    }
    
    function cancelOperation(bytes32 opHash)
        external
        onlyRole(ADMIN_ROLE)
    {
        TimeLockOperation storage op = timeLockedOps[opHash];
        require(op.executeAfter > 0, "DDC: Operation not found");
        require(!op.executed, "DDC: Already executed");
        
        delete timeLockedOps[opHash];
        emit OperationCancelled(opHash);
    }
    
    // ============ Account Management ============
    
    function flagAccount(address account, string calldata reason)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        require(account != address(0), "DDC: Invalid address");
        require(
            verificationStatus[account] != VerificationStatus.Flagged,
            "DDC: Already flagged"
        );
        
        uint256 seized = _balances[account];
        verificationStatus[account] = VerificationStatus.Flagged;
        
        if (seized > 0) {
            _balances[account] = 0;
            unchecked {
                publicReserve += seized;
                circulatingSupply -= seized;
            }
            _removeHolder(account);
            
            emit TokensSeized(account, seized, reason);
            emit Transfer(account, address(0), seized);
        }
        
        emit AccountFlagged(account, msg.sender, reason);
    }
    
    function processInheritance(address deceased)
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        require(deceased != address(0), "DDC: Invalid address");
        require(
            verificationStatus[deceased] != VerificationStatus.Flagged,
            "DDC: Account already flagged"
        );
        
        uint256 seized = _balances[deceased];
        
        if (seized > 0) {
            _balances[deceased] = 0;
            unchecked {
                publicReserve += seized;
                circulatingSupply -= seized;
            }
            _removeHolder(deceased);
            
            emit TokensSeized(deceased, seized, "Inheritance");
            emit Transfer(deceased, address(0), seized);
        }
        
        verificationStatus[deceased] = VerificationStatus.Flagged;
    }
    
    // ============ Cross-Chain Bridge ============
    
    function bridgeToChain(uint256 amount, uint256 toChainId)
        external
        onlyVerified
        nonReentrant
    {
        require(supportedChains[toChainId], "DDC: Chain not supported");
        require(amount > 0, "DDC: Invalid amount");
        require(_balances[msg.sender] >= amount, "DDC: Insufficient balance");
        
        bytes32 txHash = keccak256(
            abi.encodePacked(msg.sender, amount, chainId, toChainId, block.timestamp)
        );
        
        _balances[msg.sender] -= amount;
        if (_balances[msg.sender] == 0) {
            _removeHolder(msg.sender);
        }
        
        emit BridgeTransfer(msg.sender, amount, toChainId, txHash);
        emit Transfer(msg.sender, address(0), amount);
    }
    
    function bridgeFromChain(
        address to,
        uint256 amount,
        uint256 fromChainId,
        bytes32 txHash
    )
        external
        onlyRole(BRIDGE_ROLE)
        nonReentrant
    {
        require(supportedChains[fromChainId], "DDC: Chain not supported");
        require(!processedBridgeTransactions[txHash], "DDC: Already processed");
        require(isVerificationValid(to), "DDC: Recipient not verified");
        
        processedBridgeTransactions[txHash] = true;
        
        _balances[to] += amount;
        if (!_isHolder[to]) {
            _addHolder(to);
        }
        
        emit BridgeReceive(to, amount, fromChainId, txHash);
        emit Transfer(address(0), to, amount);
    }
    
    // ============ Emergency Controls ============
    
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }
    
    // ============ Configuration ============
    
    function setVerificationExpiry(uint256 newExpiry)
        external
        onlyRole(ADMIN_ROLE)
    {
        require(newExpiry >= 30 days && newExpiry <= 365 days, "DDC: Invalid expiry");
        verificationExpiry = newExpiry;
    }
    
    // ============ View Functions ============
    
    function getContractInfo() external view returns (
        uint256 totalSupply_,
        uint256 publicReserve_,
        uint256 founderReserve_,
        uint256 circulatingSupply_,
        uint256 holderCount_,
        uint256 chainId_,
        uint256 founderCount_
    ) {
        return (
            TOTAL_SUPPLY,
            publicReserve,
            founderReserve,
            circulatingSupply,
            _holders.length,
            chainId,
            founders.length
        );
    }
    
    function getFounderCount() external view returns (uint256) {
        return founders.length;
    }
}
