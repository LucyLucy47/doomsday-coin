# Doomsday Coin (DDC) - Deployment Guide

## Overview

This guide covers deploying Doomsday Coin on Ethereum and other EVM-compatible chains with full multi-chain support.

---

## Key Improvements from Original Contract

### Security Enhancements
- ✅ **ReentrancyGuard**: Prevents reentrancy attacks
- ✅ **Pausable**: Emergency stop mechanism
- ✅ **AccessControl**: Role-based permissions (Admin, Verifier, Bridge, Pauser)
- ✅ **Time-locks**: 24-hour delay on critical operations

### Gas Optimization
- ✅ Efficient holder tracking with O(1) removal
- ✅ Batch verification operations
- ✅ Unchecked arithmetic where safe

### New Features
- ✅ **Verification System**: Human-only ownership with 180-day renewal
- ✅ **Multi-chain Bridge**: Native cross-chain support
- ✅ **Governance**: Multi-signature admin operations
- ✅ **Allowance Functions**: Full ERC-20 compatibility
- ✅ **Comprehensive Events**: Complete audit trail

---

## Prerequisites

### Required Tools
```bash
npm install --save-dev hardhat
npm install --save-dev @openzeppelin/contracts
npm install --save-dev @openzeppelin/hardhat-upgrades
npm install --save-dev @nomicfoundation/hardhat-ethers
npm install --save-dev @nomicfoundation/hardhat-verify
npm install --save-dev dotenv
```

### Environment Setup
Create `.env` file:
```env
# Network RPC URLs
ETHEREUM_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
POLYGON_RPC_URL=https://polygon-mainnet.g.alchemy.com/v2/YOUR_KEY
AVALANCHE_RPC_URL=https://api.avax.network/ext/bc/C/rpc
ARBITRUM_RPC_URL=https://arb1.arbitrum.io/rpc
OPTIMISM_RPC_URL=https://mainnet.optimism.io

# Private Keys (NEVER commit these!)
DEPLOYER_PRIVATE_KEY=0x...
ADMIN_MULTISIG_ADDRESS=0x...

# Etherscan API Keys
ETHERSCAN_API_KEY=...
POLYGONSCAN_API_KEY=...
SNOWTRACE_API_KEY=...
```

---

## Hardhat Configuration

```javascript
// hardhat.config.js
require("@nomicfoundation/hardhat-toolbox");
require("@openzeppelin/hardhat-upgrades");
require("dotenv").config();

module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    ethereum: {
      url: process.env.ETHEREUM_RPC_URL,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      chainId: 1
    },
    polygon: {
      url: process.env.POLYGON_RPC_URL,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      chainId: 137
    },
    avalanche: {
      url: process.env.AVALANCHE_RPC_URL,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      chainId: 43114
    },
    arbitrum: {
      url: process.env.ARBITRUM_RPC_URL,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      chainId: 42161
    },
    optimism: {
      url: process.env.OPTIMISM_RPC_URL,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      chainId: 10
    },
    // Testnets
    sepolia: {
      url: process.env.SEPOLIA_RPC_URL,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      chainId: 11155111
    },
    mumbai: {
      url: process.env.MUMBAI_RPC_URL,
      accounts: [process.env.DEPLOYER_PRIVATE_KEY],
      chainId: 80001
    }
  },
  etherscan: {
    apiKey: {
      mainnet: process.env.ETHERSCAN_API_KEY,
      polygon: process.env.POLYGONSCAN_API_KEY,
      avalanche: process.env.SNOWTRACE_API_KEY
    }
  }
};
```

---

## Deployment Script

```javascript
// scripts/deploy-ddc.js
const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  
  console.log("Deploying DDC with account:", deployer.address);
  console.log("Account balance:", (await deployer.provider.getBalance(deployer.address)).toString());
  
  // Get admin address (use multisig in production)
  const adminAddress = process.env.ADMIN_MULTISIG_ADDRESS || deployer.address;
  
  // Deploy main contract
  const DoomsdayCoin = await ethers.getContractFactory("DoomsdayCoin");
  const ddc = await DoomsdayCoin.deploy(adminAddress);
  await ddc.waitForDeployment();
  
  const ddcAddress = await ddc.getAddress();
  console.log("DoomsdayCoin deployed to:", ddcAddress);
  
  // Initialize supported chains
  const supportedChainIds = [1, 137, 43114, 42161, 10]; // ETH, Polygon, Avalanche, Arbitrum, Optimism
  console.log("Initializing supported chains...");
  const tx = await ddc.initializeSupportedChains(supportedChainIds);
  await tx.wait();
  console.log("Supported chains initialized");
  
  // Grant initial roles (if needed)
  if (adminAddress !== deployer.address) {
    console.log("Transferring admin roles to multisig...");
    const VERIFIER_ROLE = await ddc.VERIFIER_ROLE();
    const BRIDGE_ROLE = await ddc.BRIDGE_ROLE();
    
    await ddc.grantRole(VERIFIER_ROLE, adminAddress);
    await ddc.grantRole(BRIDGE_ROLE, adminAddress);
    console.log("Roles granted to:", adminAddress);
  }
  
  // Verify contract on Etherscan
  console.log("\nWaiting for block confirmations...");
  await ddc.deploymentTransaction().wait(6);
  
  console.log("\nVerifying contract...");
  try {
    await hre.run("verify:verify", {
      address: ddcAddress,
      constructorArguments: [adminAddress],
    });
    console.log("Contract verified!");
  } catch (error) {
    console.log("Verification failed:", error.message);
  }
  
  // Output deployment info
  console.log("\n=== Deployment Complete ===");
  console.log("Network:", hre.network.name);
  console.log("Contract:", ddcAddress);
  console.log("Admin:", adminAddress);
  console.log("Deployer:", deployer.address);
  console.log("\nSave this information for multi-chain deployment!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
```

---

## Multi-Chain Deployment Strategy

### Step 1: Deploy on Ethereum (Main Chain)
```bash
npx hardhat run scripts/deploy-ddc.js --network ethereum
```

### Step 2: Deploy on Additional Chains
```bash
# Polygon
npx hardhat run scripts/deploy-ddc.js --network polygon

# Avalanche
npx hardhat run scripts/deploy-ddc.js --network avalanche

# Arbitrum
npx hardhat run scripts/deploy-ddc.js --network arbitrum

# Optimism
npx hardhat run scripts/deploy-ddc.js --network optimism
```

### Step 3: Configure Bridge Operators

For each chain, set up bridge operators that can mint/burn tokens:

```javascript
// scripts/setup-bridge.js
async function setupBridge(ddcAddress, bridgeOperatorAddress) {
  const ddc = await ethers.getContractAt("DoomsdayCoin", ddcAddress);
  const BRIDGE_ROLE = await ddc.BRIDGE_ROLE();
  
  await ddc.grantRole(BRIDGE_ROLE, bridgeOperatorAddress);
  console.log("Bridge role granted to:", bridgeOperatorAddress);
}
```

---

## Bridge Integration Options

### Option 1: LayerZero Integration
```solidity
// contracts/DDCLayerZeroBridge.sol
import "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";

contract DDCLayerZeroBridge is NonblockingLzApp {
    DoomsdayCoin public ddc;
    
    constructor(address _lzEndpoint, address _ddc) 
        NonblockingLzApp(_lzEndpoint) 
    {
        ddc = DoomsdayCoin(_ddc);
    }
    
    function sendToChain(
        uint16 _dstChainId,
        address _toAddress,
        uint256 _amount
    ) external payable {
        // Lock tokens and send message
        ddc.bridgeToChain(_amount, _dstChainId);
        
        bytes memory payload = abi.encode(_toAddress, _amount);
        _lzSend(
            _dstChainId,
            payload,
            payable(msg.sender),
            address(0),
            bytes(""),
            msg.value
        );
    }
    
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory,
        uint64,
        bytes memory _payload
    ) internal override {
        (address toAddress, uint256 amount) = abi.decode(_payload, (address, uint256));
        
        bytes32 txHash = keccak256(abi.encodePacked(_srcChainId, toAddress, amount, block.timestamp));
        ddc.bridgeFromChain(toAddress, amount, _srcChainId, txHash);
    }
}
```

### Option 2: Axelar Integration
```solidity
// contracts/DDCAxelarBridge.sol
import "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";

contract DDCAxelarBridge is AxelarExecutable {
    DoomsdayCoin public ddc;
    
    constructor(address gateway_, address ddc_) 
        AxelarExecutable(gateway_) 
    {
        ddc = DoomsdayCoin(ddc_);
    }
    
    function sendToChain(
        string calldata destinationChain,
        string calldata destinationAddress,
        uint256 amount
    ) external payable {
        ddc.bridgeToChain(amount, getChainId(destinationChain));
        
        bytes memory payload = abi.encode(msg.sender, amount);
        gateway.callContract(destinationChain, destinationAddress, payload);
    }
    
    function _execute(
        string calldata,
        string calldata,
        bytes calldata payload
    ) internal override {
        (address toAddress, uint256 amount) = abi.decode(payload, (address, uint256));
        bytes32 txHash = keccak256(abi.encodePacked(toAddress, amount, block.timestamp));
        ddc.bridgeFromChain(toAddress, amount, block.chainid, txHash);
    }
}
```

---

## Testing

```javascript
// test/DoomsdayCoin.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("DoomsdayCoin", function () {
  let ddc, admin, verifier, user1, user2;
  
  beforeEach(async function () {
    [admin, verifier, user1, user2] = await ethers.getSigners();
    
    const DDC = await ethers.getContractFactory("DoomsdayCoin");
    ddc = await DDC.deploy(admin.address);
    
    // Grant verifier role
    const VERIFIER_ROLE = await ddc.VERIFIER_ROLE();
    await ddc.grantRole(VERIFIER_ROLE, verifier.address);
    
    // Verify users
    await ddc.connect(verifier).verifyAccount(user1.address);
    await ddc.connect(verifier).verifyAccount(user2.address);
  });
  
  it("Should have correct initial state", async function () {
    expect(await ddc.totalSupply()).to.equal(ethers.parseEther("1"));
    expect(await ddc.reserve()).to.equal(ethers.parseEther("1"));
    expect(await ddc.circulatingSupply()).to.equal(0);
  });
  
  it("Should allow verified users to receive tokens", async function () {
    const amount = ethers.parseEther("0.1");
    
    const opHash = await ddc.scheduleShareRelease(user1.address, amount);
    
    // Fast forward time
    await ethers.provider.send("evm_increaseTime", [24 * 60 * 60 + 1]);
    await ethers.provider.send("evm_mine");
    
    await ddc.executeShareRelease(opHash);
    
    expect(await ddc.balanceOf(user1.address)).to.equal(amount);
  });
  
  it("Should prevent unverified transfers", async function () {
    const amount = ethers.parseEther("0.1");
    
    // Schedule and execute release
    const opHash = await ddc.scheduleShareRelease(user1.address, amount);
    await ethers.provider.send("evm_increaseTime", [24 * 60 * 60 + 1]);
    await ddc.executeShareRelease(opHash);
    
    // Try transfer from unverified address
    const [, , unverified] = await ethers.getSigners();
    await expect(
      ddc.connect(unverified).transfer(user2.address, amount)
    ).to.be.revertedWith("DDC: Account not verified");
  });
  
  it("Should seize tokens from flagged accounts", async function () {
    const amount = ethers.parseEther("0.1");
    
    // Give tokens to user1
    const opHash = await ddc.scheduleShareRelease(user1.address, amount);
    await ethers.provider.send("evm_increaseTime", [24 * 60 * 60 + 1]);
    await ddc.executeShareRelease(opHash);
    
    // Flag account
    await ddc.flagAccount(user1.address, "Corporate entity detected");
    
    expect(await ddc.balanceOf(user1.address)).to.equal(0);
    expect(await ddc.reserve()).to.equal(ethers.parseEther("1"));
  });
});
```

Run tests:
```bash
npx hardhat test
npx hardhat coverage
```

---

## Security Checklist

- [ ] Use multisig wallet for admin role (e.g., Gnosis Safe)
- [ ] Set up at least 3-of-5 multisig signers
- [ ] Complete professional audit (OpenZeppelin, Trail of Bits, etc.)
- [ ] Deploy to testnet and test thoroughly
- [ ] Set up monitoring and alerting
- [ ] Create incident response plan
- [ ] Document all admin procedures
- [ ] Set up time-locks for all critical operations
- [ ] Test bridge functionality extensively
- [ ] Verify all deployed contracts on explorers

---

## Post-Deployment Operations

### Initial Share Distribution
```javascript
// Only execute after 24-hour timelock
const recipients = [
  { address: "0x...", amount: ethers.parseEther("0.01") },
  // ... more recipients
];

for (const recipient of recipients) {
  const opHash = await ddc.scheduleShareRelease(recipient.address, recipient.amount);
  console.log(`Scheduled release for ${recipient.address}: ${opHash}`);
}
```

### Monitoring Script
```javascript
// scripts/monitor.js
async function monitorDDC(ddcAddress) {
  const ddc = await ethers.getContractAt("DoomsdayCoin", ddcAddress);
  
  const info = await ddc.getContractInfo();
  console.log("Total Supply:", ethers.formatEther(info.totalSupply_));
  console.log("Circulating:", ethers.formatEther(info.circulatingSupply_));
  console.log("Reserve:", ethers.formatEther(info.reserve_));
  console.log("Holders:", info.holderCount_.toString());
  
  // Check for expired verifications
  const holders = await ddc.getHolders();
  for (const holder of holders) {
    const isValid = await ddc.isVerificationValid(holder);
    if (!isValid) {
      console.log(`WARNING: ${holder} verification expired!`);
    }
  }
}

// Run every hour
setInterval(() => monitorDDC(process.env.DDC_ADDRESS), 60 * 60 * 1000);
```

---

## Mainnet Deployment Costs (Estimates)

| Chain | Deployment Gas | Est. Cost (USD) |
|-------|----------------|-----------------|
| Ethereum | ~3,500,000 | $70-350 |
| Polygon | ~3,500,000 | $0.50-2 |
| Avalanche | ~3,500,000 | $5-20 |
| Arbitrum | ~3,500,000 | $2-10 |
| Optimism | ~3,500,000 | $2-10 |

*Note: Costs vary with gas prices*

---

## Support & Resources

- **Documentation**: https://docs.openzeppelin.com/contracts
- **Security**: https://github.com/OpenZeppelin/openzeppelin-contracts
- **Hardhat**: https://hardhat.org/docs
- **LayerZero**: https://layerzero.gitbook.io/
- **Axelar**: https://docs.axelar.dev/

---

## License

MIT License - See LICENSE file for details