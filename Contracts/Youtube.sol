//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@api3/airnode-protocol/contracts/rrp/requesters/RrpRequesterV0.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@api3/contracts/v0.8/interfaces/IProxy.sol";


contract Youtube is RrpRequesterV0, Ownable {

    event RequestedUint256(bytes32 indexed requestId);
    event ReceivedUint256(bytes32 indexed requestId, int256 response);

    address public proxyAddress;

    address public airnode;
    address public sponsorWallet;
    bytes32 public endpointId;

    uint256 public returnedResponse;

    mapping(bytes32 => bool) public incomingFulfillments;

    // Creating a range for users to bet within scope
    enum Range { OneTo100, Hundred1To1000, Thousand1To5000, Five001To10000, Ten001AndBeyond }
    
    // Structure to hold bettor and their bet range
    struct Bet {
        address payable bettor;
        Range betRange;
    }
    
    Bet[] public bets;

    constructor(address _rrpAddress) RrpRequesterV0(_rrpAddress) {}

    // Set our price feed 
    function setProxyAddress(address _proxyAddress) public onlyOwner {
        proxyAddress = _proxyAddress;
    }

    // Setup Airnode Parameters
    function setRequestParameters(
        address _airnode,
        bytes32 _endpointId,
        address _sponsorWallet
    ) external onlyOwner {
        airnode = _airnode;
        endpointId = _endpointId;
        sponsorWallet = _sponsorWallet;
    }

    //The main makeRequest function that will trigger the Airnode request.
    function makeRequest(
        bytes calldata parameters
    ) external {
        bytes32 requestId = airnodeRrp.makeFullRequest(
            airnode,
            endpointId,
            address(this),
            sponsorWallet,
            address(this),
            this.fulfill.selector,
            parameters
        );
        incomingFulfillments[requestId] = true;
        emit RequestedUint256(requestId);
    }

    // This is the response from the Airnode request
    // It should return with a number of youtube views for that video
    function fulfill(bytes32 requestId, bytes calldata data)
        external
        onlyAirnodeRrp
    {
        require(incomingFulfillments[requestId], "No such request made");
        delete incomingFulfillments[requestId];
        int256 decodedData = abi.decode(data, (int256));
        returnedResponse = uint256(decodedData);
        executeBets(returnedResponse);
        emit ReceivedUint256(requestId, decodedData);
    }

    //Require all bets be at least 20 dollars in USD Value depending on price of ETH
    function placeBet(Range _betRange) public payable {
        /* Note - There is no timestamp to stop last minute bets
           For production, we want to ensure that there is a time system to ensure 
           that time is given for betters and a grace period is set before execution */
        require(_betRange >= Range.OneTo100 && _betRange <= Range.Ten001AndBeyond, "Invalid bet range");
        (uint256 price, ) = readDataFeed();

        // Convert the amount being paid (in wei) to its equivalent in USD (in wei format)
        uint256 amountInUSDWei = (msg.value * price) / 1e18;
        // Convert the USD amount in wei format to a regular USD amount
        uint256 amountInUSD = amountInUSDWei / 1e18;

        require(amountInUSD >= 20, "Amount should be more than $20 in USD value");
        
        Bet memory newBet;
        newBet.bettor = payable(msg.sender);
        newBet.betRange = _betRange;
        bets.push(newBet);
    }

    function executeBets(uint256 number) internal {
        Range winningRange;
        if (number >= 1 && number <= 100) {
            winningRange = Range.OneTo100;
        } else if (number >= 101 && number <= 1000) {
            winningRange = Range.Hundred1To1000;
        } else if (number >= 1001 && number <= 5000) {
            winningRange = Range.Thousand1To5000;
        } else if (number >= 5001 && number <= 10000) {
            winningRange = Range.Five001To10000;
        } else {
            winningRange = Range.Ten001AndBeyond;
        }
        
        uint256 totalWinners = 0;
        
        for (uint i = 0; i < bets.length; i++) {
            if (bets[i].betRange == winningRange) {
                totalWinners++;
            }
        }
        
        if (totalWinners == 0) {
            return;
        }

        uint256 prizePerWinner = address(this).balance / totalWinners;
        for (uint i = 0; i < bets.length; i++) {
            if (bets[i].betRange == winningRange) {
                (bool success, ) = payable(bets[i].bettor).call{value: prizePerWinner}("");
                require(success, "Failed payout");
            }
        }
        // Reset bets
        delete bets;
    }

    function readDataFeed() public view returns (uint256, uint256) {
        (int224 value, uint256 timestamp) = IProxy(proxyAddress).read();
        //convert price to UINT256
        uint256 price = uint224(value);
        return (price, timestamp);
    }


}