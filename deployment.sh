# 1. Set founder addresses in .env
FOUNDER_1_ADDRESS=0x...
FOUNDER_2_ADDRESS=0x...
FOUNDER_3_ADDRESS=0x...

# 2. Deploy contract
npx hardhat run doomsday_coin.sol --network ethereum

# 3. Founders wait 6 months, then claim anytime
await ddc.claimFounderTokens();
