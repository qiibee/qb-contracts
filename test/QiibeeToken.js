var help = require('./helpers');
// var _ = require('lodash');

var BigNumber = web3.BigNumber;

require('chai')
  .use(require('chai-bignumber')(BigNumber))
  .should();

var QiibeeToken = artifacts.require('./QiibeeToken.sol');
// var Message = artifacts.require('./Message.sol');

const LOG_EVENTS = true;

contract('qiibeeToken', function(accounts) {

  var token;
  var eventsWatcher;

  beforeEach(async function() {
    const initialRate = 6000;
    const preferentialRate = 8000;
    const goal = 360000000;
    const cap = 2400000000;

    const crowdsale = await help.simulateCrowdsale(
      initialRate,
      preferentialRate,
      new BigNumber(help.toAtto(goal)),
      new BigNumber(help.toAtto(cap)),
      accounts,
      [40,30,20,10,0]
    );
    token = QiibeeToken.at(await crowdsale.token());

    //TODO: do we need to add something else here? PrivatePresale? Whitelist?
    eventsWatcher = token.allEvents();

    eventsWatcher.watch(function(error, log){
      if (LOG_EVENTS)
        console.log('Event:', log.event, ':',log.args);
    });
  });

  afterEach(function(done) {
    eventsWatcher.stopWatching();
    done();
  });

  it('has name, symbol and decimals', async function() {
    assert.equal('QBX', await token.SYMBOL());
    assert.equal('qiibeeCoin', await token.NAME());
    assert.equal(18, await token.DECIMALS());
  });

  it('can burn tokens', async function() {
    let totalSupply = await token.totalSupply.call();
    new BigNumber(0).should.be.bignumber.equal(await token.balanceOf(accounts[5]));

    let initialBalance = web3.toWei(1);
    await token.transfer(accounts[5], initialBalance, { from: accounts[1] });
    initialBalance.should.be.bignumber.equal(await token.balanceOf(accounts[5]));

    let burned = web3.toWei(0.3);

    assert.equal(accounts[0], await token.owner());

    // pause the token
    await token.pause({from: accounts[0]});

    try {
      await token.burn(burned, {from: accounts[5]});
      assert(false, 'burn should have thrown');
    } catch (error) {
      if (!help.isInvalidOpcodeEx(error)) throw error;
    }
    await token.unpause({from: accounts[0]});

    // now burn should work
    await token.burn(burned, {from: accounts[5]});

    new BigNumber(initialBalance).minus(burned).
      should.be.bignumber.equal(await token.balanceOf(accounts[5]));
    totalSupply.minus(burned).should.be.bignumber.equal(await token.totalSupply.call());
  });

});
