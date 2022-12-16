// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../interface/IStakingReward.sol";
import "../interface/IEXOToken.sol";
import "../interface/IGCREDToken.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract StakingReward is Initializable, IStakingReward, PausableUpgradeable, AccessControlUpgradeable {
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant EXO_ROLE = keccak256("EXO_ROLE");

    uint256 public constant MAX_REWRAD = 35e26;
    uint256 public totalRewardAmount;
    // EXO token address
    address public EXO_ADDRESS;
    // GCRED token address
    address public GCRED_ADDRESS;
    // Foundation Node wallet which is releasing EXO to prevent inflation
    address public FOUNDATION_NODE;
    // Reward amount from FN wallet
    uint256 public FN_REWARD;
    // All staking infors
    mapping(address => StakingInfo[]) private _stakingInfos;
    // Holder counter in each tier
    uint256[16] private _interestHolderCounter;
    // Tier of the user; Tier 0 ~ 3
    mapping(address => uint8) public tier;
    // Whether holder can upgrade tier status
    mapping(address => bool) public tierCandidate;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _EXO_ADDRESS, address _GCRED_ADDRESS) public initializer {
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OWNER_ROLE, msg.sender);
        _grantRole(EXO_ROLE, _EXO_ADDRESS);

        EXO_ADDRESS = _EXO_ADDRESS;
        GCRED_ADDRESS = _GCRED_ADDRESS;
    }

    /// @inheritdoc	IStakingReward
    function stake(uint256 _amount, uint8 _duration) external override whenNotPaused {
        address holder = _msgSender();
        require(_amount <= IERC20Upgradeable(EXO_ADDRESS).balanceOf(holder), "StakingReward: Not enough EXO token to stake");
        require(_duration < 4, "StakingReward: Duration does not match");

        uint8 interestRate = tier[holder] * 4 + _duration;

        if (holder == FOUNDATION_NODE) {
            // Calculate reward amount from Foudation Node wallet
            FN_REWARD = (IERC20Upgradeable(EXO_ADDRESS).balanceOf(FOUNDATION_NODE) * 75) / 1000 / 365;
        } else {
            uint88[4] memory minAmount = getTierMinAmount();
            uint24[4] memory period = _getStakingPeriod();

            _stakingInfos[holder].push(
                StakingInfo(holder, _amount, block.timestamp, block.timestamp + uint256(period[_duration]), _duration, 0, interestRate)
            );

            _interestHolderCounter[interestRate]++;

            // Check user can upgrade tier
            if (tier[holder] < 3 && _amount >= uint256(minAmount[tier[holder] + 1]) && _duration > tier[holder])
                tierCandidate[holder] = true;
        }

        IERC20Upgradeable(EXO_ADDRESS).transferFrom(holder, address(this), _amount);
        emit Stake(holder, _amount, interestRate);
    }

    function unstake(uint256 _stakingIndex) external whenNotPaused {
        address holder = _msgSender();
        require(_stakingInfos[holder].length > _stakingIndex, "StakingReward: Invalid staking index");

        StakingInfo memory targetStaking = _stakingInfos[holder][_stakingIndex];
        // Unstake only soft lock or expired staking
        require(block.timestamp > targetStaking.expireDate || targetStaking.interestRate % 4 == 0, "StakingReward: Cannot unstake");

        // Last Claim
        claim(_stakingIndex);

        /* The staking date is expired */
        // Upgrade holder's tier
        if (targetStaking.duration >= tier[holder] && tierCandidate[holder]) {
            if (tier[holder] < 3) {
                tier[holder] += 1;
            }
            tierCandidate[holder] = false;
        }
        _interestHolderCounter[targetStaking.interestRate]--;

        _stakingInfos[holder][_stakingIndex] = _stakingInfos[holder][_stakingInfos[holder].length - 1];
        _stakingInfos[holder].pop();

        // Return staked EXO to holder
        IERC20Upgradeable(EXO_ADDRESS).transfer(holder, targetStaking.amount);
        emit Unstake(holder, targetStaking.amount, targetStaking.interestRate);
    }

    /// @inheritdoc IStakingReward
    function setEXOAddress(address _EXO_ADDRESS) external override onlyRole(OWNER_ROLE) {
        EXO_ADDRESS = _EXO_ADDRESS;

        emit EXOAddressUpdated(EXO_ADDRESS);
    }

    /// @inheritdoc IStakingReward
    function setGCREDAddress(address _GCRED_ADDRESS) external override onlyRole(OWNER_ROLE) {
        GCRED_ADDRESS = _GCRED_ADDRESS;

        emit GCREDAddressUpdated(GCRED_ADDRESS);
    }

    function setFNAddress(address _FOUNDATION_NODE) external override onlyRole(OWNER_ROLE) {
        FOUNDATION_NODE = _FOUNDATION_NODE;

        emit FoundationNodeUpdated(FOUNDATION_NODE);
    }

    function setTier(address _holder, uint8 _tier) external override onlyRole(EXO_ROLE) {
        tier[_holder] = _tier;
    }

    function pause() external onlyRole(OWNER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(OWNER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IStakingReward
    function getTier(address _holder) external view returns (uint8) {
        return tier[_holder];
    }

    /// @inheritdoc IStakingReward
    function getStakingInfos(address _holder) external view returns (StakingInfo[] memory) {
        return _stakingInfos[_holder];
    }

    function getTotalStakedAmount(address _holder) external view returns (uint256) {
        StakingInfo[] memory stakings = _stakingInfos[_holder];
        uint256 totalStakedAmount = 0;
        for (uint256 i = 0; i < stakings.length; i++) {
            totalStakedAmount += stakings[i].amount;
        }
        return totalStakedAmount;
    }

    function claim(uint256 _stakingIndex) public whenNotPaused {
        address holder = _msgSender();
        require(_stakingInfos[holder].length > _stakingIndex, "StakingReward: Invalid staking index");

        StakingInfo memory targetStaking = _stakingInfos[holder][_stakingIndex];

        /* ---- Claim reward ----*/
        uint256 curDate = block.timestamp >= targetStaking.expireDate ? targetStaking.expireDate : block.timestamp;
        uint256 stakedDays = (curDate - targetStaking.startDate) / 1 days;

        if (stakedDays > targetStaking.claimedDays) {
            uint8 rewardDays = uint8(stakedDays - targetStaking.claimedDays);
            // Calculate reward EXO amount
            uint256 REWARD_APR = _getEXORewardAPR(targetStaking.interestRate);
            uint256 reward = _calcReward(targetStaking.amount, REWARD_APR, rewardDays);
            totalRewardAmount += reward;
            // Mint reward to targetStaking holder
            IEXOToken(EXO_ADDRESS).mint(holder, reward);

            // Calculate GCRED daily reward
            uint256 GCRED_REWARD = (targetStaking.amount * _getGCREDReturn(targetStaking.interestRate) * rewardDays) / 1e6;
            // send GCRED to holder
            _sendGCRED(holder, GCRED_REWARD);

            // Update claimed days
            _stakingInfos[holder][_stakingIndex].claimedDays += rewardDays;
            emit Claim(holder, reward, targetStaking.interestRate);

            _getRewardFromFN(targetStaking.interestRate, rewardDays);
        }
    }

    /// @dev Minimum EXO amount in tier
    function getTierMinAmount() public pure override returns (uint88[4] memory) {
        uint88[4] memory tierMinimumAmount = [
            0,
            2_0000_0000_0000_0000_0000_0000,
            4_0000_0000_0000_0000_0000_0000,
            8_0000_0000_0000_0000_0000_0000
        ];
        return tierMinimumAmount;
    }

    function _getRewardFromFN(uint8 _interestRate, uint256 _rewardDays) internal {
        address holder = _msgSender();
        uint8[16] memory FN_REWARD_PERCENT = _getFNRewardPercent();
        uint256 _rewardAmountFN;
        // Calculate daily FN reward
        if (_interestHolderCounter[_interestRate] == 0) {
            _rewardAmountFN = 0;
        } else {
            _rewardAmountFN = (FN_REWARD * uint256(FN_REWARD_PERCENT[_interestRate])) / _interestHolderCounter[_interestRate] / 1000;
        }

        uint256 _rewardAmount = _rewardAmountFN * _rewardDays;
        totalRewardAmount += _rewardAmount;
        if (_rewardAmount != 0) {
            IEXOToken(EXO_ADDRESS).mint(holder, _rewardAmount);
            emit ClaimFN(holder, _rewardAmount);
        }
    }

    /// @dev Staking period
    function _getStakingPeriod() internal pure returns (uint24[4] memory) {
        uint24[4] memory stakingPeriod = [0, 30 days, 60 days, 90 days];
        return stakingPeriod;
    }

    /// @dev EXO Staking reward APR
    function _getEXORewardAPR(uint8 _interestRate) internal pure returns (uint8) {
        uint8[16] memory EXO_REWARD_APR = [50, 55, 60, 65, 60, 65, 70, 75, 60, 65, 70, 75, 60, 65, 70, 75];
        return EXO_REWARD_APR[_interestRate];
    }

    /// @dev Foundation Node Reward Percent Array
    function _getFNRewardPercent() internal pure returns (uint8[16] memory) {
        uint8[16] memory FN_REWARD_PERCENT = [0, 0, 0, 0, 30, 60, 85, 115, 40, 70, 95, 125, 50, 80, 105, 145];
        return FN_REWARD_PERCENT;
    }

    /// @dev GCRED reward per day
    function _getGCREDReturn(uint8 _interest) internal pure returns (uint16) {
        uint16[16] memory GCRED_RETURN = [0, 0, 0, 242, 0, 0, 266, 354, 0, 0, 293, 390, 0, 0, 322, 426];
        return GCRED_RETURN[_interest];
    }

    function _sendGCRED(address _address, uint256 _amount) internal {
        IGCREDToken(GCRED_ADDRESS).mintForReward(_address, _amount);

        emit ClaimGCRED(_address, _amount);
    }

    function _calcReward(
        uint256 _amount,
        uint256 _percent,
        uint8 _days
    ) internal pure returns (uint256) {
        return ((_amount * _percent) * _days) / 365000;
    }
}
