pragma solidity ^0.4.11;

import "zeppelin-solidity/contracts/lifecycle/Pausable.sol";
import "zeppelin-solidity/contracts/crowdsale/RefundVault.sol";
// import "./QiibeeToken.sol";

/**
   @title Crowdsale for the QBX Token Generation Event

   Implementation of kind of an 'abstract' Crowdsale. This contract will be
   used by QiibeePresale.sol and QiibeeCrowdsale.sol

   This Crowdsale is capped and has a spam prevention technique:
    * investors can make purchases with a minimum request inverval of X seconds given by minBuyingRequestInterval.
    * investors are limited in the gas price

   In case of the goal not being reached by purchases made during crowdsale period funds sent will
   be made available to be claimed by the originating addresses.

   The function buyTokens() does not mint tokens. This function should be overriden to add that logic.
 */

contract QiibeeToken {
  function mintVestedTokens(address _to,
    uint256 _value,
    uint64 _start,
    uint64 _cliff,
    uint64 _vesting,
    bool _revokable,
    bool _burnsOnRevoke,
    address _wallet
  ) returns (bool);
  function mint(address _to, uint256 _amount) returns (bool);
  function transferOwnership(address _wallet);
  function pause();
  function unpause();
  function finishMinting() returns (bool);
}

contract Crowdsale is Pausable {

    using SafeMath for uint256;

    uint256 public startTime;
    uint256 public endTime;

    uint256 public cap; // max amount of funds to be raised in wei
    uint256 public goal; // min amount of funds to be raised in wei
    RefundVault public vault; // refund vault used to hold funds while crowdsale is running

    uint256 public rate; // how many token units a buyer gets per wei

    QiibeeToken public token; // token being sold
    uint256 public tokensSold; // qbx minted (and sold)
    uint256 public weiRaised; // raised money in wei
    mapping (address => uint256) public balances; // balance of wei invested per investor

    // spam prevention
    mapping (address => uint256) public lastCallTime; // last call times by address
    uint256 public maxGasPrice; // max gas price per transaction
    uint256 public minBuyingRequestInterval; // min request interval for purchases from a single source (in seconds)

    bool public isFinalized = false; // whether the crowdsale has finished or not

    address public wallet; // address where funds are collected

    /*
     * @dev event for change wallet logging
     * @param wallet new wallet address
     */
    event WalletChange(address wallet);

    /**
     * event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value in wei paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    event Finalized();

    /*
     * @dev Constructor. Creates the token in a paused state
     * @param _startTime see `startTimestamp`
     * @param _endTime see `endTimestamp`
     * @param _rate see `see rate`
     * @param _goal see `see goal`
     * @param _cap see `see cap`
     * @param _maxGasPrice see `see maxGasPrice`
     * @param _minBuyingRequestInterval see `see minBuyingRequestInterval`
     * @param _wallet see `wallet`
     */
    function Crowdsale (
        uint256 _startTime,
        uint256 _endTime,
        uint256 _rate,
        uint256 _goal,
        uint256 _cap,
        uint256 _maxGasPrice,
        uint256 _minBuyingRequestInterval,
        address _wallet
    )
    {
        require(_startTime >= now);
        require(_endTime >= _startTime);
        require(_rate > 0);
        require(_cap > 0);
        require(_goal > 0);
        require(_goal <= _cap);
        require(_maxGasPrice > 0);
        require(_minBuyingRequestInterval > 0);
        require(_wallet != address(0));


        startTime = _startTime;
        endTime = _endTime;
        rate = _rate;
        cap = _cap;
        goal = _goal;
        maxGasPrice = _maxGasPrice;
        minBuyingRequestInterval = _minBuyingRequestInterval;
        wallet = _wallet;

        // token = new QiibeeToken();
        vault = new RefundVault(wallet);

        // token.pause();

    }

    /*
     * @dev fallback function can be used to buy tokens
     */
    function () payable whenNotPaused {
      buyTokens(msg.sender);
    }

    /*
     * @dev Low level token purchase function.
     * @param beneficiary address where tokens are sent to
     */
    function buyTokens(address beneficiary) public payable whenNotPaused {
      require(beneficiary != address(0));
      require(validPurchase());

      uint256 weiAmount = msg.value;

      // calculate token amount to be created
      uint256 tokens = weiAmount.mul(rate);

      // update state
      weiRaised = weiRaised.add(weiAmount);
      tokensSold = tokensSold.add(tokens);
      lastCallTime[msg.sender] = now;

      token.mint(beneficiary, tokens);
      TokenPurchase(msg.sender, beneficiary, weiAmount, tokens);

      forwardFunds();
    }

    /*
     * @return true if investors can buy at the moment
     */
    function validPurchase() internal constant returns (bool) {
      bool withinFrequency = now.sub(lastCallTime[msg.sender]) >= minBuyingRequestInterval;
      bool withinGasPrice = tx.gasprice <= maxGasPrice;
      bool withinPeriod = now >= startTime && now <= endTime;
      bool withinCap = weiRaised.add(msg.value) <= cap;
      bool nonZeroPurchase = msg.value != 0;
      return withinFrequency && withinGasPrice && withinPeriod && withinCap && nonZeroPurchase;
    }

    /*
     * @return true if crowdsale event has ended
     */
    function hasEnded() public constant returns (bool) {
      bool capReached = weiRaised >= cap;
      return now > endTime || capReached;
    }

    /*
     * @return true if crowdsale goal has reached
     */
    function goalReached() public constant returns (bool) {
      return weiRaised >= goal;
    }

    /*
     * In addition to sending the funds, we want to call the RefundVault deposit function
     */
    function forwardFunds() internal {
      vault.deposit.value(msg.value)(msg.sender);
    }

    /*
     * if crowdsale is unsuccessful, investors can claim refunds here
     */
    function claimRefund() public {
      require(isFinalized);
      require(!goalReached());

      vault.refund(msg.sender);
    }

    /**
     * @dev Must be called after crowdsale ends, to do some extra finalization
     * work. Calls the contract's finalization function.
     */
    function finalize() public onlyOwner {
      require(!isFinalized);
      require(hasEnded());

      finalization();
      Finalized();

      isFinalized = true;
    }

    /**
     * @dev Can be overridden to add finalization logic. The overriding function
     * should call super.finalization() to ensure the chain of finalization is
     * executed entirely.
     */
    function finalization() internal {
      if (goalReached()) {
        vault.close();
      } else {
        vault.enableRefunds();
      }
    }

    /*
     * @dev Changes the current wallet for a new one. Only the owner can call this function.
     * @param _wallet new wallet
     */
    function setWallet(address _wallet) onlyOwner public {
        require(_wallet != address(0));
        wallet = _wallet;
        WalletChange(_wallet);
    }

    /**
      @dev changes the token owner
    */
    //TODO: EXECUTE BEFORE START CROWDSALE
    function setToken(address tokenAddress) onlyOwner {
      require(now < startTime);
      token = QiibeeToken(tokenAddress);
    }


}
