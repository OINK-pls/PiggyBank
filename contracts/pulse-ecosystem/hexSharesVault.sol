// SPDX-License-Identifier: NONE

pragma solidity 0.8.1;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/utils/Address.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.4.0/contracts/security/ReentrancyGuard.sol";


import "../interface/IGovernor.sol";
import "../interface/IMasterChef.sol";
import "../interface/IacPool.sol";
import "../interface/IVoting.sol";

interface ILookup {
	function stakeCount(address _staker) external view returns (uint256);
	function stakeLists(address, uint256) external view returns (uint40,uint72,uint72,uint16,uint16,uint16,bool);
}

/**
 * tshare Vault
 * !!! Warning: !!! Licensed under Business Source License 1.1 (BSL 1.1)
 */
contract tshareVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
		uint256 debt;
    }

    struct PoolPayout {
        uint256 amount;
        uint256 minServe;
    }
	
    IERC20 public immutable token; // DTX token
	
	ILookup public immutable hexC = ILookup(0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39);
    
    IERC20 public immutable dummyToken; 

    IMasterChef public masterchef;  

    mapping(address => UserInfo) public userInfo;
    mapping(address => PoolPayout) public poolPayout; //determines the percentage received depending on withdrawal option
 
	uint256 public poolID; 
	uint256 public accDtxPerShare;
    address public admin; //admin = governing contract!
    address public treasury; //penalties
	uint256 public totalTshares = 1e8; // Negligible share to avoid division by 0 on first deposit. 
	
	uint256 public maxStakes = 150;

    uint256 public defaultDirectPayout = 500; //5% if withdrawn into wallet
	

    event Deposit(address indexed sender, uint256 amount, uint256 debt);
    event Withdraw(address indexed sender, uint256 harvestAmount, uint256 penalty);
    event UserSettingUpdate(address indexed user, address poolAddress, uint256 threshold, uint256 feeToPay);

    event Harvest(address indexed user, address harvestInto, uint256 harvestAmount, uint256 penalty);

    /**
     * @notice Constructor
     * @param _token: DTX token contract
     * @param _dummyToken: Dummy token contract
     * @param _masterchef: MasterChef contract
     * @param _admin: address of the admin
     * @param _treasury: address of the treasury (collects fees)
     */
    constructor(
        IERC20 _token,
        IERC20 _dummyToken,
        IMasterChef _masterchef,
        address _admin,
        address _treasury,
        uint256 _poolID
    ) {
        token = _token;
        dummyToken = _dummyToken;
        masterchef = _masterchef;
        admin = _admin;
        treasury = _treasury;
        poolID = _poolID;

        IERC20(_dummyToken).safeApprove(address(_masterchef), type(uint256).max);
		poolPayout[0x32b33C2Eb712D172e389811d5621031688Fa4c13].amount = 750;
        poolPayout[0x32b33C2Eb712D172e389811d5621031688Fa4c13].minServe = 864000;

        poolPayout[0x8C0471539F226453598090dAd4333F3D7E34Afb4].amount = 1500;
        poolPayout[0x8C0471539F226453598090dAd4333F3D7E34Afb4].minServe = 2592000;

        poolPayout[0xC251392b5A5D3f0721027015D1d1234d630c8688].amount = 2500;
        poolPayout[0xC251392b5A5D3f0721027015D1d1234d630c8688].minServe = 5184000;

        poolPayout[0x7B0939A38EDc3bfDB674F4160e08A3Abed733305].amount = 5000;
        poolPayout[0x7B0939A38EDc3bfDB674F4160e08A3Abed733305].minServe = 8640000;

        poolPayout[0x2694BaB21281Bf743536754C562b8d3AA99DF80c].amount = 7000;
        poolPayout[0x2694BaB21281Bf743536754C562b8d3AA99DF80c].minServe = 20736000;

        poolPayout[0x908C35aa2CFF22e8234990344C129AD2fD365A0F].amount = 10000;
        poolPayout[0x908C35aa2CFF22e8234990344C129AD2fD365A0F].minServe = 31536000; 
    }
    
    /**
     * @notice Checks if the msg.sender is the admin
     */
    modifier adminOnly() {
        require(msg.sender == admin, "admin: wut?");
        _;
    }

	
    /**
     * Creates a NEW stake
     * _poolInto is the pool to harvest into(time deposit option)
	 * threshold is the amount to allow another user to harvest 
	 * fee is the amount paid to harvester
     */
    function stakeHexShares(address _poolInto, uint256 _threshold, uint256 _fee) external nonReentrant {
		UserInfo storage user = userInfo[msg.sender];
		require(user.amount == 0, "already have an active stake!");
        harvest();
		
		uint256 nrOfStakes = hexC.stakeCount(msg.sender);
		require(nrOfStakes > 0, "no stakes");
		uint256 _shares;
        uint256 _amount = 0;
		for(uint256 i=0; i<nrOfStakes; i++) {
			(, , _shares, , , ,) = hexC.stakeLists(msg.sender, i);
			_amount+= _shares;
		}
		uint256 _debt = _amount * accDtxPerShare / 1e12;
		totalTshares+= _amount;
        
		user.amount = _amount;
		user.debt = _debt;

        emit Deposit(msg.sender, _amount, _debt);
    }
	
    /**
     * Harvests into pool
     */
    function harvest() public {
		uint256 _pending = IMasterChef(masterchef).pendingDtx(poolID, address(this));
        IMasterChef(masterchef).withdraw(poolID, 0);
		accDtxPerShare+= _pending * 1e12  / totalTshares;
    }

    /**
    *
    */
    function setAdmin() external {
        admin = IMasterChef(masterchef).owner();
        treasury = IMasterChef(masterchef).feeAddress();
    }

    /**
     * Withdraws all tokens
     */
    function withdraw(address _harvestInto) public nonReentrant {
        harvest();
        UserInfo storage user = userInfo[msg.sender];
		uint256 userTokens = user.amount; 
		require(userTokens > 0, "no active stake");

		uint256 currentAmount = userTokens * accDtxPerShare / 1e12 - user.debt;
		totalTshares-= userTokens;
		
		user.amount = 0;
		user.debt = 0;

        uint256 _toWithdraw;      

        if(_harvestInto == msg.sender) { 
            _toWithdraw = currentAmount * defaultDirectPayout / 10000;
            currentAmount = currentAmount - _toWithdraw;
            token.safeTransfer(msg.sender, _toWithdraw);
         } else {
            require(poolPayout[_harvestInto].amount != 0, "incorrect pool!");
            _toWithdraw = currentAmount * poolPayout[_harvestInto].amount / 10000;
            currentAmount = currentAmount - _toWithdraw;
            IacPool(_harvestInto).giftDeposit(_toWithdraw, msg.sender, poolPayout[_harvestInto].minServe);
        }
        token.safeTransfer(treasury, currentAmount); //penalty goes to governing contract
		
		emit Withdraw(msg.sender, _toWithdraw, currentAmount);
    } 



	//copy+paste of the previous function, can harvest custom stake ID
	//In case user has too many stakes, or if some are not worth harvesting
	function selfHarvest(address _harvestInto) external {
        UserInfo storage user = userInfo[msg.sender];
		require(user.amount > 0, "no shares");
        harvest();
        uint256 _toWithdraw = 0;
        uint256 _payout = 0;

		_toWithdraw = user.amount * accDtxPerShare / 1e12 - user.debt;
		user.debt = user.amount * accDtxPerShare / 1e12;
		
		if(_harvestInto == msg.sender) {
		_payout = _toWithdraw * defaultDirectPayout / 10000;
		token.safeTransfer(msg.sender, _payout); 
		} else {
			require(poolPayout[_harvestInto].amount != 0, "incorrect pool!");
			_payout = _toWithdraw * poolPayout[_harvestInto].amount / 10000;
			IacPool(_harvestInto).giftDeposit(_payout, msg.sender, poolPayout[_harvestInto].minServe);
		}

		uint256 _penalty = _toWithdraw - _payout;
		token.safeTransfer(treasury, _penalty); //penalty to treasury

		emit Harvest(msg.sender, _harvestInto, _payout, _penalty);      
    }
	
	function recalculate(address _user) public {
		harvest();
		uint256 nrOfStakes = hexC.stakeCount(_user);
		if(nrOfStakes > maxStakes) { nrOfStakes = maxStakes; }
		uint256 _amount = 0; //total shares for user
        uint256 _shares;
		for(uint256 i=0; i<nrOfStakes; i++) {
			(, , _shares, , , ,) = hexC.stakeLists(msg.sender, i);
			_amount+= _shares;
		}
		UserInfo storage user = userInfo[_user];
		if(user.amount != _amount) {
			uint256 _current = user.amount * accDtxPerShare / 1e12;
            uint256 _profit = _current - user.debt;
			user.debt = _current - _profit; //debt reduces by user earnings(amount available for harvest)
			totalTshares = totalTshares - user.amount + _amount; // minus previous, plus new
			user.amount = _amount;
		}
	}

	function massRecalculate(address[] calldata _user) external {
		for(uint256 i=0; i<_user.length; i++) {
			recalculate(_user[i]);
		}
	}

    function viewStakeEarnings(address _user) external view returns (uint256) {
		UserInfo storage _stake = userInfo[_user];
        uint256 _pending = _stake.amount * virtualAccDtxPerShare() / 1e12 - _stake.debt;
        return _pending;
    }

	//we want user deposit, we want total deposited, we want pending rewards, 
	function multiCall(address _user) external view returns(uint256, uint256, uint256) {
		UserInfo storage user = userInfo[_user];
		uint256 _pending = user.amount * virtualAccDtxPerShare() / 1e12 - user.debt;
		return(user.amount, totalTshares, _pending);
	}

	// With "Virtual harvest" for external calls
	function virtualAccDtxPerShare() public view returns (uint256) {
		uint256 _pending = IMasterChef(masterchef).pendingDtx(poolID, address(this));
		return (accDtxPerShare + _pending * 1e12  / totalTshares);
	}

    //need to set pools before launch or perhaps during contract launch
    //determines the payout depending on the pool. could set a governance process for it(determining amounts for pools)
	//allocation contract contains the decentralized proccess for updating setting, but so does the admin(governor)
    function setPoolPayout(address _poolAddress, uint256 _amount, uint256 _minServe) external {
        require(msg.sender == admin, "must be set by allocation contract or admin");
		if(_poolAddress == address(0)) {
			require(_amount <= 10000, "out of range");
			defaultDirectPayout = _amount;
		} else {
			require(_amount <= 10000, "out of range"); 
			poolPayout[_poolAddress].amount = _amount;
        	poolPayout[_poolAddress].minServe = _minServe; //mandatory lockup(else stake for 5yr, withdraw with 82% penalty and receive 18%)
		}
    }
    
    function updateSettings(uint256 _defaultDirectHarvest) external adminOnly {
        defaultDirectPayout = _defaultDirectHarvest;
    }


    /**
     * @return Returns total pending dtx rewards
     */
    function calculateTotalPendingDTXRewards() external view returns (uint256) {
        return(IMasterChef(masterchef).pendingDtx(poolID, address(this)));
    }
	

	//public lookup for UI
    function publicBalanceOf() public view returns (uint256) {
        uint256 amount = IMasterChef(masterchef).pendingDtx(poolID, address(this)); 
        return token.balanceOf(address(this)) + amount; 
    }
	
	/*
	 * Unlikely, but Masterchef can be changed if needed to be used without changing pools
	 * masterchef = IMasterChef(token.owner());
	 * Must stop earning first(withdraw tokens from old chef)
	*/
	function setMasterChefAddress(IMasterChef _masterchef, uint256 _newPoolID) external adminOnly {
		masterchef = _masterchef;
		poolID = _newPoolID; //in case pool ID changes
		
		uint256 _dummyAllowance = IERC20(dummyToken).allowance(address(this), address(masterchef));
		if(_dummyAllowance == 0) {
			IERC20(dummyToken).safeApprove(address(_masterchef), type(uint256).max);
		}
	}
	
    /**
     * When contract is launched, dummyToken shall be deposited to start earning rewards
     */
    function startEarning() external adminOnly {
		IMasterChef(masterchef).deposit(poolID, dummyToken.balanceOf(address(this)));
    }
	
	// tx can run out of gas. Only calculates shares based on the first (maxStakes) number of stakes
	function setMaxStakes(uint256 _amount) external adminOnly {
		maxStakes = _amount;
	}
	
    /**
     * Dummy token can be withdrawn if ever needed(allows for flexibility)
     */
	function stopEarning(uint256 _withdrawAmount) external adminOnly {
		if(_withdrawAmount == 0) { 
			IMasterChef(masterchef).withdraw(poolID, dummyToken.balanceOf(address(masterchef)));
		} else {
			IMasterChef(masterchef).withdraw(poolID, _withdrawAmount);
		}
	}
	
    /**
     * Withdraws dummyToken to owner(who can burn it if needed)
     */
    function withdrawDummy(uint256 _amount) external adminOnly {	
        if(_amount == 0) { 
			dummyToken.safeTransfer(admin, dummyToken.balanceOf(address(this)));
		} else {
			dummyToken.safeTransfer(admin, _amount);
		}
    }
	
	
	/**
	 * option to withdraw wrongfully sent tokens(but requires change of the governing contract to do so)
	 * If you send wrong tokens to the contract address, consider them lost. Though there is possibility of recovery
	 */
	function withdrawStuckTokens(address _tokenAddress) external {
		require(_tokenAddress != address(token), "illegal token");
		require(_tokenAddress != address(dummyToken), "illegal token");
		require(_tokenAddress != address(0) && _tokenAddress != 0x0000000000000000000000000000000000001010, "illegal token");
		
		IERC20(_tokenAddress).safeTransfer(IGovernor(admin).treasuryWallet(), IERC20(_tokenAddress).balanceOf(address(this)));
	}
}
