// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Uncomment this line to use console.log
// import "hardhat/console.sol";
import "@rari-capital/solmate/src/tokens/ERC20.sol";
import "@rari-capital/solmate/src/tokens/ERC721.sol";

/*
WalletKnight protects against:
1. Approval exploits on ERC20 and ERC721
APPROVAL: Send all ERC20 tokens or ERC721 to a back-up wallet 

2. Private key exploits
PRIVATE KEY: Send all ERC20 tokens or ERC721 to a multi-sig wallet 

*/

// TODO: Need to add the authorisation logic to the contract

contract WalletKnight {
    uint128 public randomNonce;
    uint128 costPerSecond;

    // Subscriber info
    mapping(address => bool) public subscriber;
    mapping(address => uint256) public subscriptionEnd;
    mapping(address => uint256) public gasLimit;

    // Back-up wallet info
    mapping(address => address) public backUpWallet;
    mapping(address => address) public multiSigWallet;

    ///////////////////////////// Events /////////////////////////////
    event NewSubscriber(address indexed subscriber, uint256 subscriptionEnd);
    event SubscriberTopUp(address indexed subscriber, uint256 subscriptionEnd);
    event BackUpSet(address indexed subscriber, address indexed backUpWallet);
    event MultiSigSet(address indexed subscriber, address indexed multiSigWallet);

    constructor(uint128 _cost)  {
        costPerSecond = _cost;
    }
    ///////////////////// ADMIN FUNCTIONS ///////////////////////
    // TODO: Access control needs to be added
    function changeCost(uint128 _cost) external {
        costPerSecond = _cost;
    }

    function flushETH() external {
        payable(msg.sender).transfer(address(this).balance);
    }

    //////////////////////// USER FUNCTIONS /////////////////////////
    function setUpAccount() external payable {
        require(msg.value > 0, "NO_MONIES");
        uint256 coverageTime = msg.value / costPerSecond;
        require(coverageTime < 52 weeks, "TOO_LONG");
        subscriber[msg.sender] = true;
        subscriptionEnd[msg.sender] = block.timestamp + coverageTime;
        emit NewSubscriber(msg.sender, subscriptionEnd[msg.sender]);
    }

    function topUpAccount() external payable {
        require(subscriber[msg.sender] == true, "NOT_SUBSCRIBED");
        require(msg.value > 0, "NO_MONIES");
        uint256 coverageTime = msg.value / costPerSecond;
        require(subscriptionEnd[msg.sender] + coverageTime < block.timestamp + 52 weeks, "TOO_LONG");
        subscriptionEnd[msg.sender] += coverageTime;
        emit SubscriberTopUp(msg.sender, subscriptionEnd[msg.sender]);
    }

    function setBackUp(address _backUpWallet) external {
        require(subscriber[msg.sender] == true, "NOT_SUBSCRIBED");
        backUpWallet[msg.sender] = _backUpWallet;
        emit BackUpSet(msg.sender, _backUpWallet);
    }

    function setMultisig(address _account, address _multisig) external {
        require(backUpWallet[_account] == msg.sender, "NOT_BACKUP");
        multiSigWallet[_account] = _multisig;
        emit MultiSigSet(msg.sender, _multisig);
    }

    //////////////////////// USER FRONT-RUN /////////////////////////
    /// @notice User callable function to increment their nonce
    function frontRun() external {
        require(subscriber[msg.sender] == true, "NOT_SUBSCRIBED");
        randomNonce++;
    }

    ///////////////////// RELAYER FUNCTIONS FOR APPROVAL HACKS /////////////////////////
    /// @notice Back end will need to check approved on ERC20 balance
    function protectERC20Asset(ERC20 _asset, address _targetAccount) external {
        uint256 gasStart = gasleft();
        address receiver = backUpWallet[_targetAccount];
        uint256 amount = _asset.balanceOf(_targetAccount);
        _asset.transfer(receiver, amount);
        _updateBalance(gasStart, _targetAccount);
    }

    /// @notice Back end will need to check approved on token Id
    function protectERC721Asset(ERC721 _asset, uint256 _id, address _targetAccount) external {
        uint256 gasStart = gasleft();
        address receiver = backUpWallet[_targetAccount];
        _asset.transferFrom(_targetAccount, receiver, _id);
        _updateBalance(gasStart, _targetAccount);
    }

    /// @notice Back end will need to check approved on all assets
    function protectERC20Approved(ERC20[] calldata _assets, address _targetAccount) external {
        uint256 gasStart = gasleft();
        require(subscriber[_targetAccount] == true, "NOT_SUBSCRIBED");
        address receiver = backUpWallet[_targetAccount];
        for(uint256 i; i < _assets.length; i++) {
            uint256 amount = _assets[i].balanceOf(_targetAccount);
            _assets[i].transfer(receiver, amount);
        }
        _updateBalance(gasStart, _targetAccount);
    }

    /// @notice Back end will need to check the approvalForAll
    function protectERC721Approved(ERC721[] calldata _assets, uint256[] calldata _ids, address _targetAccount) external {
        uint256 gasStart = gasleft();
        require(subscriber[_targetAccount] == true, "NOT_SUBSCRIBED");
        address receiver = backUpWallet[_targetAccount];
        for(uint256 i; i < _assets.length; i++) {
            _assets[i].transferFrom(_targetAccount, receiver, _ids[i]);
        }
        _updateBalance(gasStart, _targetAccount);
    }

    ///////////////////// RELAYER FUNCTIONS FOR PRIVATE KEY HACKS /////////////////////////
    /// NOTE: Private key hack could change the back-up address to a malicious address
    /// TODO: How do you prevent private key hack where malicious back-up set then fake exploit?

    // NOTE: Flushing all assets to a multi-sig wallet should avoid the private key hack
    // NOTE: Assets are only accessible if multiple wallets are compromised = safest options

    function flushERC20ToMultiSig(ERC20[] calldata _assets, address _targetAccount) external {
        uint256 gasStart = gasleft();
        require(subscriber[_targetAccount] == true, "NOT_SUBSCRIBED");
        address receiver = multiSigWallet[_targetAccount];
        for(uint256 i; i < _assets.length; i++) {
            uint256 amount = _assets[i].balanceOf(_targetAccount);
            _assets[i].transfer(receiver, amount);
        }
        _updateBalance(gasStart, _targetAccount);
    }

    function flushERC721ToMultiSig(ERC721[] calldata _assets, uint256[] calldata _ids, address _targetAccount) external {
        uint256 gasStart = gasleft();
        require(subscriber[_targetAccount] == true, "NOT_SUBSCRIBED");
        address receiver = multiSigWallet[_targetAccount];
        for(uint256 i; i < _assets.length; i++) {
            _assets[i].transferFrom(_targetAccount, receiver, _ids[i]);
        }
        _updateBalance(gasStart, _targetAccount);
    }

    ///////////////////// INTERNAL FUNCTIONS /////////////////////////
    /// @notice reduces the subscription coverage by gas used
    function _updateBalance(uint256 gasStart, address _account) internal {
        subscriptionEnd[_account] -= ((gasStart - gasleft()) * tx.gasprice) * 2;
    }
}
