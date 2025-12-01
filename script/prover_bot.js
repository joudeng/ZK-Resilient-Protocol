const snarkjs = require("snarkjs");
const fs = require("fs");
const { ethers } = require("ethers");
const { generateBankData } = require("./mock_bank");
const { fetchSnapshot } = require("./fetch_snapshot");
const { buildTree } = require("./build_liability_tree");

// 合约配置
const CONTROLLER_ADDRESS = "0x..."; // 填入部署的 ComplianceController 地址
const CONTROLLER_ABI = [
    "function submitAudit(uint256[2] a, uint256[2][2] b, uint256[2] c, bytes32 _rootHash, uint256 _totalLiabilities) public"
];
// 提交者的私钥 (Relayer)
const RELAYER_PRIVATE_KEY = "0x..."; 

async function runBot() {
    console.log("🤖 [Prover Bot] Starting audit cycle...");

    // Step 1: 准备数据
    await fetchSnapshot(); // 获取链上数据
    const treeData = await buildTree(); // 算树
    const bankData = await generateBankData(); // 银行签名

    // Step 2: 构造电路输入
    // 必须包含 Public Inputs (totalIssuance) 和 Private Inputs
    const circuitInput = {
        ...bankData, // 包含 bankBalance, bankSig 等
        totalIssuance: treeData.rootSum // 这里的 rootSum 就是 totalSupply
    };

    fs.writeFileSync("./circuits/input.json", JSON.stringify(circuitInput, null, 2));

    // Step 3: 生成 ZK Proof
    console.log("⚡ [ZK] Generating Proof...");
    const { proof, publicSignals } = await snarkjs.groth16.fullProve(
        circuitInput,
        "./circuits/solvency.wasm",
        "./circuits/solvency_final.zkey"
    );

    // Step 4: 格式化参数 (适配 Solidity)
    // SnarkJS 输出的是字符串，Solidity 需要 uint256
    const pA = [proof.pi_a[0], proof.pi_a[1]];
    const pB = [[proof.pi_b[0][1], proof.pi_b[0][0]], [proof.pi_b[1][1], proof.pi_b[1][0]]];
    const pC = [proof.pi_c[0], proof.pi_c[1]];
    
    // rootHash 需要转为 bytes32 格式 (hex string)
    const rootHashHex = "0x" + BigInt(treeData.rootHash).toString(16).padStart(64, '0');

    console.log("🚀 [Chain] Submitting to blockchain...");

    // Step 5: 上链
    const provider = new ethers.JsonRpcProvider("http://127.0.0.1:8545");
    const wallet = new ethers.Wallet(RELAYER_PRIVATE_KEY, provider);
    const controller = new ethers.Contract(CONTROLLER_ADDRESS, CONTROLLER_ABI, wallet);

    try {
        const tx = await controller.submitAudit(
            pA, pB, pC,
            rootHashHex,
            treeData.rootSum
        );
        console.log(`✅ Transaction sent: ${tx.hash}`);
        await tx.wait();
        console.log("🎉 Audit Submitted Successfully! System is Compliant.");
    } catch (e) {
        console.error("❌ Transaction Failed:", e.reason || e);
    }
}

runBot();