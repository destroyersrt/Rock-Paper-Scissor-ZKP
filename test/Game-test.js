const {ethers} = require('hardhat');
const {expect} = require('chai');


describe("Rock Paper Scissor test", () => {

    let deployer, player1, player2;
    let game;
    const BET_SIZE = ethers.utils.parseEther('1');


    before(async() => {
        [deployer, player1, player2] = await ethers.getSigners();

        const Verifier = await ethers.getContractFactory('Verifier');
        const verifier = await Verifier.deploy();


        const GameFactory = await ethers.getContractFactory('Game');
        game =  await GameFactory.deploy(verifier.address);

        // Deployer should be the owner
        expect(
            await game.owner()
        ).to.be.equal(deployer.address);

        // verifier address should be verifier
        expect(
            await game.verifier()
        ).to.be.equal(verifier.address);

        // GameCount should be equal to
        expect(
            await game.gameCount()
       ).to.be.equal(0);

        // sets gameId
        gameId = await game.connect(player1).createGame({
           value: BET_SIZE
       }); 

    })
    
    describe("Player creates a Game and Leave -- non-zero Bet", () => {
        

        it("Player is able to create a game", async() => {
            let instance = await game.games(0);

            // instance player1 address should be player1's address
            expect(
                instance.player1
            ).to.be.equal(player1.address)
            
            // gameCount should be increased to 1
            expect(
                await game.gameCount()
            ).to.be.equal(1)
            
            // game's betSize should be 1 Ether
            expect(
                await instance.betSize
            ).to.be.equal(ethers.utils.parseEther('1'));
            
            // GameState should be OPEN
            expect(
                await instance.state
            ).to.be.equal(0)

        })

        it("Player2 can join the game", async () => {
            

            await game.connect(player2).joinGame(0,{
                value: BET_SIZE
            });

            let instance = await game.games(0);

            expect(
                await instance.player2
            ).to.be.equal(player2.address) 

            expect(
                await instance.state
            ).to.be.equal(1)

            expect(
                await instance.gameStartSnapshot
            ).to.not.equal(0)

        })

        it("Players submits the encodedChoice", async() => {

            await game.connect(player1).submitEncodedChoice(
                0,
                ["11804943091196839642","2893212809961427824", "4590175716267440011", "14875410631761412763"]
            )

            await game.connect(player2).submitEncodedChoice(
                0,                             
                ["5455366589862775137","14252626103636100779","8892337613839764846","3059451574168111488"]
            )

            let instance = await game.games(0);

            // states should be changed to Proving
            expect(
                await instance.state
            ).to.be.equal(2);
            
        })

        it("players submit proof", async() => {
            let proofP1 = [["0x2df224e32a05f6bf50182faf2096863aeed4f436bcecbec6fef28c21578081bd","0x0fd1b29646cabb38f047623c09045f791628cad206f1963f60365cc1701bdc87"],[["0x24a1eee26be212bb6e3889e9a583bf881bde534ea42fbe870d1b91ce217b34b4","0x2b39e4fd06a4966f3c3b175ced1bcef85eb81f277c4fb28079220f072fb4567a"],["0x091bfc17c16f6b3c2e833eca511bd5d017cacb07ac79be323e622e266706e67c","0x1553d03efacb73ad279ee966538fd3e22524b9b0c8e8e00977b004ccab32c15b"]],["0x140c6987b30b748b99fcb34cdb37c08cf046b1857b12deaaa54950f223bc4831","0x2666698ad81547600e6ba9b02cd0282a3dc4dc02e134d694d9acc2ead18749e0"]]
            let proofP2 = [["0x052b5b3a15a7e37d97815fa06f2b503c08fa665b545dcb1d156599b3c4dfab4e","0x23b106433e39702f604aa6da194b5f68cb29b50455be4eb0e08c09eefc40e9be"],[["0x1a534967882efe2542dbe8083d02a5499ece8897081f8ea9103d11d1eada79e4","0x2124ce2a5cebffdf9add726b73def00f362314b22bce802bd09bd83bfa7f9493"],["0x1625bd938314ce9b35aeeff2b755f06b45a5d6777518831c388cb4b4e9eaac26","0x0dde632143098bd1f94b8ff3b921209a06055742cbcac7bbe1f1b0cc50c77607"]],["0x0968e5439f5b88ab0d14d853f81aa7facbca55e9d8e792c8ade959ffce15cf39","0x2266ac230f30812711dbf3a74714155e9b7115f8bd8d8301f1c6331fbc82f128"]]
            
            await game.connect(player1).submitProof(0,proofP1);

            expect(
                await game.getIsProof(0)
            ).to.eql([true,false])
            
            await game.connect(player2).submitProof(0,proofP2);

            expect(
                await game.getIsProof(0)
            ).to.eql([true,true])
            
            let instance = await game.games(0);

            // states should be changed to Proving
            expect(
                await instance.state
            ).to.be.equal(3);
            
        })

        it("players reveal their choice", async() => {
            // 23 53 32 22
            await game.connect(player1).revealChoice(
                0,
                1,
                ["23","53","32","22"]
            );

            expect(
                await game.getIsRevealed(0)
            ).to.eql([true, false])
            
            // 123 456 789 321
            await game.connect(player2).revealChoice(
                0,
                1,
                ["123","456","789","321"]
            );

            expect(
                await game.getIsRevealed(0)
            ).to.eql([true, true])

            let instance = await game.games(0);

            expect(
                await instance.state
            ).to.be.equal(4)

        })

        it("Compute Winner", async () => {

            await game.computeWinner(0);

            // check claims
            expect (
                await game.claims(player1.address)
            ).to.be.equal(ethers.utils.parseEther('1'))
            
            expect (
                await game.claims(player2.address)
            ).to.be.equal(ethers.utils.parseEther('1'))
        })

    })
})