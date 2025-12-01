// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IVerifier.sol";

// 定义 Token 接口，只需要查总供应量
interface IResilientToken {
    function totalSupply() external view returns (uint256);
}

contract ComplianceController is AccessControl {
    
    // --- 角色定义 ---
    bytes32 public constant RELAYER_ROLE = keccak256("RELAYER_ROLE"); // 允许提交证明的机器人
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE"); // 允许紧急冻结的审计员

    // --- 状态机定义 ---
    enum State { Compliant, GracePeriod, Frozen }
    State public currentState;

    // --- 核心数据存储 ---
    IVerifier public verifier;       // ZK 验证器合约地址
    address public resilientToken;   // 稳定币合约地址
    
    // 银行公钥 (Trust Anchor) - 对应电路中的 bankPubKeyAx, bankPubKeyAy
    uint256[2] public bankPubKey; 

    // 负债树根 (用于用户自查)
    bytes32 public liabilityRoot;    
    
    // 风控计时器
    uint256 public lastAuditTime;    
    uint256 public constant TIMEOUT = 24 hours; // 心跳阈值

    // --- 事件 ---
    event ProofSubmitted(uint256 timestamp, bytes32 root, uint256 totalLiabilities);
    event StateChanged(State oldState, State newState);
    event VerifierUpgraded(address oldVerifier, address newVerifier);

    /**
     * @dev 构造函数
     * @param _verifierAddress ZK Verifier 合约地址
     * @param _admin 初始管理员地址
     * @param _pubKeyAx 银行公钥 X 坐标
     * @param _pubKeyAy 银行公钥 Y 坐标
     */
    constructor(
        address _verifierAddress, 
        address _admin,
        uint256 _pubKeyAx,
        uint256 _pubKeyAy
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(AUDITOR_ROLE, _admin);
        _grantRole(RELAYER_ROLE, _admin); // 测试方便，管理员也可以提交证明

        verifier = IVerifier(_verifierAddress);
        bankPubKey[0] = _pubKeyAx;
        bankPubKey[1] = _pubKeyAy;

        currentState = State.Compliant;
        lastAuditTime = block.timestamp;
    }

    // 设置 Token 地址 (部署顺序：Verifier -> Controller -> Token -> SetToken)
    function setToken(address _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        resilientToken = _token;
    }

    /**
     * @dev 核心功能：提交审计 (由 Prover Node 机器人调用)
     * @param a/b/c ZK Proof 的三个部分 (由 SnarkJS 生成)
     * @param _rootHash Merkle Sum Tree 的根哈希
     * @param _totalLiabilities 树根中记录的总负债金额
     */
    function submitAudit(
        uint[2] memory a,
        uint[2][2] memory b,
        uint[2] memory c,
        bytes32 _rootHash,
        uint256 _totalLiabilities
    ) public onlyRole(RELAYER_ROLE) {
        
        // --- 1. 负债端验证 (Liability Check) ---
        uint256 currentSupply = IResilientToken(resilientToken).totalSupply();
        require(_totalLiabilities == currentSupply, "Liability Mismatch: Tree Sum != Total Supply");

        // --- 2. 构造 ZK 公开输入 (Public Signals) ---
        uint[3] memory input;
        input[0] = currentSupply;   // 动态数据：链上发行量
        input[1] = bankPubKey[0];   // 静态锚点：银行公钥 X
        input[2] = bankPubKey[1];   // 静态锚点：银行公钥 Y

        // --- 3. 调用 Verifier 进行数学验证 ---
        // 验证：银行余额 >= currentSupply 且 签名有效
        bool result = verifier.verifyProof(a, b, c, input);
        require(result, "ZK Proof Invalid: Insolvency or Bad Signature");

        // --- 4. 状态更新与自愈 ---
        liabilityRoot = _rootHash;
        lastAuditTime = block.timestamp;

        if (currentState != State.Compliant || currentState != State.Frozen) {
            _switchState(State.Compliant);
        }

        emit ProofSubmitted(block.timestamp, _rootHash, _totalLiabilities);
    }

    /**
     * @dev 心跳检测 (Liveness Check)
     */
    function checkLiveness() external onlyRole(AUDITOR_ROLE) {
        if (block.timestamp > lastAuditTime + TIMEOUT && currentState == State.Compliant) {
            _switchState(State.GracePeriod);
        }
    }

    /**
     * @dev 紧急冻结 (Hard Freeze)
     * 只有审计员可以调用。用于应对严重安全事故。
     */
    function emergencyFreeze() external onlyRole(AUDITOR_ROLE) {
        _switchState(State.Frozen);
    }

    /**
     * @dev 升级验证器 (把关人逻辑)
     */
    function upgradeVerifier(address _newVerifier) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newVerifier != address(0), "Invalid address");
        emit VerifierUpgraded(address(verifier), _newVerifier);
        verifier = IVerifier(_newVerifier);
    }

    /**
     * @dev 供 Token 合约查询的状态接口
     */
    function isTransferAllowed() external view returns (bool) {
        return currentState == State.Compliant;
    }

    // --- 内部辅助函数 ---
    function _switchState(State _newState) internal {
        emit StateChanged(currentState, _newState);
        currentState = _newState;
    }
}