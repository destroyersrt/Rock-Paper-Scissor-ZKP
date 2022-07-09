// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.10;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./verifier.sol";
import "hardhat/console.sol";


contract Game is ReentrancyGuard{

    enum GameState {Open, InProgress, Proving, Reveal, Result, Abandoned}

    struct Match{
         
        address player1; // 20bytes
        bool betMatch; // 1 byte
        GameState state; // 1 byte
        uint64 betSize; // let's say 10 ETH // 8 bytes
        uint8[2] decodedChoice;  // range [1-3] // 2 bytes
        address player2; // 20 bytes 
        uint64[4] encodedChoiceP1; 
        uint64[4] encodedChoiceP2;
        uint64 gameStartSnapShot; // 8 bytes
        bool[2] proofs; // 2 bytes
        uint8[2] choices; // 2 bytes
        bool[2] isRevealed; // 2 bytes

    }

    // owner address
    address public owner;

    // ZKP-Verifier Address
    Verifier public immutable verifier;

    // gameId -> games 
    mapping(uint256 => Match) public games;

    // playerAddress -> amount
    mapping(address => uint256) public claims;

    // current Number of games
    uint256 public gameCount;


    constructor(Verifier _verifier) {

        owner = msg.sender;
        verifier = _verifier;

    }

    function createGame() 
        external 
        payable
        returns(uint gameId) 
        {
            // ---- CHECKS ----
            require(msg.sender != address(0), "Call from invalid address");

            // ---- EFFECTS ----
            Match storage mat = games[gameCount];
            
            if(msg.value > 0) {

                mat.betMatch = true;
                mat.betSize = uint64(msg.value);

            }

            mat.state = GameState.Open;
            mat.player1 = payable(msg.sender);
            
            gameId = gameCount;
            gameCount++;

    }    

    function joinGame(uint gameId) 
        external
        payable
        {
            // ---- CHECKS

            require(msg.sender != address(0), "Call from invalid Address");
            require(games[gameId].player1 != address(0),"No game with this GameId");
            require(games[gameId].player1 != msg.sender, "You can't verse yourself");
            require(games[gameId].state == GameState.Open,"Game not allowing players to Join");


            if(games[gameId].betMatch) {
                
                require(uint64(msg.value) == games[gameId].betSize, "Need to deposit betSize amount");

            } else {
                
                require(msg.value == 0, "You don't need to submit any bet");

            }

            // ---- EFFECTS             

            games[gameId].player2 = msg.sender;
            games[gameId].state = GameState.InProgress;
            games[gameId].gameStartSnapShot = uint64(block.timestamp);

        }
    
    function submitEncodedChoice(uint gameId, uint64[4] memory choiceHash) 
        external
        { 
        // ---- CHECKS ----

        require(games[gameId].state == GameState.InProgress, "State not in progress");
        
        if(block.timestamp > games[gameId].gameStartSnapShot + 1 days) {
            
            games[gameId].state = GameState.Abandoned;
            
            if(games[gameId].betMatch) {
                
                if(games[gameId].encodedChoiceP1[0] != 0) {
            
                    claims[games[gameId].player1] += 2*(games[gameId].betSize);
            
                } else if(games[gameId].encodedChoiceP2[0] != 0) {
            
                    claims[games[gameId].player2] += 2*(games[gameId].betSize);
            
                } else {
            
                    claims[owner] += 2*games[gameId].betSize;
            
                }
                
            }
            
            return;
        }

        if(msg.sender == games[gameId].player1) {
            
            require(games[gameId].encodedChoiceP1[0] == 0, "already submitted a choice");
            games[gameId].encodedChoiceP1 = choiceHash;

        } else if(msg.sender == games[gameId].player2) {
            
            require(games[gameId].encodedChoiceP2[0] == 0, "already submitted a choice");
            games[gameId].encodedChoiceP2 = choiceHash;

        } else {
            // todo return an error saying not the player;
            return;
        
        }

        if(games[gameId].encodedChoiceP1[0] != 0  && games[gameId].encodedChoiceP2[0] != 0) {

            games[gameId].state = GameState.Proving;

        }


    }

    function submitProof(uint256 gameId, Verifier.Proof memory _proof) 
        external 
        {

        require(games[gameId].state == GameState.Proving, "Not the proving state");

        if (block.timestamp > games[gameId].gameStartSnapShot + 2 days) {
            
            games[gameId].state = GameState.Abandoned;
            
            if(games[gameId].betMatch) {
                
                if(games[gameId].proofs[0]) {
            
                    claims[games[gameId].player1] += 2*(games[gameId].betSize);
            
                } else if(games[gameId].proofs[1]) {
            
                    claims[games[gameId].player2] += 2*(games[gameId].betSize);
            
                } else {
            
                    claims[owner] += 2*games[gameId].betSize;
            
                }
                
            }
            return;
        }

        uint256[4] memory encodedChoice;

        if(msg.sender == games[gameId].player1) {
            
            require(!games[gameId].proofs[0], "Already submitted correct proof");
             
            for(uint256 i = 0; i < 4; i++) {
                
                encodedChoice[i] = uint256(games[gameId].encodedChoiceP1[i]);    
            
            }
            // EXTERNAL CALL

            games[gameId].proofs[0] = verifier.verifyTx(_proof,encodedChoice);

        } else if (msg.sender == games[gameId].player2) {

            require(!games[gameId].proofs[1],"Already submitted correct proof");
            
            for(uint256 i = 0; i < 4; i++) {
              
                encodedChoice[i] = uint256(games[gameId].encodedChoiceP2[i]);    
            
            }
        
            games[gameId].proofs[1] = verifier.verifyTx(_proof,encodedChoice);
        
        } else {
            // todo return an error - caller not a player
            return;
        }


        if(games[gameId].proofs[0] && games[gameId].proofs[1]) {

            games[gameId].state = GameState.Reveal;

        }

    }

    function revealChoice(uint256 gameId, uint8 choice, uint64[4] memory salt)
        external 
        {
        
        require(games[gameId].state == GameState.Reveal, "GameState is not Reveal");

        if(block.timestamp > games[gameId].gameStartSnapShot + 3 days) {

            games[gameId].state = GameState.Abandoned;
            
            if(games[gameId].betMatch) {
                
                if(games[gameId].isRevealed[0]) {
            
                    claims[games[gameId].player1] += 2*(games[gameId].betSize);
            
                } else if(games[gameId].isRevealed[1]) {
            
                    claims[games[gameId].player2] += 2*(games[gameId].betSize);
            
                } else {
            
                    claims[owner] += 2*games[gameId].betSize;
            
                }
                
            }
            
            return;
        }

        bytes32 calculatedHash = keccak256(abi.encodePacked(salt[0],salt[1],salt[2],salt[3], uint64(choice)));
        bytes32 submittedHash;

        if(msg.sender == games[gameId].player1) {

            require(!games[gameId].isRevealed[0], "Already Reveal the choice");
            submittedHash = computeHash(games[gameId].encodedChoiceP1);
            require(submittedHash == calculatedHash, "hashes don't match");

            games[gameId].isRevealed[0] = true;
            games[gameId].choices[0] = choice;

        } else if( msg.sender == games[gameId].player2) {

            require(!games[gameId].isRevealed[1], "Already Reveal the choice");
            submittedHash = computeHash(games[gameId].encodedChoiceP2);
            require(submittedHash == calculatedHash, "hashes don't match");

            games[gameId].isRevealed[1] = true;
            games[gameId].choices[1] = choice;

        } else {
            // todo return an error - caller not a player
            return;
        }

        if(games[gameId].isRevealed[0] && games[gameId].isRevealed[1]) {

            games[gameId].state = GameState.Result;

        }
    }

    function computeHash(uint64[4] memory encodedChocie) 
        internal
        pure 
        returns (bytes32) 
        {

            return bytes32(abi.encodePacked(encodedChocie[0],encodedChocie[1],encodedChocie[2],encodedChocie[3]));
    
    }

    function computeWinner(uint256 gameId)
        external 
        {
        //  --- CHECKS

        require(games[gameId].state == GameState.Result,"GameState not Result");
        
        uint8 choiceP1 = games[gameId].choices[0];
        uint8 choiceP2 = games[gameId].choices[1];

        if(choiceP1 == choiceP2) {

            if(games[gameId].betMatch) {

                claims[games[gameId].player1] += games[gameId].betSize;
                claims[games[gameId].player2] += games[gameId].betSize;
                // emit draw() 
            }

        } else {
            if(choiceP1-1 == choiceP2%3) {
                // winner is P1
                claims[games[gameId].player1] += 2*(games[gameId].betSize);
                // emit winner
                
            } else {
                
                // winner is P2
                claims[games[gameId].player2] += 2*(games[gameId].betSize);
                // emit winner

            }
            
        }
    }

    function leaveGame(uint gameId) 
        external
        {
            // ---- CHECKS
            require(msg.sender == games[gameId].player1 && msg.sender != address(0));
            require(games[gameId].state == GameState.Open, "Game should be in joining state");

            if(games[gameId].betMatch == true) {
            
                claims[msg.sender] += games[gameId].betSize;
            
            }

            //  ---- EFFECTS
            
            games[gameId].state = GameState.Abandoned;

        }    

    function claim()
        external
        nonReentrant
        {
            // ---- CHECKS ----
            require(claims[msg.sender] != 0, "You don't have anything to claim");
            
            // ---- EFFECTS ----
            // ---- INTERACTION ----
            (bool success, ) = msg.sender.call{value: claims[msg.sender]}("");
            require(success, "Transfer failed.");

        }

    function getEncodedChoiceP1(uint256 gameId) 
        external 
        view 
        returns (uint64[4] memory) 
        {
        
            return games[gameId].encodedChoiceP1;

        }   

    function getEncodedChoiceP2(uint256 gameId) 
        external
        view
        returns (uint64[4] memory) 
        {
        
            return games[gameId].encodedChoiceP2;

        }

    function getIsProof(uint256 gameId)
        external
        view
        returns(bool[2] memory) 
        {
        
            return games[gameId].proofs;

        }

    function getIsRevealed(uint256 gameId) 
        external
        view
        returns (bool[2] memory) 
        {
        
            return games[gameId].isRevealed;

        }

    receive() external payable{

    }

    fallback() external payable {

    }

}