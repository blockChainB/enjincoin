pragma solidity ^0.4.15;

import './SafeMath.sol';
import './ERC20.sol';
import './EnjinReceivingContract.sol';

/**
 * @title Enjin Coin Custom Tokens (Mint) Contract
 * @dev Handles minting of custom game tokens
 * todo DRAFT / Work in progress, monolithic design version
 * todo Economy of scale curve needs re-do because of solidity math limitations
 * todo Unit Tests
 */
contract CustomTokens {
    using SafeMath for uint256;

    // this multiplier is needed for the minimum exchange rate of 1 and used for all division
    uint256 multiplier = 10000;
    ERC20 enjinCoin;
    uint256 index = 0;
    struct Tokens {
        address creator;
        uint256 totalSupply;
        uint256 exchangeRate;
        uint8 decimals;
        string name;
        string icon;
        string data;
        mapping (address => uint256) balances;
    }

    // customTokenId => Tokens
    mapping (uint256 => Tokens) types;

    /**
     * Default fallback function
     */
    function() { revert(); }

    /**
     * @dev Constructor
     * @param _enjinCoinToken Address of the deployed Enjin Coin ERC20 token contract
     */
    function CustomTokens(address _enjinCoinToken) {
        enjinCoin = ERC20(_enjinCoinToken);
    }

    /**
     * @dev Require that only the token creator can execute this function
     * @param _customTokenId The ID number of the Custom Token
     */
    function checkTokenCreator(uint256 _customTokenId) {
        require(msg.sender == types[_customTokenId].creator);
    }

    /**
     * @dev Get the balance of anyone's token
     * @param _customTokenId The ID number of the Custom Token
     * @return The _owner's token balance of the type requested
     */
    function balanceOf(uint256 _customTokenId, address _owner) constant returns (uint256) {
        return types[_customTokenId].balances[_owner];
    }

    /**
     * @dev Transfer Custom Tokens from a sender to an address
     * @param _customTokenId The ID number of the Custom Token
     * @param _to Address to send to
     * @param _value Number of tokens to send (omitting decimals)
     * @param _data Include data which will be passed to tokenFallback function
     */
    function transfer(uint256 _customTokenId, address _to, uint256 _value, bytes _data) {
        uint256 codeLength;

        assembly {
        // Retrieve the size of the code on target address, this needs assembly .
        codeLength := extcodesize(_to)
        }

        types[_customTokenId].balances[msg.sender] = types[_customTokenId].balances[msg.sender].sub(_value);
        types[_customTokenId].balances[_to] = types[_customTokenId].balances[_to].add(_value);
        if(codeLength>0) {
            EnjinReceivingContract receiver = EnjinReceivingContract(_to);
            receiver.tokenFallback(msg.sender, _value, _data);
        }
        Transfer(_customTokenId, msg.sender, _to, _value, _data);
    }

    /**
     * @dev Standard function transfer similar to ERC20 transfer with no _data, added for backward-compatibility and simple transfers
     * @param _customTokenId The ID number of the Custom Token
     * @param _to Address to send to
     * @param _value Number of tokens to send (omitting decimals)
     */
    function transfer(uint256 _customTokenId, address _to, uint256 _value) {
        uint256 codeLength;

        assembly {
        // Retrieve the size of the code on target address, this needs assembly .
        codeLength := extcodesize(_to)
        }

        types[_customTokenId].balances[msg.sender] = types[_customTokenId].balances[msg.sender].sub(_value);
        types[_customTokenId].balances[_to] = types[_customTokenId].balances[_to].add(_value);

        bytes memory empty; // todo: see if we can just pass "" instead of this variable
        if(codeLength>0) {
            EnjinReceivingContract receiver = EnjinReceivingContract(_to);
            receiver.tokenFallback(msg.sender, _value, empty);
        }
        Transfer(_customTokenId, msg.sender, _to, _value, empty);
    }

    /**
     * @dev Private function that transfers Custom Tokens between two addresses
     * @param _customTokenId The ID number of the Custom Token
     * @param _from Address to send from
     * @param _to Address to send to
     * @param _value Number of tokens to send (omitting decimals)
     */
    function transferInternal(uint256 _customTokenId, address _from, address _to, uint256 _value) private {
        require(_to != address(0));

        types[_customTokenId].balances[_from] = types[_customTokenId].balances[_from].sub(_value);
        types[_customTokenId].balances[_to] = types[_customTokenId].balances[_to].add(_value);
    }

    /**
     * @dev Create and mint a new Custom Token type, committing ENJ to the reserve and receiving the newly minted tokens
     * @param _totalSupply The total supply of Custom Tokens that will be created
     * @param _exchangeRate How many ENJ each unit is worth (using multiplier 10000)
     * @param _decimals Number of Decimal places (0 for indivisible items)
     * @param _name Human name of the item, ex. Sword of Satoshi
     * @param _icon URL to the 500x500px icon representing the item
     * @param _customData Optional data string to store custom game attributes in an item
     * @return index
     */
    function createToken(uint256 _totalSupply, uint256 _exchangeRate, uint8 _decimals, string _name, string _icon, string _customData)
    returns (uint256) {
        require(_totalSupply > 0);

        // Economy-of-scale calculation forcing the minimum exchange rate to start at 1 ENJ : 1 Custom Token and then decrease w/ exponential decay
        // Check for <1 because of possible 0 with integer math - this results in the lowest exchange rate of 1 (w/multiplier) after 100,000,000 units
        // todo: Rewrite this with 100M/x for solidity int math and match the curve
        //require(_exchangeRate >= (_totalSupply ** (-5 / 10)) * multiplier && _exchangeRate > 0);

        // Check ENJ allowance that Mint may take from creator
        uint256 totalCost = _exchangeRate / multiplier * _totalSupply;
        require(enjinCoin.allowance(msg.sender, this) >= totalCost);

        // Take ENJ from creator
        enjinCoin.transferFrom(msg.sender, this, totalCost);

        // Register the new token
        index++;

        types[index] = Tokens(
            msg.sender,
            _totalSupply,
            _exchangeRate,
            _decimals,
            _name,
            _icon,
            _customData
        );

        // Grant tokens to creator
        types[index].balances[msg.sender] = _totalSupply;

        // Event
        Create(index, msg.sender);

        return index;
    }

    /**
     * @dev Liquidate a custom token into ENJ. The Mint contract gains ownership of the liquidated custom tokens until re-minting by the creator
     * @param _customTokenId The ID number of the Custom Token
     * @param _value How many tokens to liquidate
     */
    function liquidateToken(uint256 _customTokenId, uint256 _value) {
        // todo: We may want another function signature that liquidates and transfers to a specific address instead of original sender
        require(types[_customTokenId].balances[msg.sender] >= _value);

        transferInternal(_customTokenId, msg.sender, this, _value);
        enjinCoin.transferFrom(this, msg.sender, types[_customTokenId].exchangeRate / multiplier * _value); // todo: check this calculation carefully
        Liquidate(_customTokenId, msg.sender, _value);
    }

    /**
     * @dev Re-mint any custom tokens that have been taken out of circulation
     * @param _customTokenId The ID number of the Custom Token
     * @param _value How many tokens to mint
     */
    function mintToken(uint256 _customTokenId, uint256 _value) {
        checkTokenCreator(_customTokenId);

        // Ensure enough tokens have been liquidated and are held for re-minting
        require(types[_customTokenId].balances[this] <= _value);

        // Check ENJ allowance that Mint may take from creator
        uint256 totalCost = types[_customTokenId].exchangeRate / multiplier * _value;
        require(enjinCoin.allowance(msg.sender, this) >= totalCost);

        // Take ENJ from creator
        enjinCoin.transferFrom(msg.sender, this, totalCost);

        // Grant tokens to creator
        transferInternal(_customTokenId, this, msg.sender, _value);

        // Event
        Mint(_customTokenId, _value);
    }

    /**
     * @dev Delete a custom token type. There must be 0 in circulation and this must be run by the token creator.
     * @param _customTokenId The ID number of the Custom Token
     */
    function deleteToken(uint256 _customTokenId) {
        checkTokenCreator(_customTokenId);

        // A Custom Token may only be deleted if its total supply is fully liquidated
        require(types[_customTokenId].balances[this] == types[_customTokenId].totalSupply);

        delete types[_customTokenId];

        Delete(_customTokenId, msg.sender);
    }

    /**
     * @dev Delete a custom token type. There must be 0 in circulation and this must be run by the token creator.
     * @param _customTokenId The ID number of the Custom Token
     * @param _name Human name of the item, ex. Sword of Satoshi
     * @param _icon URL to the 500x500px icon representing the item
     * @param _customData Optional data string to store custom game attributes in an item
     */
    function updateParams(uint256 _customTokenId, string _name, string _icon, string _customData) {
        checkTokenCreator(_customTokenId);

        types[_customTokenId].name = _name;
        types[_customTokenId].icon = _icon;
        types[_customTokenId].data = _customData;

        Update(_customTokenId, _name, _icon, _customData);
    }

    /**
     * @dev Get the name of a Custom Token
     * @param _customTokenId The ID number of the Custom Token
     */
    function getParams(uint256 _customTokenId) constant returns (address creator, uint256 totalSupply, uint256 exchangeRate, uint8 decimals, string name, string icon, string data) {
        creator = types[_customTokenId].creator;
        totalSupply = types[_customTokenId].totalSupply;
        exchangeRate = types[_customTokenId].exchangeRate;
        decimals = types[_customTokenId].decimals;
        name = types[_customTokenId].name;
        icon = types[_customTokenId].icon;
        data = types[_customTokenId ].data;
    }

    /**
     * @dev Allows the current token creator to transfer control of the custom token to a new creator.
     * @param _customTokenId The ID number of the Custom Token
     * @param _creator The address to transfer ownership to.
     */
    function assign(uint256 _customTokenId, address _creator) {
        checkTokenCreator(_customTokenId);
        if (_creator != address(0)) {
            types[_customTokenId].creator = _creator;
        }

        Assign(_customTokenId, msg.sender, _creator);
    }

    /**
     * @dev Events
     */
    event Create(uint256 indexed _customTokenId, address indexed _creator);
    event Liquidate(uint256 indexed _customTokenId, address indexed _owner, uint256 _value);
    event Mint(uint256 indexed _customTokenId, uint256 _value);
    event Delete(uint256 indexed _customTokenId, address indexed _creator);
    event Update(uint256 indexed _customTokenId, string _name, string _icon, string _customData);
    event Transfer(uint256 indexed _customTokenId, address indexed _from, address indexed _to, uint256 _value, bytes _data);
    event Assign(uint256 indexed _customTokenId, address indexed _from, address indexed _to);
}
