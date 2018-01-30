pragma solidity ^0.4.19;


import "./Agricoin.sol";
import "./Owned.sol";


contract Ico is Owned
{
    enum State
    {
        Runned,     // Ico is running.
        Paused,     // Ico was paused.
        Finished,   // Ico has finished successfully.
        Expired,    // Ico has finished unsuccessfully.
        Failed
    }

    // Refund event.
    event Refund(address indexed investor, uint amount);

    // Investment event.
    event Invested(address indexed investor, uint amount);

    // End of ICO event.
    event End(bool result);

    // Ico constructor.
    function Ico(
        address tokenAddress,       // Agricoin contract address.
        uint tokenPreIcoPrice,      // Price of Agricoin in weis on Pre-ICO.
        uint tokenIcoPrice,         // Price of Agricoin in weis on ICO.
        uint preIcoStart,           // Date of Pre-ICO start.
        uint preIcoEnd,             // Date of Pre-ICO end.
        uint icoStart,              // Date of ICO start.
        uint icoEnd,                // Date of ICO end.
        uint preIcoEmissionTarget,  // Max number of Agricoins, which will be minted on Pre-ICO.
        uint icoEmissionTarget,     // Max number of Agricoins, which will be minted on ICO.
        uint icoSoftCap) public
    {
        owner = msg.sender;
        token = tokenAddress;
        state = State.Runned;
        
        // Save prices.
        preIcoPrice = tokenPreIcoPrice;
        icoPrice = tokenIcoPrice;

        // Save dates.
        startPreIcoDate = preIcoStart;
        endPreIcoDate = preIcoEnd;
        startIcoDate = icoStart;
        endIcoDate = icoEnd;

        preIcoTarget = preIcoEmissionTarget;
        icoTarget = icoEmissionTarget;
        softCap = icoSoftCap;
    }

    // Returns true if ICO is active now.
    function isActive() public view returns (bool)
    {
        return state == State.Runned;
    }

    // Returns true if date in Pre-ICO period.
    function isRunningPreIco(uint date) public view returns (bool)
    {
        return startPreIcoDate <= date && date <= endPreIcoDate;
    }

    // Returns true if date in ICO period.
    function isRunningIco(uint date) public view returns (bool)
    {
        return startIcoDate <= date && date <= endIcoDate;
    }

    // Fallback payable function.
    function () external payable
    {
        // Initialize variables here.
        uint value;
        uint rest;
        uint amount;
        
        if (state == State.Failed)
        {
            amount = invested[msg.sender] + investedOnPreIco[msg.sender];// Save amount of invested weis for user.
            invested[msg.sender] = 0;// Set amount of invested weis to zero.
            investedOnPreIco[msg.sender] = 0;
            Refund(msg.sender, amount);// Call refund event.
            msg.sender.transfer(amount + msg.value);// Returns funds to user.
            return;
        }

        if (state == State.Expired)// Unsuccessful end of ICO.
        {
            amount = invested[msg.sender];// Save amount of invested weis for user.
            invested[msg.sender] = 0;// Set amount of invested weis to zero.
            Refund(msg.sender, amount);// Call refund event.
            msg.sender.transfer(amount + msg.value);// Returns funds to user.
            return;
        }

        require(state == State.Runned);// Only for active contract.

        if (now >= endIcoDate)// After ICO period.
        {
            if (Agricoin(token).totalSupply() + Agricoin(token).totalSupplyOnIco() >= softCap)// Minted Agricoin amount above fixed SoftCap.
            {
                state = State.Finished;// Set state to Finished.

                // Get Agricoin info for bounty.
                uint decimals = Agricoin(token).decimals();
                uint supply = Agricoin(token).totalSupply() + Agricoin(token).totalSupplyOnIco();
                
                // Transfer bounty funds to Bounty contract.
                if (supply >= 1500000 * decimals)
                {
                    Agricoin(token).mint(bounty, 300000 * decimals, true);
                }
                else if (supply >= 1150000 * decimals)
                {
                    Agricoin(token).mint(bounty, 200000 * decimals, true);
                }
                else if (supply >= 800000 * decimals)
                {
                    Agricoin(token).mint(bounty, 100000 * decimals, true);
                }
                
                Agricoin(token).activate(true);// Activate Agricoin contract.
                End(true);// Call successful end event.
                msg.sender.transfer(msg.value);// Returns user's funds to user.
                return;
            }
            else// Unsuccessful end.
            {
                state = State.Expired;// Set state to Expired.
                Agricoin(token).activate(false);// Activate Agricoin contract.
                msg.sender.transfer(msg.value);// Returns user's funds to user.
                End(false);// Call unsuccessful end event.
                return;
            }
        }
        else if (isRunningPreIco(now))// During Pre-ICO.
        {
            require(investedSumOnPreIco / preIcoPrice < preIcoTarget);// Check for target.

            if ((investedSumOnPreIco + msg.value) / preIcoPrice >= preIcoTarget)// Check for target with new weis.
            {
                value = preIcoTarget * preIcoPrice - investedSumOnPreIco;// Value of invested weis without change.
                require(value != 0);// Check value isn't zero.
                investedSumOnPreIco = preIcoTarget * preIcoPrice;// Max posible number of invested weis in to Pre-ICO.
                investedOnPreIco[msg.sender] += value;// Increase invested funds by investor.
                Invested(msg.sender, value);// Call investment event.
                Agricoin(token).mint(msg.sender, value / preIcoPrice, false);// Mint some Agricoins for investor.
                msg.sender.transfer(msg.value - value);// Returns change to investor.
                return;
            }
            else
            {
                rest = msg.value % preIcoPrice;// Calculate rest/change.
                require(msg.value - rest >= preIcoPrice);
                investedSumOnPreIco += msg.value - rest;
                investedOnPreIco[msg.sender] += msg.value - rest;
                Invested(msg.sender, msg.value - rest);// Call investment event.
                Agricoin(token).mint(msg.sender, msg.value / preIcoPrice, false);// Mint some Agricoins for investor.
                msg.sender.transfer(rest);// Returns change to investor.
                return;
            }
        }
        else if (isRunningIco(now))// During ICO.
        {
            require(investedSumOnIco / icoPrice < icoTarget);// Check for target.

            if ((investedSumOnIco + msg.value) / icoPrice >= icoTarget)// Check for target with new weis.
            {
                value = icoTarget * icoPrice - investedSumOnIco;// Value of invested weis without change.
                require(value != 0);// Check value isn't zero.
                investedSumOnIco = icoTarget * icoPrice;// Max posible number of invested weis in to ICO.
                invested[msg.sender] += value;// Increase invested funds by investor.
                Invested(msg.sender, value);// Call investment event.
                Agricoin(token).mint(msg.sender, value / icoPrice, true);// Mint some Agricoins for investor.
                msg.sender.transfer(msg.value - value);// Returns change to investor.
                return;
            }
            else
            {
                rest = msg.value % icoPrice;// Calculate rest/change.
                require(msg.value - rest >= icoPrice);
                investedSumOnIco += msg.value - rest;
                invested[msg.sender] += msg.value - rest;
                Invested(msg.sender, msg.value - rest);// Call investment event.
                Agricoin(token).mint(msg.sender, msg.value / icoPrice, true);// Mint some Agricoins for investor.
                msg.sender.transfer(rest);// Returns change to investor.
                return;
            }
        }
        else
        {
            revert();
        }
    }

    // Pause contract.
    function pauseIco() onlyOwner external
    {
        require(state == State.Runned);// Only from Runned state.
        state = State.Paused;// Set state to Paused.
    }

    // Continue paused contract.
    function continueIco() onlyOwner external
    {
        require(state == State.Paused);// Only from Paused state.
        state = State.Runned;// Set state to Runned.
    }

    // End contract unsuccessfully.
    function endIco() onlyOwner external
    {
        require(state == State.Paused);// Only from Paused state.
        state = State.Failed;// Set state to Expired.
    }

    // Get invested ethereum.
    function getEthereum() onlyOwner external returns (uint)
    {
        require(state == State.Finished);// Only for successfull ICO.
        uint amount = this.balance;// Save balance.
        msg.sender.transfer(amount);// Transfer all funds to owner address.
        return amount;// Returns amount of transfered weis.
    }

    // Get invested ethereum from Pre ICO.
    function getEthereumFromPreIco() onlyOwner external returns (uint)
    {
        require(now >= endIcoDate);
        
        uint value = investedSumOnPreIco;
        investedSumOnPreIco = 0;
        msg.sender.transfer(value);
        return value;
    }

    // Invested balances.
    mapping (address => uint) invested;

    mapping (address => uint) investedOnPreIco;

    // State of contract.
    State public state;

    // Agricoin price in weis on Pre-ICO.
    uint public preIcoPrice;

    // Agricoin price in weis on ICO.
    uint public icoPrice;

    // Date of Pre-ICO start.
    uint public startPreIcoDate;

    // Date of Pre-ICO end.
    uint public endPreIcoDate;

    // Date of ICO start.
    uint public startIcoDate;

    // Date of ICO end.
    uint public endIcoDate;

    // Agricoin contract address.
    address public token;

    // Bounty contract address.
    address public bounty;

    // Invested sum in weis on Pre-ICO.
    uint public investedSumOnPreIco = 0;

    // Invested sum in weis on ICO.
    uint public investedSumOnIco = 0;

    // Target in tokens minted on Pre-ICo.
    uint public preIcoTarget;

    // Target in tokens minted on ICO.
    uint public icoTarget;

    // SoftCap fot this ICO.
    uint public softCap;
}