// SPDX-License-Identifier: NONE
pragma solidity 0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interface/IDTX.sol";
import "./interface/ISenate.sol";
import "./interface/IGovernor.sol";


contract DTXChef is Ownable, ReentrancyGuard {
	using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each pool.
    struct PoolInfo {       // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. DTXs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that DTXs distribution occurs.
        address participant;   // participating contract    
    }

    // The DTX TOKEN!
    IDTX public dtx;
    // Dev address.
    address public devaddr;
	//portion of inflation goes to the decentralized governance contract
	uint256 public governorFee = 618; //6.18%
    // DTX tokens created per block.
    uint256 public DTXPerBlock = 850 * 1e18; // start at 850 tokens per block (*roughly* 50,000 tokens per 10minutes; Bitcoin started with 50 BTC per 10minutes)
    // Deposit Fee address
    address public feeAddress;

	bool maxSupplyReached = false;

	// Total tokens published to senate
	uint256 public fairTokensPublishedToSenate;

    // Info of each pool.
    PoolInfo[] public poolInfo;
	// User Credit (can publish such amount of tokens)
	mapping(address => uint256) public credit;
	// Does Pool Already Exist?
	mapping(address => bool) public existingParticipant;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when DTX mining starts.
    uint256 public startBlock = 99999999; // arbitrary date ( is updated when minting phase begins )
	// Keep track of total credit given 
	uint256 public totalCreditRewards;
	// Keep track of principal burned
	uint256 public totalPrincipalBurned;
	// Keep track of total tokens published (by users)
	uint256 public totalPublished;
	

	bool public senatorRewards = true;
	
	 // can burn tokens without allowance
	mapping(address => bool) public trustedContract;
	//makes it easier to verify(without event logs)
	uint256 public trustedContractCount; 

    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
	event UpdateEmissions(address indexed user, uint256 newEmissions);
	event TrustedContract(address contractAddress, bool setting);
	event TransferCredit(address from, address to, uint256 amount);

    constructor(
        IDTX _DTX,
	address _airdropFull
    ) {
        dtx = _DTX;
        devaddr = msg.sender;
        feeAddress = msg.sender;
	    credit[_airdropFull] = 1080000000 * 1e18;
		totalCreditRewards = 1080000000 * 1e18;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }
	
	function publishTokens(address _to, uint256 _amount) external {
		require(credit[msg.sender] >= _amount, "Insufficient credit");
		credit[msg.sender] = credit[msg.sender] - _amount;
		totalPublished+=_amount;
		dtx.mint(_to, _amount);
	}
	
	function burn(address _from, uint256 _amount) external returns (bool) {
		require(trustedContract[msg.sender], "only trusted contracts");
		require(dtx.burnToken(_from, _amount), "burn failed");
		credit[msg.sender] = credit[msg.sender] + _amount;
		totalPrincipalBurned+= _amount;
		return true;
	}
	
    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, address _participant, bool _withUpdate) public onlyOwner {
		require(!existingParticipant[_participant], "contract already participating");
		
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
		existingParticipant[_participant] = true;
        poolInfo.push(PoolInfo({
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            participant: _participant
        }));
    }
    
    function massAdd(uint256[] calldata _allocPoint, address[] calldata _participant, bool[] calldata _withUpdate) external {
        require(_allocPoint.length == _participant.length && _allocPoint.length == _withUpdate.length);
        for(uint i=0; i < _allocPoint.length; i++) {
            add(_allocPoint[i], _participant[i], _withUpdate[i]);
        }
    }

    // Update the given pool's DTX allocation point and deposit fee. Can only be called by the owner.
	// Notice: DepositFee is completely irrelevant, but it's been left as it would otherwise mess up our setup
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }


    // View function to see pending DTXs on frontend.
    function pendingDtx(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number > pool.lastRewardBlock && pool.participant != address(0)) {
            uint256 multiplier = block.number.sub(pool.lastRewardBlock);
            uint256 dtxReward = multiplier.mul(DTXPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            return dtxReward;
        }
        return 0;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        if (pool.participant == address(0) || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number.sub(pool.lastRewardBlock);
        uint256 dtxReward = multiplier.mul(DTXPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        dtx.mint(devaddr, dtxReward.mul(governorFee).div(10000));
		credit[pool.participant] = credit[pool.participant] + dtxReward;
		totalCreditRewards+=dtxReward;
        pool.lastRewardBlock = block.number;
    }

    function stopPublishing(uint256 _pid) external onlyOwner {
        updatePool(_pid);
        poolInfo[_pid].participant = address(0);
        poolInfo[_pid].allocPoint = 0;
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint);
    }

	function startPublishing(uint256 _pid, address _participant, uint256 _alloc) external onlyOwner {
		require(poolInfo[_pid].allocPoint == 0 && poolInfo[_pid].participant == address(0), "already earning");
        updatePool(_pid);
        poolInfo[_pid].participant = _participant;
        poolInfo[_pid].allocPoint = _alloc;
        totalAllocPoint = totalAllocPoint.add(_alloc);
    }
	
	// In case pools are changed (on migration old contract transfers it's credit to the new one)
	function transferCredit(address _to, uint256 _amount) external {
        require(credit[msg.sender] >= _amount, "insufficient credit for transfer!");
		credit[msg.sender] = credit[msg.sender] - _amount;
		credit[_to] = credit[_to] + _amount;
		emit TransferCredit(msg.sender, _to, _amount);
	}
	
	//only owner can set trusted Contracts
	function setTrustedContract(address _contractAddress, bool _setting) external onlyOwner {
		if(trustedContract[_contractAddress] != _setting) { 
			trustedContract[_contractAddress] = _setting;
			_setting ? trustedContractCount++ : trustedContractCount--;
			emit TrustedContract(_contractAddress, _setting);
		}
	}

	function setGovernorFee(uint256 _amount) public onlyOwner {
		require(_amount <= 1000 && _amount >= 0);
		governorFee = _amount;
	}

    // Update dev address by the previous dev.
    function dev(address _devaddr) public onlyOwner {
        devaddr = _devaddr;
    }

    function setFeeAddress(address _feeAddress) public onlyOwner {
        feeAddress = _feeAddress;
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _DTXPerBlock) public onlyOwner {
        if(!maxSupplyReached) {
			massUpdatePools();
	        DTXPerBlock = _DTXPerBlock;
		} else {
			DTXPerBlock = 0;
		}
		
		emit UpdateEmissions(tx.origin, _DTXPerBlock);
    }

    //Only update before start of farm
    function updateStartBlock(uint256 _startBlock) public onlyOwner {
        require(block.number < startBlock, "already started");
		startBlock = _startBlock;
    }
	
	//For flexibility(can transfer to new masterchef if need be!)
	function tokenChangeOwnership(address _newOwner) external onlyOwner {
		dtx.transferOwnership(_newOwner);
	}


	function fairMintSenate() external {
		require(senatorRewards, "senator rewards are turned off");
        require(block.number > startBlock, "Must wait until minting phase begins!");

		address[] memory senators = ISenate(IGovernor(owner()).senateContract()).viewSenators();
		uint256 _senatorRewardAmount;
		if(senators.length <= 100) {
			_senatorRewardAmount = 100; // 0.01%
		} else {
			_senatorRewardAmount = 10000 / senators.length; // 1% shared between all the senators
		}
		uint256 _amount = ((totalCreditRewards * _senatorRewardAmount) / 1000000) - fairTokensPublishedToSenate;

		for(uint i=0; i < senators.length; i++) {
			credit[senators[i]]+= _amount;
		}

		fairTokensPublishedToSenate+= senators.length * _amount;
		totalCreditRewards+= senators.length * _amount;
	}

	function rewardSenators(bool _e) external onlyOwner {
		senatorRewards = _e;
	}

	// renounce rewards once maximum supply would be breached
	// if there is an "overflow", tokens can simply be burned from the governing contract
	function renounceRewards() external {
		require(virtualTotalSupply() >= dtx.MAX_SUPPLY(), "Max supply not yet reached!");
		DTXPerBlock = 0;
		maxSupplyReached = true;
	}

	function virtualTotalSupply() public view returns (uint256) {
		return (dtx.totalSupply() + totalCreditRewards + totalPrincipalBurned - totalPublished);
	}
}
