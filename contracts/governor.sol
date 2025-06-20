// SPDX-License-Identifier: NONE

pragma solidity 0.8.20;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interface/IMasterChef.sol";
import "./interface/IDTX.sol";
import "./interface/IConsensus.sol";
import "./interface/IacPool.sol";
import "./interface/ITreasury.sol";

interface ITokenBalancer {
    function emergencyWithdraw(address _token) external;
}

interface IEmitVault {
	function giveNFTApproval(address[] calldata _allowed, bool _permission) external;
}

contract DTXgovernor {
    address public constant OINK = 0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38;
    address public constant token = ; //DEGEN token

    //masterchef address
    address public constant masterchef = ;

	address public constant basicContract = ;
	address public constant farmContract = ;
    address public constant consensusContract = ;
	
	address public constant creditContract = ;
    
    address public constant treasuryWallet = ;

	address public constant rewardContract = ; //for referral rewards

address public constant manageRewardsAddress = ; // buy oink contract

address public constant helperToken = ;
    
    //addresses for time-locked deposits(autocompounding pools)
    address public constant acPool1 = ;
    address public constant acPool2 = ;
    address public constant acPool3 = ;
    address public constant acPool4 = ;

        
    //pool ID in the masterchef for respective Pool address and dummy token
    uint256 public constant acPool1ID = 0;
    uint256 public constant acPool2ID = 1;
    uint256 public constant acPool3ID = 2;
    uint256 public constant acPool4ID = 3;

	uint256 public proposeGovernorTimestamp;
	address public proposedGovernor;
    mapping(address => bool) public governorBlocked;
    mapping(address => uint256) private _rollBonus;

	uint256 public referralBonus = 500; // 5% for both referr and invitee
	uint256 public depositFee = 0;
	uint256 public fundingRate = 200;

    uint256 public costToVote = 1 * 1e18;  // 1000 coins. All proposals are valid unless rejected. This is a minimum to prevent spam
    uint256 public delayBeforeEnforce = 1 days; //minimum number of TIME between when proposal is initiated and executed
    

	uint256 public lastHarvestedTime;

	bool public isTemporaryAdmin = true;
	address public temporaryAdmin;

    event SetInflation(uint256 rewardPerBlock);
    event EnforceGovernor(address indexed _newGovernor, address indexed enforcer);
    event GiveRolloverBonus(address indexed recipient, uint256 amount, address indexed poolInto);

    constructor() {
		// Roll-over bonuses
		_rollBonus[acPool1] = 100;
		_rollBonus[acPool2] = 200;
		_rollBonus[acPool3] = 300;
		_rollBonus[acPool3] = 500;
		temporaryAdmin = msg.sender;
    }    
   
   
     /**
     * Rebalances Pools and allocates rewards in masterchef
     * Pools with higher time-lock must always pay higher rewards in relative terms
     * Eg. for 1DTX staked in the pool 6, you should always be receiving
     * 50% more rewards compared to staking in pool 4
     */
    function rebalancePools() public {
    	uint256 balancePool1 = IacPool(acPool1).balanceOf();
    	uint256 balancePool2 = IacPool(acPool2).balanceOf();
    	uint256 balancePool3 = IacPool(acPool3).balanceOf();
	uint256 balancePool4 = IacPool(acPool4).balanceOf();
    	
   	    uint256 total = balancePool1 + balancePool2 + balancePool3  + balancePool4;

		IMasterChef(masterchef).set(acPool1ID, (100000 * 5333 * balancePool1) / (total * 10000), true);
	IMasterChef(masterchef).set(acPool2ID, (100000 * 7500 * balancePool3) / (total * 10000), false);
    	IMasterChef(masterchef).set(acPool3ID, (100000 * 25000 * balancePool2) / (total * 10000), false);
    	IMasterChef(masterchef).set(acPool4ID, (100000 * 125000 * balancePool3) / (total * 10000), false);

    }
	

    /**
     * Harvests from all pools and rebalances rewards
     */
    function harvest() external {
        rebalancePools();
		lastHarvestedTime = block.timestamp;
    }
    
    /**
     * Mechanism, where the governor gives the bonus 
     * to user for extending(re-commiting) their stake
     * tldr; sends the gift deposit, which resets the timer
     * the pool is responsible for calculating the bonus
     */
    function stakeRolloverBonus(address _toAddress, address _depositToPool, uint256 _bonusToPay, uint256 _stakeID) external {
        require(
            msg.sender == acPool1 || msg.sender == acPool2 || msg.sender == acPool3 || msg.sender == acPool4);
        
        IacPool(_depositToPool).addAndExtendStake(_toAddress, _bonusToPay, _stakeID, 0);
        
        emit GiveRolloverBonus(_toAddress, _bonusToPay, _depositToPool);
    }
    
    function proposeNewGovernor(address beneficiary) external {
		require(msg.sender == IDTX(OINK).governor(), "decentralized voting only");
		proposedGovernor = beneficiary;
		proposeGovernorTimestamp = block.timestamp;
	}
	
    function setNewGovernor() external {
	require(proposedGovernor != address(0), "governor not yet submitted!");
	require(proposeGovernorTimestamp + 5 * delayBeforeEnforce < block.timestamp, "pending validation by this system for potential rejection");
	require(!governorBlocked[proposedGovernor], "governor upgrade blocked by this system consensus!");

	IMasterChef(masterchef).setFeeAddress(proposedGovernor);
        IMasterChef(masterchef).dev(proposedGovernor);
        IMasterChef(masterchef).transferOwnership(proposedGovernor); //transfer masterchef ownership
		
		IERC20(token).transfer(proposedGovernor, IERC20(token).balanceOf(address(this))); // send collected DTX tokens to new governor
        
		emit EnforceGovernor(proposedGovernor, msg.sender);
    }

	function blockGovernorProposal() external {
	require(proposedGovernor != address(0), "governor not yet submitted!");
	IConsensus(consensusContract).updateHighestConsensusVotes(addressToUint256(proposedGovernor));
	if(IConsensus(consensusContract).highestConsensusVotes(addressToUint256(proposedGovernor)) >= IConsensus(consensusContract).totalDTXStaked() * 25 / 100) {
		governorBlocked[proposedGovernor] = true;
	}
}

	//gives allowance to pools to use emit NFT
	function approveEmitNft(address _updateVault, address[] calldata _vaults, uint256[] calldata _poolIds) external {
		for(uint i=0; i < _vaults.length; i++) {
			(,, address _vault) = IMasterChef(masterchef).poolInfo(_poolIds[i]);
			require(_vaults[i] == _vault, "invalid _vaults data"); // check vault is valid in masterchef
		}
		IEmitVault(_updateVault).giveNFTApproval(_vaults, true);
	}


	function treasuryRequest(address _tokenAddr, address _recipient, uint256 _amountToSend) external {
		require(msg.sender == consensusContract);
		ITreasury(payable(treasuryWallet)).requestWithdraw(
			_tokenAddr, _recipient, _amountToSend
		);
	}
	
	function updateDelayBeforeEnforce(uint256 newDelay) external {
	    require(msg.sender == basicContract);
	    delayBeforeEnforce = newDelay;
	}

	
	function updateCostToVote(uint256 newCostToVote) external {
	    require(msg.sender == basicContract);
	    costToVote = newCostToVote;
	}
	
	function updateRolloverBonus(address _forPool, uint256 _bonus) external {
	    require(msg.sender == basicContract);
		require(_bonus <= 1500, "15% hard limit");
	    _rollBonus[_forPool] = _bonus;
	}

	function addNewPool(address _pool) external {
	    require(msg.sender == basicContract);
		require(IMasterChef(masterchef).poolLength() < 50, "Maximum pools allowed reached");
	    IMasterChef(masterchef).add(0, _pool, false);
	}

	function setReward(uint256 _amount) external {
	    require(msg.sender == farmContract);
	    IMasterChef(masterchef).updateEmissionRate(_amount);
	}

	function setPool(uint256 _pid, uint256 _allocPoint, bool _withUpdate) external {
	    require(msg.sender == farmContract);
	    IMasterChef(masterchef).set(_pid, _allocPoint, _withUpdate);
	}

	// If fees are changed, updateFees() function must be called to each vault contract to sync the update!
	function updateVault(uint256 _type, uint256 _amount) external {
        require(msg.sender == farmContract);

        if(_type == 0) {
            depositFee = _amount;
        } else if(_type == 1) {
            fundingRate = _amount;
        } else if (_type == 2) {
			require(_amount <= 2500, "max 25% Bonus!");
			referralBonus = _amount;
		}
    }
	
		//Modified function; instead of setting governor tax, we set token tax
	function setGovernorTax(uint256 _amount) external {
		require(msg.sender == farmContract);
		IDTX(token).updateTax(_amount);
	}

	//instead of burn token function, we use it to set rewards
	function burnTokens(uint256 _amount) external {
		require(msg.sender == farmContract);
		
		IMasterChef(masterchef).updateEmissionRate(_amount);
	}
	
	function transferToTreasury(uint256 amount) external {
		require(msg.sender == farmContract);
		
		IERC20(token).transfer(treasuryWallet, amount);
	}

	//enable governor shift immedietly post-launch in case quick adaption is needed. Function should be disabled shortly after
	function setNewGovernorByAdmin(address _tempGovernor) external {
	require(isTemporaryAdmin, "temporary admin access has been revoked!");
	require(msg.sender == temporaryAdmin, "unauthorized!");

        IMasterChef(masterchef).transferOwnership(_tempGovernor); //transfer masterchef ownership

		emit EnforceGovernor(proposedGovernor, msg.sender);
    }

	function disableTemporaryAdmin() external {
		require(isTemporaryAdmin, "already revoked");
	require(msg.sender == temporaryAdmin, "unauthorized!");

	isTemporaryAdmin = false;
}


	function getRollBonus(address _bonusForPool) external view returns (uint256) {
        return _rollBonus[_bonusForPool];
    }

	function addressToUint256(address addr) public pure returns (uint256) {
    return uint256(uint160(addr));
}
	
    
}  
