// SPDX-License-Identifier: NONE

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interface/IDTX.sol";
import "./interface/IacPool.sol";
import "./interface/IGovernor.sol";
import "./interface/IVoting.sol";

// Seems more simple than a merkle-tree airdrop
// if fees too high, do the merkle-tree style
contract AirDrop is ReentrancyGuard {
	uint256 public constant CLAIM_PERIOD_DAYS = 90;

	address public immutable DTX;
	address public immutable initiatingAddress; // inititates balances

    uint256 public startTime;
    uint256 public directPayout = 250; // 97.5% penalty
	uint256 public totalCredit;
	bool public creditGiven = false;

    address public acPool1;
    address public acPool2;
    address public acPool3;
    address public acPool4;
    address public acPool5;
    address public acPool6;
	
	address public votingCreditContract;

	mapping(address => uint256) public userCredit;
	mapping(address => uint256) public minToServe;
    mapping(address => uint256) public payout;

	event AddCredit(uint256 credit, address user);
	event RedeemCredit(uint256 amount, address user, address withdrawInto);

	constructor(address _dtx, address initiator) {
		DTX = _dtx;
		initiatingAddress = initiator;
		startTime = block.timestamp;
	}

	function claimAirdrop(uint256 amount, address claimInto) external nonReentrant {
		require(amount <= userCredit[msg.sender], "insufficient credit");
		if(claimInto == acPool1 || claimInto == acPool2 || claimInto == acPool3 || claimInto == acPool4 || claimInto == acPool5 || claimInto == acPool6) {
			IacPool(claimInto).giftDeposit((amount * payout[claimInto] / 10000), msg.sender, minToServe[claimInto]);
			IVoting(votingCreditContract).airdropVotingCredit(amount * payout[claimInto] / 1000, msg.sender);
		} else {
			require(IDTX(DTX).transfer(msg.sender, (amount * directPayout / 10000)));
			//IVoting(votingCreditContract).airdropVotingCredit(amount * directPayout / 10000, msg.sender); // No credit if withdrawn
		}

		userCredit[msg.sender]-= amount;

		emit RedeemCredit(amount, msg.sender, claimInto);
	}

    // ends the airdrop by emptying token balance(sends tokens to governing contract)
	function endAirdrop() external {
		require(block.timestamp > startTime + CLAIM_PERIOD_DAYS * 86400, "airdrop still active");
		IDTX(DTX).transfer(owner(), IDTX(DTX).balanceOf(address(this)));
	}

	function updatePools() external {
			acPool1 = IGovernor(owner()).acPool1();
			acPool2 = IGovernor(owner()).acPool2();
			acPool3 = IGovernor(owner()).acPool3();
			acPool4 = IGovernor(owner()).acPool4();
			acPool5 = IGovernor(owner()).acPool5();
			acPool6 = IGovernor(owner()).acPool6();

			minToServe[acPool1] = 864000;
			minToServe[acPool2] = 2592000;
			minToServe[acPool3] = 5184000;
			minToServe[acPool4] = 8640000;
			minToServe[acPool5] = 20736000;
			minToServe[acPool6] = 31536000;

			payout[acPool1] = 500;
			payout[acPool2] = 1000;
			payout[acPool3] = 1500;
			payout[acPool4] = 2000;
			payout[acPool5] = 5000;
			payout[acPool6] = 10000;	
    }

	function inititateBalances(uint256[] calldata amount, address[] calldata beneficiary) external {
		require(msg.sender == initiatingAddress && !creditGiven, "only initiator allowed");
		require(amount.length == beneficiary.length, "wrong list");
		
		for(uint256 i = 0; i < beneficiary.length; i++) {
			userCredit[beneficiary[i]] = amount[i];
			totalCredit+= amount[i];
			
			emit AddCredit(amount[i], beneficiary[i]);
		}
	} 

	function endInitiation(address _creditContract) external {
		require(msg.sender == initiatingAddress, "only initiator");
		creditGiven = true;
		votingCreditContract = _creditContract;
	}

	function owner() public view returns(address) {
		return IDTX(DTX).governor();
	}
}
