const { buildPoseidon } = require("circomlibjs");
const fs = require("fs");

async function buildTree() {
    const poseidon = await buildPoseidon();
    const snapshot = JSON.parse(fs.readFileSync("./scripts/data/snapshot.json"));
    
    console.log("🌳 [Merkle Tree] Building Liability Sum Tree...");

    // 1. 准备叶子节点
    // Leaf = Poseidon(Address, Balance)
    // Node = { hash, sum }
    let leaves = snapshot.users.map(user => {
        const balanceBigInt = BigInt(user.balance);
        const addressBigInt = BigInt(user.address); // 地址转数值
        const hash = poseidon([addressBigInt, balanceBigInt]);
        return {
            hash: poseidon.F.toString(hash),
            sum: balanceBigInt
        };
    });

    // 2. 递归构建树
    let levels = [leaves];
    let currentLevel = leaves;

    while (currentLevel.length > 1) {
        let nextLevel = [];
        for (let i = 0; i < currentLevel.length; i += 2) {
            const left = currentLevel[i];
            const right = (i + 1 < currentLevel.length) ? currentLevel[i + 1] : { hash: 0, sum: 0n }; // 补零

            // Parent Hash = Poseidon(LeftHash, LeftSum, RightHash, RightSum)
            const parentSum = left.sum + right.sum;
            const parentHash = poseidon([
                left.hash, left.sum,
                right.hash, right.sum
            ]);

            nextLevel.push({
                hash: poseidon.F.toString(parentHash),
                sum: parentSum
            });
        }
        currentLevel = nextLevel;
        levels.push(currentLevel);
    }

    const root = currentLevel[0];
    
    // 3. 校验
    if (root.sum.toString() !== snapshot.totalSupply) {
        throw new Error(`❌ Mismatch! Tree Sum: ${root.sum}, Chain Supply: ${snapshot.totalSupply}`);
    }

    // 4. 导出数据
    const output = {
        rootHash: root.hash,
        rootSum: root.sum.toString(),
        snapshotBlock: snapshot.blockNumber
    };

    fs.writeFileSync("./scripts/data/merkle_root.json", JSON.stringify(output, null, 2));
    
    // *这里还可以导出 user_proofs.json 供前端使用，代码略*
    
    console.log(`✅ Tree Built. Root Hash: ${root.hash.slice(0, 10)}...`);
    return output;
}

if (require.main === module) {
    buildTree();
}

module.exports = { buildTree };