const { ethers } = require("ethers");
const fs = require("fs");
const path = require("path");

// ================= 配置区域 =================
// 1. 你的 Token 合约地址 (请在部署后填入真实的)
const TOKEN_ADDRESS = "0xYourTokenAddressHere"; 

// 2. 合约部署时的起始区块 (优化扫描速度，不用从 block 0 开始扫)
// 如果是本地 Hardhat 网络，填 0 即可；如果是 Sepolia，填部署时的区块号
const DEPLOYMENT_BLOCK = 0; 

// 3. RPC 节点 (本地用 localhost，测试网用 Alchemy/Infura)
const RPC_URL = "http://127.0.0.1:8545"; 
// ===========================================

const TOKEN_ABI = [
    "function totalSupply() view returns (uint256)",
    "function balanceOf(address) view returns (uint256)",
    "event Transfer(address indexed from, address indexed to, uint256 value)"
];

async function fetchSnapshot() {
    console.log("📸 [Snapshot] Starting real on-chain data fetch...");
    
    // 连接节点
    const provider = new ethers.JsonRpcProvider(RPC_URL);
    const tokenContract = new ethers.Contract(TOKEN_ADDRESS, TOKEN_ABI, provider);

    // 1. 确定快照高度 (使用当前最新区块)
    const currentBlock = await provider.getBlockNumber();
    console.log(`   Target Block Height: ${currentBlock}`);

    // 2. 获取总供应量 (作为这一时刻的宏观锚点)
    const totalSupply = await tokenContract.totalSupply({ blockTag: currentBlock });
    console.log(`   On-chain Total Supply: ${ethers.formatEther(totalSupply)} rUSD`);

    if (totalSupply === 0n) {
        console.log("⚠️  Total Supply is 0. Please mint some tokens first!");
        return;
    }

    // 3. 扫描历史事件，发现所有持币人 (Discovery)
    console.log("   🔍 Scanning Transfer events to find holders...");
    
    // queryFilter(Event, fromBlock, toBlock)
    // 注意：如果由 Infura 等节点限制，这里可能需要分段查询 (Pagination)，这里简化为一次查完
    const logs = await tokenContract.queryFilter("Transfer", DEPLOYMENT_BLOCK, currentBlock);
    
    // 使用 Set 去重，收集所有出现过的地址
    const candidateAddresses = new Set();
    
    logs.forEach(log => {
        const { from, to } = log.args;
        // 排除 0x0 地址 (Mint 的发送方 / Burn 的接收方)
        if (from !== ethers.ZeroAddress) candidateAddresses.add(from);
        if (to !== ethers.ZeroAddress) candidateAddresses.add(to);
    });

    console.log(`   Found ${candidateAddresses.size} unique addresses interacting with the token.`);

    // 4. 逐个查询真实余额 (Fetching Balances)
    console.log("   💰 Fetching balances for each address at snapshot block...");
    
    const holders = [];
    let calculatedTotalSupply = 0n;

    for (const address of candidateAddresses) {
        // 关键点：加上 { blockTag: currentBlock } 确保是“那个瞬间”的余额
        const balance = await tokenContract.balanceOf(address, { blockTag: currentBlock });
        
        // 只记录有钱的用户 (余额 > 0)
        if (balance > 0n) {
            holders.push({
                address: address,
                balance: balance.toString() // 转字符串存 JSON
            });
            calculatedTotalSupply += balance;
            // 打印进度 (可选)
            // console.log(`      - ${address}: ${ethers.formatEther(balance)}`);
        }
    }

    // 5. 最终核对 (Sanity Check)
    console.log("   ⚖️  Verifying data integrity...");
    console.log(`      Calculated Sum: ${ethers.formatEther(calculatedTotalSupply)}`);
    console.log(`      Actual Supply : ${ethers.formatEther(totalSupply)}`);

    if (calculatedTotalSupply !== totalSupply) {
        console.error("❌ CRITICAL ERROR: Snapshot sum does not match on-chain total supply!");
        console.error("   Reason: Maybe missed some transfers or block reorg.");
    } else {
        console.log("✅ Data Match! Integrity Verified.");
    }

    // 6. 保存快照文件
    const snapshotData = {
        blockNumber: currentBlock,
        totalSupply: totalSupply.toString(),
        timestamp: Math.floor(Date.now() / 1000),
        users: holders
    };

    const outputPath = path.join(__dirname, "data/snapshot.json");
    // 确保目录存在
    if (!fs.existsSync(path.dirname(outputPath))) {
        fs.mkdirSync(path.dirname(outputPath), { recursive: true });
    }
    
    fs.writeFileSync(outputPath, JSON.stringify(snapshotData, null, 2));
    console.log(`📂 Snapshot saved to: ${outputPath}`);
    console.log(`   Total Holders: ${holders.length}`);
}

// 执行
if (require.main === module) {
    fetchSnapshot()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error(error);
            process.exit(1);
        });
}

module.exports = { fetchSnapshot };