pragma solidity ^0.4.11;

import "./Crowdsale.sol";

/**
   @title Presale event

   Implementation of the presale event. This event will start when the owner calls the `unpause()`
   function and will end when it paused again.

   There is a cap expressed in wei and a whitelist, meaning that only investors in that list are
   allowed to send their investments.

   Funds raised during this presale will be transfered to `wallet`.

 */

contract QiibeePresale is Crowdsale {

    using SafeMath for uint256;

    struct AccreditedInvestor {
      uint256 rate;
      uint64 cliff;
      uint64 vesting;
      uint256 minInvest;
      uint256 maxInvest;
    }

    mapping (address => AccreditedInvestor) public accredited; // whitelist of investors

    bool public isFinalized = false;

    event NewAccreditedInvestor(address indexed from, address indexed buyer);

    /*
     * @dev Constructor.
     * @param _startTime see `startTimestamp`
     * @param _endTime see `endTimestamp`
     * @param _goal see `see goal`
     * @param _cap see `see cap`
     * @param _maxGasPrice see `see maxGasPrice`
     * @param _minBuyingRequestInterval see `see minBuyingRequestInterval`
     * @param _wallet see `wallet`
     */
    function QiibeePresale(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _goal,
        uint256 _cap,
        uint256 _maxGasPrice,
        uint256 _minBuyingRequestInterval,
        address _wallet
    )
      Crowdsale(_startTime, _endTime, _goal, _cap, _maxGasPrice, _minBuyingRequestInterval, _wallet)
    {
    }

    /*
     * @param beneficiary beneficiary address where tokens are sent to
     */
    function buyTokens(address beneficiary) public payable whenNotPaused{
        require(beneficiary != address(0));
        require(validPurchase());

        AccreditedInvestor storage data = accredited[msg.sender];

        uint256 rate = data.rate;
        uint256 minInvest = data.minInvest;
        uint256 maxInvest = data.maxInvest;
        uint64 current = uint64(now);
        uint64 cliff = current + data.cliff;
        uint64 vesting = cliff + data.vesting;
        uint256 tokens = msg.value.mul(rate);

        // check investor's limits
        uint256 newBalance = balances[beneficiary].add(msg.value);
        require(newBalance <= maxInvest && msg.value >= minInvest);
        balances[beneficiary] = newBalance;

        // update state
        weiRaised = weiRaised.add(msg.value);
        tokensSold = tokensSold.add(tokens);

        // vest tokens TODO: check last two params
        if (data.cliff > 0 && data.vesting > 0) {
          token.grantVestedTokens(beneficiary, tokens, current, cliff, vesting, false, false);
        }

        token.mint(beneficiary, tokens);

        TokenPurchase(msg.sender, beneficiary, msg.value, tokens);

        forwardFunds();
    }

    /*
     * @dev Add an address to the accredited list.
     */
    function addAccreditedInvestor(address investor, uint256 rate, uint64 cliff, uint64 vesting, uint256 minInvest, uint256 maxInvest) public onlyOwner {
        require(investor != address(0));
        require(rate > 0);
        require(cliff >= 0);
        require(vesting >= 0);
        require(minInvest >= 0);
        require(maxInvest > 0);

        accredited[investor] = AccreditedInvestor(rate, cliff, vesting, minInvest, maxInvest);

        NewAccreditedInvestor(msg.sender, investor);
    }

    /*
     * @dev checks if an address is accredited
     * @return true if investor is accredited
     */
    function isAccredited(address investor) public constant returns (bool) {
        AccreditedInvestor storage data = accredited[investor];
        return data.rate > 0; //TODO: is there any way to check this?
    }

    /*
     * @dev Remove an address from the accredited list.
     */
    function removeAccreditedInvestor(address investor) public onlyOwner {
        require(investor != address(0));
        accredited[investor] = false;
    }


    // @return true if investors can buy at the moment
    function validPurchase() internal constant returns (bool) {
      require(isAccredited(msg.sender));
      return super.validPurchase();
    }

    /**
     * @dev Must be called after crowdsale ends, to do some extra finalization
     * work. Calls the contract's finalization function.
     */
    function finalize() public {
      require(!isFinalized);
      require(hasEnded());

      finalization();
      Finalized();

      isFinalized = true;

      // transfer the ownership of the token to the foundation
      token.transferOwnership(wallet);
    }

}
