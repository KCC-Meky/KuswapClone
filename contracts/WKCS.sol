pragma solidity 0.8.0;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/utils/math/SafeMath.sol";


contract WETH is IERC20 {
    using SafeMath for uint256;

    string public constant name = "Wrapped ETH on Ethereum";
    string public constant symbol = "WETH";
    string public constant version = "1";
    uint8 public constant decimals = 18;
    bytes2 constant private EIP191_HEADER = 0x1901;
    bytes32 public constant EIP712_UNWRAP_TYPEHASH = keccak256("Unwrap(address holder,uint256 amount,uint256 nonce,uint256 expiry)");
    bytes32 public constant EIP712_PERMIT_TYPEHASH = keccak256(
        "Permit(address holder,address spender,uint256 nonce,uint256 expiry,bool allowed)"
    );
    bytes32 public EIP712_DOMAIN_SEPARATOR;
    uint256 private _totalSupply;
    address public defaultOperator;
    address public defaultOperatorController;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowed;
    mapping (address => uint256) public unwrapNonces;
    mapping (address => uint256) public permitNonces;

    event Deposit(address indexed dst, uint256 amount);
    event Withdrawal(address indexed src, uint256 amount);

    constructor (address _operator, uint256 _chainId, address _defaultOperatorController) public {
        defaultOperator = _operator;
        defaultOperatorController = _defaultOperatorController;
        EIP712_DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                _chainId,
                address(this)
            )
        );
    }

    modifier onlyDefaultOperatorController() {
        require(
            msg.sender == defaultOperatorController,
            "ONLY_DEFAULT_OPERATOR_CONTROLLER"
        );
        _;
    }

    fallback() external payable  {
        _deposit(msg.sender, msg.value);
    }
    
    function setDefaultOperator(address newDefaultOperator) external onlyDefaultOperatorController {
        defaultOperator = newDefaultOperator;
    }

    function metaWithdraw(
        address payable holder,
        uint256 amount,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                EIP191_HEADER,
                EIP712_DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        EIP712_UNWRAP_TYPEHASH,
                        holder,
                        amount,
                        nonce,
                        expiry
                    )
                )
            )
        );

        require(holder != address(0), "INVALID_HOLDER");
        require(holder == ecrecover(digest, v, r, s), "INVALID_SIGNATURE");
        require(expiry == 0 || block.timestamp <= expiry, "META_WITHDRAW_EXPIRED");
        require(nonce == unwrapNonces[holder]++, "INVALID_NONCE");
        require(_balances[holder] >= amount, "INSUFFICIENT_BALANCE");

        _withdraw(holder, amount);
    }

    function permit(
        address holder,
        address spender,
        uint256 nonce,
        uint256 expiry,
        bool allowed,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                EIP712_DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        EIP712_PERMIT_TYPEHASH,
                        holder,
                        spender,
                        nonce,
                        expiry,
                        allowed
                    )
                )
            )
        );

        require(holder != address(0), "INVALID_HOLDER");
        require(holder == ecrecover(digest, v, r, s), "INVALID_SIGNATURE");
        require(expiry == 0 || block.timestamp <= expiry, "PERMIT_EXPIRED");
        require(nonce == permitNonces[holder]++, "INVALID_NONCE");
        uint256 wad = allowed ? type(uint256).max : 0;
        _allowed[holder][spender] = wad;
        emit Approval(holder, spender, wad);
    }

    function totalSupply() override public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address owner) override public view returns (uint256) {
        return _balances[owner];
    }

    function allowance(address owner, address spender) override public view returns (uint256) {
        return _allowed[owner][spender];
    }

    function transfer(address to, uint256 value) override public returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) override public returns (bool) {
        require(spender != address(0), "SPENDER_INVALID");

        _allowed[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) override public returns (bool) {
        _allowed[from][msg.sender] = _allowed[from][msg.sender].sub(value);
        _transfer(from, to, value);
        emit Approval(from, msg.sender, _allowed[from][msg.sender]);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        require(spender != address(0), "SPENDER_INVALID");

        _allowed[msg.sender][spender] = _allowed[msg.sender][spender].add(addedValue);
        emit Approval(msg.sender, spender, _allowed[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        require(spender != address(0), "SPENDER_INVALID");

        _allowed[msg.sender][spender] = _allowed[msg.sender][spender].sub(subtractedValue);
        emit Approval(msg.sender, spender, _allowed[msg.sender][spender]);
        return true;
    }

    function withdraw(uint256 amount) public {
        require(_balances[msg.sender] >= amount, "INSUFFICIENT_BALANCE");
        address payable withdrawUser = payable(msg.sender);
        _withdraw(withdrawUser, amount);
    }

    function _transfer(address from, address to, uint256 value) private {
        require(to != address(0), "SPENDER_INVALID");

        _balances[from] = _balances[from].sub(value);
        _balances[to] = _balances[to].add(value);
        emit Transfer(from, to, value);
    }

    function _withdraw(address payable holder, uint256 amount) private {
        _balances[holder] = _balances[holder].sub(amount);
        holder.transfer(amount);
        emit Withdrawal(holder, amount);
    }

    function _deposit(address sender, uint256 amount) public payable {
        _balances[sender] = _balances[sender].add(amount);
        uint256 senderAllowance = _allowed[sender][defaultOperator];
        if (senderAllowance == 0) {
            _allowed[sender][defaultOperator] = type(uint256).max;
        }
        emit Deposit(sender, amount);
    }
}