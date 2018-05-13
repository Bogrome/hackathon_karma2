/**
 *
 *  MIT License
 *
 *  Copyright (c) 2018 Vladimir Khramov
 *
 *  Permission is hereby granted, free of charge, to any person obtaining a copy
 *  of this software and associated documentation files (the "Software"), to deal
 *  in the Software without restriction, including without limitation the rights
 *  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 *  copies of the Software, and to permit persons to whom the Software is
 *  furnished to do so, subject to the following conditions:
 *
 *  The above copyright notice and this permission notice shall be included in all
 *  copies or substantial portions of the Software.
 *
 *  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 *  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 *  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 *  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 *  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 *  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 *  SOFTWARE.
 */

pragma solidity ^0.4.17;

import 'openzeppelin-solidity/contracts/math/SafeMath.sol';
import './AtomicSwapRegistry.sol';
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';

contract Exchange is Ownable {
    using SafeMath for uint256;

    function Exchange(address _swapRegistry) public {
        swapRegistry = AtomicSwapRegistry(_swapRegistry);
    }

    /**
     * Blockchains to swap with (one of them with be useless, since exchange contract will be deployed to it)
     */
    uint8 constant ETH = 1;
    uint8 constant ETH_KOVAN = 2;
    uint8 constant ETH_RINKEBY = 3;
    uint8 constant EOS = 4;
    uint8 constant BITCOIN = 5;

    enum OpType {BUY, SELL}

    struct Band {
        address initiator;

        uint currencyCount;
        uint priceInWei;

        OpType opType;
    }

    /*****************************************************************/

    mapping(uint8 => Band[]) public bands;

    mapping(address => bytes32[]) hashes;

    mapping (address => uint) public deposits;

    AtomicSwapRegistry public swapRegistry;

    /*****************************************************************/

    function buy(uint8 _secondBlockchain, uint _currencyCount, uint _priceInWeiForOneUnit) public {
        //todo hardcoded only ether like decimals (18)
        uint totalEther = _priceInWeiForOneUnit.mul(_currencyCount).div(1 ether);

        require(totalEther <= deposits[msg.sender]);
        deposits[msg.sender] = deposits[msg.sender].sub(totalEther);

        uint restCurrencyCount = _currencyCount;
        // todo optimization :(
        for(uint i=0; i<bands[_secondBlockchain].length; i++) {
            if (restCurrencyCount==0) {
                continue;
            }
            require(hashes[msg.sender].length>0);//todo more than orders

            Band storage band = bands[_secondBlockchain][i];
            if (band.opType==OpType.BUY) {
                continue;
            }

            //todo minimum price, since not we get first suitable price
            if (band.priceInWei > _priceInWeiForOneUnit) {
                continue;
            }

            //todo split bands/orders
            if (band.currencyCount == _currencyCount) {

                uint weiCount = band.priceInWei.mul(_currencyCount).div(1 ether);
                swapRegistry.initiate.value(weiCount)(msg.sender, 7200, getNextHash(msg.sender), band.initiator);
                restCurrencyCount = restCurrencyCount.sub(band.currencyCount);

                uint spread = _priceInWeiForOneUnit.sub(band.priceInWei).mul(_currencyCount).div(1 ether);
                owner.transfer(spread);
            }
        }

        if (restCurrencyCount > 0) {
            bands[_secondBlockchain].push(
                Band(
                    msg.sender,
                    restCurrencyCount,
                    _priceInWeiForOneUnit,
                    OpType.BUY
                )
            );
        }
    }


    function sell(uint8 _secondBlockchain, uint _currencyCount, uint _priceInWeiForOneUnit) public {
        require(_currencyCount > 0);
        require(_priceInWeiForOneUnit > 0);

        uint restCurrencyCount = _currencyCount;
        // todo optimization :(
        for(uint i=0; i<bands[_secondBlockchain].length; i++) {
            if (restCurrencyCount==0) {
                continue;
            }
            Band storage band = bands[_secondBlockchain][i];
            if (band.opType==OpType.SELL) {
                continue;
            }

            //todo minimum price, since not we get first suitable price
            if (band.priceInWei < _priceInWeiForOneUnit) {
                continue;
            }

            if (hashes[band.initiator].length==0) {
                continue;
            }

            //todo split bands/orders
            if (band.currencyCount == _currencyCount) {

                uint weiCount = _priceInWeiForOneUnit.mul(_currencyCount).div(1 ether);

                swapRegistry.initiate.value(weiCount)(band.initiator, 7200, getNextHash(band.initiator), msg.sender);
                restCurrencyCount = restCurrencyCount.sub(band.currencyCount);

                uint spread = band.priceInWei.sub(_priceInWeiForOneUnit).mul(_currencyCount).div(1 ether);
                owner.transfer(spread);
                //todo how to do better?
            }
        }

        if (restCurrencyCount > 0) {
            bands[_secondBlockchain].push(
                Band(
                    msg.sender,
                    restCurrencyCount,
                    _priceInWeiForOneUnit,
                    OpType.SELL
                )
            );
        }
    }

    /*****************************************************************/
    function myHashesCount() view public returns (uint) {
        return hashes[msg.sender].length;
    }

    function addHashes(bytes32 _hash1, bytes32 _hash2, bytes32 _hash3, bytes32 _hash4, bytes32 _hash5) public {
        // for front in smartz params in this way
        bytes32[5] memory newHashes = [_hash1, _hash2, _hash3, _hash4, _hash5];
        for (uint i = 0; i < newHashes.length; i++) {
            if (newHashes[i] != 0) {
                //todo check that hash has been never used
                hashes[msg.sender].push(newHashes[i]);
            }
        }

    }

    function getNextHash(address _addr) internal returns (bytes32 result) {
        assert(hashes[_addr].length > 0);

        result = hashes[_addr][ hashes[_addr].length-1 ];
        hashes[_addr].length -= 1;
    }

    /*****************************************************************/

    function myDeposit() view public returns (uint) {
        return deposits[msg.sender];
    }

    function deposit() public payable {
        deposits[msg.sender] += msg.value;
    }

    function withdraw(uint _amount) public {
        //todo check orders
        require(deposits[msg.sender] >= _amount);

        deposits[msg.sender] -= _amount;

        msg.sender.transfer(_amount);
    }
}

