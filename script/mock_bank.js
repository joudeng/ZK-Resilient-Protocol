const { buildEddsa, buildPoseidon } = require("circomlibjs");
const fs = require("fs");
const path = require("path");

async function generateBankData() {
    const eddsa = await buildEddsa();
    const poseidon = await buildPoseidon();

    console.log("🏦 [Mock Bank] Generating daily asset snapshot...");

    // 1. 银行私钥 (硬编码用于演示，生产环境必须保密)
    // 这是一个 32 字节的十六进制字符串
    const bankPrvKey = Buffer.from("0001020304050607080900010203040506070809000102030405060708090001", "hex");
    const bankPubKey = eddsa.prv2pub(bankPrvKey);

    // 2. 模拟当前的法币余额
    // 假设：银行里有 1,500,000 美元 (足够覆盖 100万的发行量)
    const balance = BigInt(1500000); 

    // 3. 对余额进行签名 (Message = Poseidon(Balance))
    // 注意：电路里我们是直接对数值签名的
    const msgHash = poseidon([balance]);
    const signature = eddsa.signPoseidon(bankPrvKey, msgHash);

    // 4. 格式化输出 (适配 snarkjs 输入格式)
    const input = {
        bankPubKeyAx: eddsa.F.toObject(bankPubKey[0]).toString(),
        bankPubKeyAy: eddsa.F.toObject(bankPubKey[1]).toString(),
        bankBalance: balance.toString(),
        bankSigR8x: eddsa.F.toObject(signature.R8[0]).toString(),
        bankSigR8y: eddsa.F.toObject(signature.R8[1]).toString(),
        bankSigS: signature.S.toString()
    };

    // 保存到文件
    const outputPath = path.join(__dirname, "../circuits/bank_input.json");
    fs.writeFileSync(outputPath, JSON.stringify(input, null, 2));
    
    console.log(`✅ Bank Snapshot Saved to ${outputPath}`);
    console.log(`   Balance: $${balance}`);
    return input;
}

// 允许直接运行或被其他脚本调用
if (require.main === module) {
    generateBankData();
}

module.exports = { generateBankData };