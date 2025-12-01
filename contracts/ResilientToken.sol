// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IKYCProvider.sol"; 

// 定义控制器接口
interface IController {
    function isTransferAllowed() external view returns (bool);
}

contract ResilientToken is ERC20, ERC20Burnable, AccessControl {
    
    // --- 角色定义 ---
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    // DEFAULT_ADMIN_ROLE (内置) 将拥有升级合约架构的最高权限

    // --- 核心模块指针 ---
    address public controller;      // 风控大脑 (Compliance Controller)
    IKYCProvider public kycProvider; // 合规接口 (ZK-KYC)
    
    // --- 经济模型变量 ---
    address public treasury;        // 国库地址
    uint256 public mintFeeRate;     // 费率 (基点 100 = 1%)
    uint256 public constant BPS = 10000;

    // --- 事件 (用于链上审计) ---
    event ControllerUpdated(address indexed oldController, address indexed newController);
    event KYCProviderUpdated(address indexed oldProvider, address indexed newProvider);
    event FeeConfigUpdated(address treasury, uint256 feeRate);
    event FeeCollected(address indexed user, uint256 feeAmount);

    constructor(
        address _controller, 
        address _admin, 
        address _kycProvider,
        address _treasury
    ) ERC20("Resilient USD", "rUSD") {
        require(_controller != address(0), "Invalid controller");
        require(_treasury != address(0), "Invalid treasury");
        require(_admin != address(0), "Invalid admin");

        // 初始化变量
        controller = _controller;
        kycProvider = IKYCProvider(_kycProvider);
        treasury = _treasury;
        mintFeeRate = 10; // 默认 0.1%

        // 设置权限
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(MINTER_ROLE, _admin);
        _grantRole(FEE_MANAGER_ROLE, _admin);
    }

    // ==========================================
    // 1. 架构升级功能 (之前缺失的部分)
    // ==========================================

    /**
     * @dev 更换风控控制器
     * 场景: 状态机逻辑升级，或控制器合约被替换
     */
    function setController(address _newController) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newController != address(0), "Invalid address");
        emit ControllerUpdated(controller, _newController);
        controller = _newController;
    }

    /**
     * @dev 更换 KYC 提供商
     * 场景: 从 Mock 切换到真实 WorldID，或更换合规标准
     */
    function setKYCProvider(address _newProvider) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newProvider != address(0), "Invalid address");
        emit KYCProviderUpdated(address(kycProvider), _newProvider);
        kycProvider = IKYCProvider(_newProvider);
    }

    // ==========================================
    // 2. 经济模型配置
    // ==========================================

    /**
     * @dev 调整费率和国库地址
     */
    function setFeeConfig(address _treasury, uint256 _feeRate) external onlyRole(FEE_MANAGER_ROLE) {
        require(_treasury != address(0), "Invalid treasury");
        require(_feeRate <= 1000, "Fee cap exceeded");
        treasury = _treasury;
        mintFeeRate = _feeRate;
        emit FeeConfigUpdated(_treasury, _feeRate);
    }

    // ==========================================
    // 3. 业务逻辑 (铸造与拦截)
    // ==========================================

    /**
     * @dev 带手续费的铸造
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        uint256 fee = (amount * mintFeeRate) / BPS;
        uint256 actualAmount = amount - fee;

        // 给用户发币 (会触发 _update 检查)
        _mint(to, actualAmount);

        if (fee > 0) {
            _mint(treasury, fee);
            emit FeeCollected(to, fee);
        }
    }

    /**
     * @dev 核心钩子：集成风控状态机 + ZK-KYC
     * 修正逻辑：Mint 和 Transfer 受状态机限制，但 Burn (赎回) 永远开放
     */
    function _update(address from, address to, uint256 value) internal override {
        // 1. 获取系统健康状态 (Green/Red)
        bool isSystemHealthy = IController(controller).isTransferAllowed();

        // 2. 根据操作类型分流逻辑
        
        if (from == address(0)) {
            // Case A: 铸造 (Mint) -> [严管]
            // 必须系统健康。如果资不抵债(Frozen)，绝对禁止印钞。
            require(isSystemHealthy, "Mint Paused: System Frozen");
        } 
        else if (to == address(0)) {
            // Case B: 销毁/赎回 (Burn) -> [永远开放]
            // 唯一限制：赎回者必须通过 KYC (防止黑客洗钱后销毁)
            require(kycProvider.isCompliant(from), "Redeemer Not KYCed");
        } 
        else {
            // Case C: 普通转账 (Transfer) -> [严管]
            // 必须系统健康，且双方合规
            
            // 1. 风控熔断检查
            require(isSystemHealthy, "Transfer Frozen: Risk Control Triggered");

            // 2. KYC 检查 (排除国库地址)
            if (from != treasury && to != treasury) {
                require(kycProvider.isCompliant(from), "Sender KYC Failed");
                require(kycProvider.isCompliant(to), "Receiver KYC Failed");
            }
        }

        // 3. 执行底层记账
        super._update(from, to, value);
    }
}