pragma circom 2.0.0;

// 引入 circomlib 中的标准组件
// EdDSA 是比 ECDSA 更适合 ZK 的签名算法，效率极高
include "./node_modules/circomlib/circuits/eddsaposeidon.circom";
include "./node_modules/circomlib/circuits/comparators.circom";

template SolvencyCheck() {
    // ==========================================
    // 1. 定义输入信号 (Signals)
    // ==========================================

    // --- Public Inputs ---
    // 链上当前的代币总发行量 (Total Supply)
    signal input totalIssuance;
    
    // 银行的公钥 (Trust Anchor)。分为 X 和 Y 两个坐标点。
    // 这代表了大家公认的"可信银行"。
    signal input bankPubKeyAx;
    signal input bankPubKeyAy;

    // --- Private Inputs (隐私数据：只有 Prover 知道，绝不上链) ---
    // 银行账户里的真实余额
    signal input bankBalance;

    // 银行对余额的数字签名 (EdDSA Signature)
    // 签名包含 R8(x,y) 和 S 三个部分
    signal input bankSigR8x;
    signal input bankSigR8y;
    signal input bankSigS;

    // ==========================================
    // 2. 逻辑一：验证银行签名 (Verify Signature)
    // ==========================================
    // 目的：证明 bankBalance 这个数字不是 Prover 瞎编的，而是银行私钥签过的。

    component sigVerifier = EdDSAPoseidonVerifier();
    
    // 开启验证器
    sigVerifier.enabled <== 1;

    // 传入公钥 (题目)
    sigVerifier.Ax <== bankPubKeyAx;
    sigVerifier.Ay <== bankPubKeyAy;

    // 传入签名 (答案)
    sigVerifier.R8x <== bankSigR8x;
    sigVerifier.R8y <== bankSigR8y;
    sigVerifier.S <== bankSigS;

    // 传入消息 (内容)
    // 这里我们直接对余额数值进行验签
    sigVerifier.M <== bankBalance;

    // *注：如果签名无效，电路会在生成 Proof 阶段直接报错崩溃。
    // 只要能生成 Proof，就说明签名一定是有效的。

    // ==========================================
    // 3. 逻辑二：偿付能力检查 (Solvency Check)
    // ==========================================
    // 目的：证明 资产 >= 负债

    // 使用 252 位比较器 (Circom 的最大安全位数，足够覆盖 uint256 范围)
    component ge = GreaterEqThan(252);

    ge.in[0] <== bankBalance;   // 资产
    ge.in[1] <== totalIssuance; // 负债

    // 强制约束：比较结果必须为 1 (True)
    // 如果余额 < 发行量，这里会是 0，导致电路约束失败
    ge.out === 1;
}

// ==========================================
// 4. 入口定义 (Main)
// ==========================================
// 定义哪些输入是 Public 的。
// 这一点至关重要！Verifier 合约会读取链上数据来填充这三个参数。
component main {public [totalIssuance, bankPubKeyAx, bankPubKeyAy]} = SolvencyCheck();