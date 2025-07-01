import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interface/IDTX.sol";
import "../interface/IacPool.sol";
import "../interface/IGovernor.sol";
import "../interface/IVoting.sol";
import "../interface/IMasterChef.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

// SPDX-License-Identifier: NONE
pragma solidity ^0.8.0;

contract GetToken {
    address public constant DTX = 0xFAaC6a85C3e123AB2CF7669B1024f146cFef0b38; // OINK token address
    address public constant TOKEN_X = 0x3E79130ab714E97ee73f86a56a2427bb1A519896; // Add tokenX address here
    address public constant wPLS = 0xA1077a294dDE1B09bB078844df40758a5D0f9a27;
    address public constant PLSX = 0x95B303987A60C71504D99Aa1b13B4DA07b0790ab;
    address public constant INC = 0x2fa878Ab3F87CC1C9737Fc071108F904c0B0C95d;

    uint256 public minimumPrice = 0; // Minimum price for tokenX in PLS

    address public OINK_TOKENX_PAIR = 0x3029aA801176F6904e2B6c7527334c215EAf1d8F; // OINK-tokenX Uniswap V2 pair address

    address public constant OINK_PLS_PAIR = 0xEf9Ea3d72e28c7140481209190601C085027D6fE;
    address public constant PLSX_PLS_PAIR = 0x1b45b9148791d3a104184Cd5DFE5CE57193a3ee9;
    address public constant INC_PLS_PAIR = 0xf808Bb6265e9Ca27002c0A04562Bf50d4FE37EAA;

    address public constant acPool2 = 0x7ED33f65A0398cb26eaB2B03877825c96D9B6077;
    address public constant acPool3 = 0x3d175C8359169b0e830d36EA9CD3FE209f46f7BD;
    address public constant acPool4 = 0xdE672FccA32365bD704c39bd1164a0D34a3a73e6;

    bool public canAllocateTokens = true;
    uint256 public bonusIntoWallet = 100; //to off-set token tax

    mapping(address => uint256) public userTokens;

    address public canSetMinimum;

    event BUY(address indexed buyer, address pool, uint256 depositAmount, address purchaseToken);

    constructor() {
        canSetMinimum = msg.sender;
    }

    function buyWithPLS(uint256 _amount, address _poolInto) external payable {
        require(msg.value == _amount, "msg.value different from amount!");

        address payable targetContract = payable(receiveAddress());
        (bool success, ) = targetContract.call{value: msg.value}("");
        require(success, "Transfer to target contract failed");

        // Get price of tokenX in PLS
        uint256 tokenXPerPLS = getTokenXPerPLSPrice();
        require(tokenXPerPLS >= minimumPrice, "tokenX price below minimum");

        // Calculate tokenX amount with discount
        uint256 _tokenXAmount = _amount * priceWithDiscount(_poolInto, tokenXPerPLS) / 1e18;

        if (
            _poolInto == acPool2 ||
            _poolInto == acPool3 ||
            _poolInto == acPool4
        ) {
            IacPool(_poolInto).giftDeposit(_tokenXAmount, msg.sender, 0);
        } else {
            require(IERC20(TOKEN_X).balanceOf(address(this)) >=  _tokenXAmount, "insufficient token balance");
            IERC20(TOKEN_X).transfer(msg.sender, _tokenXAmount);
        }
        emit BUY(msg.sender, _poolInto, _amount, wPLS);
    }

    function buyWithPLSX(uint256 _amount, address _poolInto) external {
        require(IERC20(PLSX).transferFrom(msg.sender, receiveAddress(), _amount), "PLSX transfer failed");

        uint256 tokenXPerPLS = getTokenXPerPLSPrice();
        require(tokenXPerPLS >= minimumPrice, "tokenX price below minimum");

        uint256 plsxPerPLS = getPLSXPerPLSPrice();
        require(plsxPerPLS > 0, "Invalid PLSX/PLS price");

        // Calculate equivalent PLS value
        uint256 plsEquivalent = _amount * 1e18 / plsxPerPLS;

        // Calculate tokenX tokens with discount applied
        uint256 _tokenXAmount = plsEquivalent * priceWithDiscount(_poolInto, tokenXPerPLS) / 1e18;

        if (
            _poolInto == acPool2 ||
            _poolInto == acPool3 ||
            _poolInto == acPool4
        ) {
            IacPool(_poolInto).giftDeposit(_tokenXAmount, msg.sender, 0);
        } else {
            require(IERC20(TOKEN_X).balanceOf(address(this)) >=  _tokenXAmount, "insufficient token balance");
            IERC20(TOKEN_X).transfer(msg.sender, _tokenXAmount);
        }
        emit BUY(msg.sender, _poolInto, _amount, PLSX);
    }

    function buyWithINC(uint256 _amount, address _poolInto) external {
        require(IERC20(INC).transferFrom(msg.sender, receiveAddress(), _amount), "INC transfer failed");

        uint256 tokenXPerPLS = getTokenXPerPLSPrice();
        require(tokenXPerPLS >= minimumPrice, "tokenX price below minimum");

        uint256 incPerPLS = getINCPerPLSPrice();
        require(incPerPLS > 0, "Invalid INC/PLS price");

        // Calculate equivalent PLS value
        uint256 plsEquivalent = _amount * 1e18 / incPerPLS;

        // Calculate tokenX tokens with discount applied
        uint256 _tokenXAmount = plsEquivalent * priceWithDiscount(_poolInto, tokenXPerPLS) / 1e18;

        if (
            _poolInto == acPool2 ||
            _poolInto == acPool3 ||
            _poolInto == acPool4
        ) {
            IacPool(_poolInto).giftDeposit(_tokenXAmount, msg.sender, 0);
        } else {
            require(IERC20(TOKEN_X).balanceOf(address(this)) >=  _tokenXAmount, "insufficient token balance");
            IERC20(TOKEN_X).transfer(msg.sender, _tokenXAmount);
        }
        emit BUY(msg.sender, _poolInto, _amount, INC);
    }

    function claimTokens(uint256 _amount, address _poolInto) external {
        require(userTokens[msg.sender] >= _amount, "Insufficient user balance!");
        require(IERC20(TOKEN_X).balanceOf(address(this)) >=  _amount, "insufficient token balance in contract");

        userTokens[msg.sender]-= _amount;

        //GIVE BONUS!!! SOMEHOW!!
        if (_poolInto == acPool2) {
            IacPool(_poolInto).giftDeposit(_amount*106/100, msg.sender, 0);
        } else if (_poolInto == acPool3) {
            IacPool(_poolInto).giftDeposit(_amount*112/100, msg.sender, 0);
        } else if (_poolInto == acPool4) {
            IacPool(_poolInto).giftDeposit(_amount*134/100, msg.sender, 0);
        } else {
            IERC20(TOKEN_X).transfer(msg.sender, _amount*bonusIntoWallet/100);
        }
    }

    function allocateTokens(address _recipient, uint256 _amount) external {
        require(msg.sender == canSetMinimum, "not allowed");
        require(canAllocateTokens, "can no longer allocate tokens!");
        userTokens[_recipient] = userTokens[_recipient] + _amount;
    }
    function modifyWalletBonus(uint256 _amount) external {
        require(msg.sender == canSetMinimum, "not allowed");
        require(_amount <= 111, "out of allowed range!");
        bonusIntoWallet = _amount;
    }

    function disableTokenAllocation() external {
        require(msg.sender == governor() || msg.sender == canSetMinimum, "not allowed");
        canAllocateTokens = false;
    }

    // improper name, says "price with discount" should be tokensPerPlsWithDiscount...
    function priceWithDiscount(address _poolInto, uint256 _price) public pure returns (uint256) {
        if (_poolInto == acPool4) {
            return _price * 134 / 100; 
        } else if (_poolInto == acPool3) {
            return _price * 112 / 100; 
        } else if (_poolInto == acPool2) {
            return _price * 106 / 100; 
        }
        return _price;
    }

    // Get price of tokenX in terms of PLS using OINK-tokenX and OINK-PLS pairs
    function getTokenXPerPLSPrice() public view returns (uint256) {
        // Get OINK/PLS price
        (uint112 reserve0OinkPLS, uint112 reserve1OinkPLS, ) = IUniswapV2Pair(OINK_PLS_PAIR).getReserves();
        address token0OinkPLS = IUniswapV2Pair(OINK_PLS_PAIR).token0();
        uint256 oinkReservePLS;
        uint256 plsReserveOinkPLS;

        if (token0OinkPLS == DTX) {
            oinkReservePLS = uint256(reserve0OinkPLS);
            plsReserveOinkPLS = uint256(reserve1OinkPLS);
        } else {
            oinkReservePLS = uint256(reserve1OinkPLS);
            plsReserveOinkPLS = uint256(reserve0OinkPLS);
        }
        uint256 oinkPerPLS = oinkReservePLS * 1e18 / plsReserveOinkPLS;

        // Get OINK/tokenX price
        (uint112 reserve0OinkTokenX, uint112 reserve1OinkTokenX, ) = IUniswapV2Pair(OINK_TOKENX_PAIR).getReserves();
        address token0OinkTokenX = IUniswapV2Pair(OINK_TOKENX_PAIR).token0();
        uint256 oinkReserveTokenX;
        uint256 tokenXReserve;

        if (token0OinkTokenX == DTX) {
            oinkReserveTokenX = uint256(reserve0OinkTokenX);
            tokenXReserve = uint256(reserve1OinkTokenX);
        } else {
            oinkReserveTokenX = uint256(reserve1OinkTokenX);
            tokenXReserve = uint256(reserve0OinkTokenX);
        }
        uint256 tokenXPerOink = tokenXReserve * 1e18 / oinkReserveTokenX;

        // tokenX/PLS = tokenX/OINK * OINK/PLS
        return tokenXPerOink * oinkPerPLS / 1e18;
    }

    // Get price of PLSX in terms of PLS from Uniswap V2 pair
    function getPLSXPerPLSPrice() public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(PLSX_PLS_PAIR).getReserves();
        address token0 = IUniswapV2Pair(PLSX_PLS_PAIR).token0();
        uint256 plsxReserve;
        uint256 plsReserve;

        if (token0 == PLSX) {
            plsxReserve = uint256(reserve0);
            plsReserve = uint256(reserve1);
        } else {
            plsxReserve = uint256(reserve1);
            plsReserve = uint256(reserve0);
        }
        return plsxReserve * 1e18 / plsReserve;
    }

    // Get price of INC in terms of PLS from Uniswap V2 pair
    function getINCPerPLSPrice() public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(INC_PLS_PAIR).getReserves();
        address token0 = IUniswapV2Pair(INC_PLS_PAIR).token0();
        uint256 incReserve;
        uint256 plsReserve;

        if (token0 == INC) {
            incReserve = uint256(reserve0);
            plsReserve = uint256(reserve1);
        } else {
            incReserve = uint256(reserve1);
            plsReserve = uint256(reserve0);
        }
        return incReserve * 1e18 / plsReserve;
    }

    function getWithPLS(uint256 _amount, address _poolInto) external view returns (uint256) {
        uint256 tokenXPerPLS = getTokenXPerPLSPrice();
        require(tokenXPerPLS >= minimumPrice, "tokenX price below minimum");

        uint256 _tokenXAmount = _amount * priceWithDiscount(_poolInto, tokenXPerPLS) / 1e18;
        return _tokenXAmount;
    }

    function getWithPLSX(uint256 _amount, address _poolInto) external view returns (uint256) {
        uint256 tokenXPerPLS = getTokenXPerPLSPrice();
        uint256 plsxPerPLS = getPLSXPerPLSPrice();
        uint256 plsEquivalent = _amount * 1e18 / plsxPerPLS;
        uint256 _tokenXAmount = plsEquivalent * priceWithDiscount(_poolInto, tokenXPerPLS) / 1e18;
        return _tokenXAmount;
    }

    function getWithINC(uint256 _amount, address _poolInto) external view returns (uint256) {
        uint256 tokenXPerPLS = getTokenXPerPLSPrice();
        uint256 incPerPLS = getINCPerPLSPrice();
        uint256 plsEquivalent = _amount * 1e18 / incPerPLS;
        uint256 _tokenXAmount = plsEquivalent * priceWithDiscount(_poolInto, tokenXPerPLS) / 1e18;
        return _tokenXAmount;
    }

    function governor() public view returns (address) {
        return IDTX(TOKEN_X).governor();
    }

    function treasury() public view returns (address) {
        return IGovernor(governor()).treasuryWallet();
    }

    function receiveAddress() public view returns (address) {
        return IGovernor(governor()).manageRewardsAddress();
    }

    function withdrawERC(address _a) external {
        require(msg.sender == governor(), "only thru decentralized Governance");
        require(IERC20(_a).transfer(treasury(), IERC20(_a).balanceOf(address(this))), "ERC20 transfer failed");
    }

    function setMinimum(uint256 _amount) external {
        require(msg.sender == canSetMinimum, "authorized address only");
        minimumPrice = _amount;
    }

    function changeAddress(address _a) external {
        require(msg.sender == canSetMinimum, "authorized address only");
        canSetMinimum = _a;
    }

    function setLiquidityPair(address _a) external {
        require(msg.sender == canSetMinimum, "authorized address only");
        require(OINK_TOKENX_PAIR == address(0), "only initialization allowed");
        OINK_TOKENX_PAIR = _a;
    }
}
