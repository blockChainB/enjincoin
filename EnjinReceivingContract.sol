pragma solidity ^0.4.15;

/*
* Contract that works with Enjin Custom tokens
*/

contract EnjinReceivingContract {
    function tokenFallback(address _from, uint _value, bytes _data);
}