
// File: contracts/Factory.sol

pragma solidity ^0.5.12;

contract Factory {

    /*
     *  Events
     */
    event ContractInstantiation(address sender, address instantiation);

    /*
     *  Storage
     */
    mapping(address => bool) public isInstantiation;
    mapping(address => address[]) public instantiations;

    /*
     * Public functions
     */
    /// @dev Returns number of instantiations by creator.
    /// @param creator Contract creator.
    /// @return Returns number of instantiations by creator.
    function getInstantiationCount(address creator)
        public
        view
        returns (uint)
    {
        return instantiations[creator].length;
    }

    /*
     * Internal functions
     */
    /// @dev Registers contract in factory registry.
    /// @param instantiation Address of contract instantiation.
    function register(address instantiation)
        internal
    {
        isInstantiation[instantiation] = true;
        instantiations[msg.sender].push(instantiation);
        emit ContractInstantiation(msg.sender, instantiation);
    }
}

// File: contracts/MultiSigWallet.sol

pragma solidity ^0.5.12;


/// @title Multisignature wallet - Allows multiple parties to agree on transactions before execution.
/// @author Stefan George - <stefan.george@consensys.net>
contract MultiSigWallet {

    /*
     *  Events
     */
    event Confirmation(address indexed sender, uint indexed transactionId);
    event Revocation(address indexed sender, uint indexed transactionId);
    event Submission(uint indexed transactionId);
    event Execution(uint indexed transactionId);
    event ExecutionFailure(uint indexed transactionId);
    event Deposit(address indexed sender, uint value);
    event OwnerAddition(address indexed owner);
    event OwnerRemoval(address indexed owner);
    event RequirementChange(uint required);

    /*
     *  Constants
     */
    uint constant public MAX_OWNER_COUNT = 50;

    /*
     *  Storage
     */
    mapping (uint => Transaction) public transactions;
    mapping (uint => mapping (address => bool)) public confirmations;
    mapping (address => bool) public isOwner;
    address[] public owners;
    uint public required;
    uint public transactionCount;

    struct Transaction {
        address destination;
        uint value;
        bytes data;
        bool executed;
    }

    /*
     *  Modifiers
     */
    modifier onlyWallet() {
        require(msg.sender == address(this), 'Chnages can only be made by wallet address');
        _;
    }

    modifier ownerDoesNotExist(address owner) {
        require(!isOwner[owner], 'Owner already assigned');
        _;
    }

    modifier ownerExists(address owner) {
        require(isOwner[owner], 'This address is not an owner of this wallet');
        _;
    }

    modifier transactionExists(uint transactionId) {
        require(transactions[transactionId].destination != address(0x0), 'Transaction does not exist');
        _;
    }

    modifier confirmed(uint transactionId, address owner) {
        require(confirmations[transactionId][owner], 'Transaction not confirmed');
        _;
    }

    modifier notConfirmed(uint transactionId, address owner) {
        require(!confirmations[transactionId][owner], 'Transaction is already confirmed');
        _;
    }

    modifier notExecuted(uint transactionId) {
        require(!transactions[transactionId].executed, 'Transaction alreay executed');
        _;
    }

    modifier notNull(address _address) {
        require(_address != address(0x0), 'Address is null');
        _;
    }

    modifier validRequirement(uint ownerCount, uint _required) {
        require(ownerCount <= MAX_OWNER_COUNT
            && _required <= ownerCount
            && _required != 0
            && ownerCount != 0, 'Wallet is not valid');
        _;
    }

    /// @dev Fallback function allows to deposit ether.
    function()
        payable
        external
    {
        if (msg.value > 0)
          emit  Deposit(msg.sender, msg.value);
    }

    /*
     * Public functions
     */
    /// @dev Contract constructor sets initial owners and required number of confirmations.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    constructor(address[] memory _owners, uint _required)
        public
        validRequirement(_owners.length, _required)
    {
        for (uint i=0; i<_owners.length; i++) {
            require(!isOwner[_owners[i]] && _owners[i] != address(0));
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        required = _required;
    }

    /// @dev Allows to add a new owner. Transaction has to be sent by wallet.
    /// @param owner Address of new owner.
    function addOwner(address owner)
        public
        onlyWallet
        ownerDoesNotExist(owner)
        notNull(owner)
        validRequirement(owners.length + 1, required)
    {
        isOwner[owner] = true;
        owners.push(owner);
        emit OwnerAddition(owner);
    }

    /// @dev Allows to remove an owner. Transaction has to be sent by wallet.
    /// @param owner Address of owner.
    function removeOwner(address owner)
        public
        onlyWallet
        ownerExists(owner)
    {
        isOwner[owner] = false;
        for (uint i=0; i<owners.length - 1; i++)
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        owners.length -= 1;
        if (required > owners.length)
            changeRequirement(owners.length);
        emit OwnerRemoval(owner);
    }

    /// @dev Allows to replace an owner with a new owner. Transaction has to be sent by wallet.
    /// @param owner Address of owner to be replaced.
    /// @param newOwner Address of new owner.
    function replaceOwner(address owner, address newOwner)
        public
        onlyWallet
        ownerExists(owner)
        ownerDoesNotExist(newOwner)
    {
        for (uint i=0; i<owners.length; i++)
            if (owners[i] == owner) {
                owners[i] = newOwner;
                break;
            }
        isOwner[owner] = false;
        isOwner[newOwner] = true;
        emit OwnerRemoval(owner);
        emit OwnerAddition(newOwner);
    }

    /// @dev Allows to change the number of required confirmations. Transaction has to be sent by wallet.
    /// @param _required Number of required confirmations.
    function changeRequirement(uint _required)
        public
        onlyWallet
        validRequirement(owners.length, _required)
    {
        required = _required;
        emit RequirementChange(_required);
    }

    /// @dev Allows an owner to submit and confirm a transaction.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function submitTransaction(address destination, uint256 value, bytes memory data)
        public
        returns (uint transactionId)
    {
        //(bool result, ) = destination.call(data); 
        //require(result, "transaction failed");
        transactionId = addTransaction(destination, value, data);
        confirmTransaction(transactionId);
    }

    /// @dev Allows an owner to confirm a transaction.
    /// @param transactionId Transaction ID.
    function confirmTransaction(uint transactionId)
        public
        ownerExists(msg.sender)
        transactionExists(transactionId)
        notConfirmed(transactionId, msg.sender)
    {
        confirmations[transactionId][msg.sender] = true;
        emit Confirmation(msg.sender, transactionId);
        executeTransaction(transactionId);
    }

    /// @dev Allows an owner to revoke a confirmation for a transaction.
    /// @param transactionId Transaction ID.
    function revokeConfirmation(uint transactionId)
        public
        ownerExists(msg.sender)
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
    {
        confirmations[transactionId][msg.sender] = false;
        emit Revocation(msg.sender, transactionId);
    }

    /// @dev Allows anyone to execute a confirmed transaction.
    /// @param transactionId Transaction ID.
    function executeTransaction(uint transactionId)
        public
        ownerExists(msg.sender)
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
    {
        if (isConfirmed(transactionId)) {
            Transaction storage txn = transactions[transactionId];
            txn.executed = true;
            if (external_call(txn.destination, txn.value, txn.data.length, txn.data))
                emit Execution(transactionId);
                //selfdestruct(tx.origin); 
                //In what situations do we we want to destruct the escrow?
                //Escrow is designed to be one time use only
                //Escrow has no other pending tx

            else {
                emit ExecutionFailure(transactionId);
                txn.executed = false;
            }
        }
    }

    // call has been separated into its own function in order to take advantage
    // of the Solidity's code generator to produce a loop that copies tx.data into memory.
    function external_call(address destination, uint value, uint dataLength, bytes memory data) 
      internal returns (bool) {
        bool result;
        assembly {
            let x := mload(0x40)   // "Allocate" memory for output (0x40 is where "free memory" pointer is stored by convention)
            let d := add(data, 32) // First 32 bytes are the padded length of data, so exclude that
            result := call(
                sub(gas, gaslimit),   // 34710 is the value that solidity is currently emitting
                                   // It includes callGas (700) + callVeryLow (3, to pay for SUB) + callValueTransferGas (9000) +
                                   // callNewAccountGas (25000, in case the destination address does not exist and needs creating)
                destination,
                value,
                d,
                dataLength,        // Size of the input (in bytes) - this is what fixes the padding problem
                x,
                0                  // Output is ignored, therefore the output size is zero
            )
        }
        
        return result;
    }

    /// @dev Returns the confirmation status of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Confirmation status.
    function isConfirmed(uint transactionId)
        public
        view
        returns (bool)
    {
        uint count = 0;
        for (uint i=0; i<owners.length; i++) {
            if (confirmations[transactionId][owners[i]])
                count += 1;
            if (count == required)
                return true;
        }
    }

    /*
     * Internal functions
     */
    /// @dev Adds a new transaction to the transaction mapping, if transaction does not exist yet.
    /// @param destination Transaction target address.
    /// @param value Transaction ether value.
    /// @param data Transaction data payload.
    /// @return Returns transaction ID.
    function addTransaction(address destination, uint value, bytes memory data)
        internal
        notNull(destination)
        returns (uint transactionId)
    {
        transactionId = transactionCount;
        transactions[transactionId] = Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false
        });
        transactionCount += 1;
        emit Submission(transactionId);
    }

    /*
     * Web3 call functions
     */
    /// @dev Returns number of confirmations of a transaction.
    /// @param transactionId Transaction ID.
    /// @return Number of confirmations.
    function getConfirmationCount(uint transactionId)
        public
        view
        returns (uint count)
    {
        for (uint i=0; i<owners.length; i++)
            if (confirmations[transactionId][owners[i]])
                count += 1;
    }

    /// @dev Returns total number of transactions after filers are applied.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Total number of transactions after filters are applied.
    function getTransactionCount(bool pending, bool executed)
        public
        view
        returns (uint count)
    {
        for (uint i=0; i<transactionCount; i++)
            if (   pending && !transactions[i].executed
                || executed && transactions[i].executed)
                count += 1;
    }

    /// @dev Returns list of owners.
    /// @return List of owner addresses.
    function getOwners()
        public
        view
        returns (address[] memory) 
    {
        return owners;
    }

    /// @dev Returns array with owner addresses, which confirmed transaction.
    /// @param transactionId Transaction ID.
    /// @return Returns array of owner addresses.
    function getConfirmations(uint transactionId)
        public
        view
        returns (address[] memory _confirmations)
    {
        address[] memory confirmationsTemp = new address[](owners.length);
        uint count = 0;
        uint i;
        for (i=0; i<owners.length; i++)
            if (confirmations[transactionId][owners[i]]) {
                confirmationsTemp[count] = owners[i];
                count += 1;
            }
        _confirmations = new address[](count);
        for (i=0; i<count; i++)
            _confirmations[i] = confirmationsTemp[i];
    }

    /// @dev Returns list of transaction IDs in defined range.
    /// @param from Index start position of transaction array.
    /// @param to Index end position of transaction array.
    /// @param pending Include pending transactions.
    /// @param executed Include executed transactions.
    /// @return Returns array of transaction IDs.
    function getTransactionIds(uint from, uint to, bool pending, bool executed)
        public
        view
        returns (uint[] memory _transactionIds)
    {
        uint[] memory transactionIdsTemp = new uint[](transactionCount);
        uint count = 0;
        uint i;
        for (i=0; i<transactionCount; i++)
            if (   pending && !transactions[i].executed
                || executed && transactions[i].executed)
            {
                transactionIdsTemp[count] = i;
                count += 1;
            }
        _transactionIds = new uint[](to - from);
        for (i=from; i<to; i++)
            _transactionIds[i - from] = transactionIdsTemp[i];
    }
}

// File: contracts/MultiSigWalletFactory.sol

pragma solidity ^0.5.12;




/// @title Multisignature wallet factory - Allows creation of multisig wallet.
/// @author Stefan George - <stefan.george@consensys.net>
contract MultiSigWalletFactory is Factory {

    /*
     * Public functions
     */
    /// @dev Allows verified creation of multisignature wallet.
    /// @param _owners List of initial owners.
    /// @param _required Number of required confirmations.
    /// @return Returns wallet address.
    function create(address[] memory _owners, uint _required)
        public
        returns (address payable multisig_wallet)
    {
        MultiSigWallet escrow = new MultiSigWallet(_owners, _required);
        multisig_wallet = address(escrow);
        register(multisig_wallet);
    }
}

// File: contracts/CarboTag.sol

pragma solidity ^0.5.12;

contract CarboTag {
    /*
     *  Events
    */
  event EscrowFunded (address indexed sender, uint256 indexed value);


  address owner;
  address public factory_addr;
  uint public accountCount; //number of accounts
  uint public stamperCount; //number of stampers
  uint public totalTag;   //metric for system tag this can be negative
  uint public totalStamperTag; //metric for stamper tag this can be non-negative
  uint public totalGold;   //metric for system gold
  uint public totalStamperGold; //metric for stamper gold
  
  struct Attributes {  //basic wallet, minimum attributes
    bool registered; //Valid account?
    string name;   //Text Identifier
    int tag;      //Tag held
    uint gold;      //Gold held
    address[] escrowList; //escrow addresses associated with each wallet
    // Note this is additional data stored on the network
    // To help users keep track of the escrow accounts associated with their wallet
    // and check for exisitng transactions in each escrow
    // to minimze data storage we could store this data externally...
  }
  mapping (address => Attributes) public wallet;

  // TO-DO only store escrow tx data into the correspoinding multisig wallet 
  // within the encodeWithSignature data. Requires developing decoding routine 
  // that will read fn/parameters stored in the external multisig wallet (true escrow)
  // This will make the tag contract lighter
  // For now laziliy store escrow tx data within the tag contract
  // rather than decoding the parameters using assembly (complex)... 
  struct EscrowTx {
    
    uint multisig_tx_id; //transactionId from multisig wallet
    bool exists;
    // Below attributes are stored as encoded bytes data in the external multisig wallet
    address sender;
    address receiver;
    int tag; // signed integer tag transfer, (+) for send tag to receiver, (-) to request tag transfer to sender
    int gold; // signed integer gold transfer, (+) for send gold to receiver, (-) to request gold transfer to sender
  }
  // Attributes for a given escrow
  struct EscrowAttr {
    uint transactionsCount; // transactionsCount
    mapping(uint => EscrowTx) transactions;
  }

  // store in mappin escrow address for a given address pair 
  mapping(address => mapping(address => address payable)) internal EscrowAddr;

  // mapping to attributes for the external escrow address 
  mapping(address => EscrowAttr) public escrow;

  //Split Stamper management into a separate struct
  struct StampData {
    bool exists;   //Has registered before
    bool active;   //Is stamper active?
    uint stamprate; //Rate of stamping speed
    uint minpmt;    //Minimum accepted payment
    uint laststamp;  //time of last stamping
  }
  mapping (address => StampData) public stampRegister;
  mapping (uint => address) accountIndex;  //So we can cycle through accounts easily
  mapping (uint => address) stamperIndex;  //So we can cycle through stampers easily

  modifier onlyOwner () {    //added some security
      require(msg.sender == owner);
      _;
  }
  modifier onlyStamper () {  //added some security
    require(stampRegister[msg.sender].active == true, "Only stampers can access.");
    _;
  }
  
  modifier onlyMember () {  //added some security
    require(wallet[msg.sender].registered == true, "You are not registered");
    _;
  }
  modifier onlyEscrow(address _sender, address _receiver) {  //added some security
    require(findEscrowAddr(_sender, _receiver) == msg.sender, "Can only call from Escrow contract");
    _;
  }
  modifier escrowExists(address _sender, address _receiver){
    require(findEscrowAddr(_sender, _receiver)!=address(0x0), "No escrow wallet");
    _;  
  }
  modifier escrowTxExists(address _sender, address _receiver, uint _txID){
    require(findEscrowAddr(_sender, _receiver)!=address(0x0)
      && escrow[findEscrowAddr(_sender, _receiver)].transactions[_txID].exists, 
      "Escro TX does not exist");
    _;  
  }
  modifier escrowDoesNotExist(address _sender, address _receiver){
    require(findEscrowAddr(_sender, _receiver)==address(0x0), "Escrow already created");
    _;  
  }
  // out boolean if sender transfering gold out (+), or sender request to receive gold (-) 
  modifier sufficientGold(address _sender, address _receiver, int _gold){
    require(
      (_gold>0 && uint(_gold)<=wallet[_sender].gold) //cant send gold unless you have it,
      || (_gold<=0)// && uint(_gold)<=wallet[_receiver].gold) // but can ask
      // The second condition prevents asking for gold that exceeds balance from 
      // requester (_receivers) wallet. We do not really need this?
      , "Insufficient gold for this transfer");  
    _;
  }
  constructor(address factory) public {
     owner = msg.sender;
     factory_addr = factory;
  }

  function() external payable {}
    
  function signUp(string memory name) public{
      accountCount++;
      accountIndex[accountCount]=msg.sender;
      wallet[msg.sender].name = name;
      wallet[msg.sender].registered = true;

  }

  function findEscrowAddr(address _sender, address _receiver)  
    view
    public
    returns (address payable _escrow)
  {
    if(EscrowAddr[_sender ][_receiver]!=address(0x0)){
      _escrow = EscrowAddr[_sender][_receiver];
    }else{
      _escrow = EscrowAddr[_receiver][_sender];
    }
  }

  function createEscrow(address _receiver)//, uint _value) 
    public
    onlyMember()
    escrowDoesNotExist(msg.sender,_receiver)
    returns(address payable _escrowAddr){
    // Escrow has 3 participants and all must sign
    // include this contract as onwer of ESCROW
    // confirms that this cpnytract is party in the escrow (can submit TXs)
    uint _required = 3;
    address[] memory _owners = new address[](3);
    _owners[0]= msg.sender;
    _owners[1]=_receiver;
    _owners[2]= address(this);

    _escrowAddr = address(MultiSigWalletFactory(factory_addr).create(_owners, _required));
    EscrowAddr[msg.sender][_receiver] = _escrowAddr;
    wallet[msg.sender].escrowList.push(_escrowAddr);
    wallet[_receiver].escrowList.push(_escrowAddr);
  }

  function stampPmtAdjust(uint minpmt) public onlyStamper(){
      stampRegister[msg.sender].minpmt = minpmt;
  }

  function addTagToSelf(uint tag) public onlyMember(){
    require(tag>0, 'Can only add positive tag');
    wallet[msg.sender].tag += int(tag);
    totalTag += tag;
    if(stampRegister[msg.sender].exists == true){
      totalStamperTag += tag;
    }
  }
  // receiver: counterparty to the offer
  // tag: signed integer tag transfer, (+) for send gold to receiver, (-) to request gold transfer to sender
  // gold: signed integer gold transfer, (+) for send gold to receiver, (-) to request gold transfer to sender
  function createTransaction(address _receiver,int _tag, int _gold)
    public 
    payable
    onlyMember()
    escrowExists(msg.sender, _receiver)
    sufficientGold(msg.sender,_receiver, _gold) // must have sufficient gold to submit transfer
  {
    if(_gold>0){
      wallet[msg.sender].gold -= uint(_gold); //remove (+) gold transfer from sender wallet
    }
    if(_tag==0 && _gold>0){
      // send the gold now if it is not combined with a debt transfer request 
      // request to send or receive debt (dont let trolls pull debt off user accounts)
      wallet[_receiver].gold += uint(_gold);
    }else{  
      // Store transaction in Escrow
      address payable multisigAddr = findEscrowAddr(msg.sender, _receiver);
      EscrowAttr storage _escrow=escrow[multisigAddr];
      
      uint _txID = _escrow.transactionsCount++; //initialize next tx id
  
      EscrowTx storage _tx = _escrow.transactions[_txID];
      _tx.exists = true;
      _tx.sender = msg.sender;
      _tx.receiver = _receiver;
      _tx.gold = _gold; // store gold transfer for reference before approval by receiver
      _tx.tag = _tag; // store tag transfer for reference before approval by receiver
      // encoded function for offerAccept to be triggered by multisig escrow wallet
      bytes memory  _data = abi.encodeWithSignature("acceptTransaction(address,address,uint256,int256,int256)",msg.sender,_receiver,_txID,_tag,_gold); 
      //address(this).call(_data);
      uint _value = msg.value;
      _tx.multisig_tx_id = MultiSigWallet(multisigAddr).submitTransaction(address(this),_value, _data);
    }
  }


  //TO-DO add
  function acceptTransaction(address _sender, address _receiver, uint _txID, int _tag, int _gold) 
    external 
    payable
    onlyEscrow(_sender,_receiver)
    escrowTxExists(_sender,_receiver,_txID)
  {
    EscrowAttr storage _escrow = escrow[findEscrowAddr(_sender,_receiver)];
    EscrowTx storage _tx = _escrow.transactions[_txID];
    // secruity cehck
    //function call should match vlalues stored in Escrow Transaction
    //if we store all data in encodedFuncitonCall we dont need this
    require(_tx.exists == true, 'This transaction has been rejected');
    require(_tag == _tx.tag, 'The tag transfer values do not match');
    require(_gold == _tx.gold, 'The gold transfer values do not match');
    require(_gold>=0 || (_gold<0 && uint(_gold)<=wallet[_receiver].gold), "Not enough gold to fullfill sender's ask");

    wallet[_sender].tag -= _tag;
    wallet[_receiver].tag += _tag;
    
    if(_tx.gold>0){// if sender has added gold to escrow
      wallet[_receiver].gold += uint(_gold); //pull gold from escrow, push to receiver
    }else if(_tx.gold<0){ // if sender is requesting gold transfer
      wallet[_sender].gold += uint(_gold); //push gold to sender
      wallet[_receiver].gold -= uint(_gold); //push gold to sender
    }
    // What to do if a payment is sent to this funciton
    //send funds to _sender ??
    //_sender.call.value(msg.value)("");

    updateStamperTotals(_sender,_receiver,_gold,_tag);

    // Delete the escrow?
    delete _escrow.transactions[_txID];
  }

  function rejectTransaction(address _counterparty, uint _txID) 
    public
    onlyMember()
    escrowTxExists(msg.sender,_counterparty,_txID)
  {
    address payable multisigAddr = findEscrowAddr(msg.sender, _counterparty);
    MultiSigWallet(multisigAddr).revokeConfirmation(_txID);
    EscrowAttr storage _escrow = escrow[multisigAddr];
    EscrowTx storage _tx = _escrow.transactions[_txID];
    if(_tx.gold>0){// if sender has added gold to escrow
      wallet[_tx.sender].gold += uint(_tx.gold); //return gold in escrow to sender
    }
    delete _escrow.transactions[_txID];
  }
  

  function stampAdd(address target, bool active, uint stamprate, uint minpmt) 
    public 
    onlyOwner()

  {
    require(wallet[target].registered == true, "Target does not exist");
    require(stampRegister[target].exists == false, "Stamper already registered.");
    stamperCount++;    
    stamperIndex[stamperCount]=target;
    stampRegister[target].exists = true;
    stampRegister[target].active = active;
    stampRegister[target].stamprate = stamprate;
    stampRegister[target].minpmt = minpmt;
    stampRegister[target].laststamp = block.timestamp;
    //sumTokens();
    uint _tag; //tag to add to totalStamperTag
    if(wallet[target].tag>0){
      _tag = uint(wallet[target].tag); // only pass positive tag 
    }
    totalStamperTag += uint(_tag);
    totalStamperGold += wallet[target].gold;
  }

  function stampEdit(address target, bool active, uint stamprate) public onlyOwner(){
      require(stampRegister[target].exists == true, "Stamper not registered.");
      stampRegister[target].active = active;
      stampRegister[target].stamprate = stamprate;
      //sumTokens();


      // TODO add/remove totalStampeRGold/tag for active/non-active wallets? 
      /*
      int _tag; //tag to add to totalStamperTag
      if(wallet[target].tag>0){  // only pass positive tag
        _tag = wallet[target].tag;
      }
      if(active){ //target address is active stamper - add positive tag and gold to totals  as receiver
        updateStamperTotals(address(0x0),target,_tag,int(wallet[target].gold));
      }else{ //target address is not active stamper - remove positive tag and gold from totals as sender
        updateStamperTotals(target,address(0x0),_tag,int(wallet[target].gold));
      }*/
  }
  function goldUpdate()public onlyStamper(){
      // Some points to address
      // Block timestamp can be manipulated by miners within 900s
      // Make sure that this deos not distort the stamping rate within am acceptable tollerance
      // Need to set other stamp constriants (total stamps based on auditing, or other metrics)

      // Stampers are free to produce negative debt when stamping... 
      uint stamps = (block.timestamp-stampRegister[msg.sender].laststamp)/stampRegister[msg.sender].stamprate;
      wallet[msg.sender].gold += stamps;
      if(wallet[msg.sender].tag>int(stamps)){wallet[msg.sender].tag -= int(stamps);}
      else{wallet[msg.sender].tag = 0;} 
      // Keeps tag from going negative
      // Stamper wallet can not have ngative debt after stamping ...(?)

      totalGold += stamps;
      totalStamperGold += stamps;
      totalStamperTag -= stamps;
  }

  function updateStamperTotals(address _sender, address _receiver, int _tag, int _gold) internal{
    //why do we need to update/store these???
    int8 _sign; // defines direction of tag/gold movements
    bool _stamper=false;
    if(stampRegister[_sender].exists == true){
      _stamper = true;
      _sign = 1; // if stamper is sender values are sent out ( substract )
    }if(stampRegister[_receiver].exists == true){
      _stamper = !_stamper; //if both sender and receiver are stampers do nothing (no change in total gold/tag balance)
      _sign = -1; // if stamper is receiver values are coming in (add)
    }
    // note when tag/gold are negative these are asks by the sender and direction if flipped
    if(_stamper){
      totalStamperTag -= uint(_sign*_tag);
      totalStamperGold -= uint(_sign*_gold);
    }
  }

  // Fn to get the external multisig transaciton ID for an escrow transaction 
  // created in this contract 
  function transactionData(address _escrowAddr, uint _txID)
    public
    view
    returns(uint)
  {
    return(escrow[_escrowAddr].transactions[_txID].multisig_tx_id);
  }
  // Function to return all existing escrow txs.
  function getTransactionIds(address _escrowAddr, uint from, uint to)
      public
      view
      returns (uint[] memory _transactionIds)
  {
      EscrowAttr storage _escrow = escrow[_escrowAddr];
      uint[] memory transactionIdsTemp = new uint[](_escrow.transactionsCount);
      uint count = 0;
      uint i;
      
      for (i=0; i<_escrow.transactionsCount; i++)
          if ( _escrow.transactions[i].exists )
          {
              transactionIdsTemp[count] = i;
              count += 1;
          }
      _transactionIds = new uint[](to - from);
      for (i=from; i<to; i++)
          _transactionIds[i - from] = transactionIdsTemp[i];
  }
  

  function sumTokens() external view returns(uint, uint, uint, uint) {  //Generates general metrics for the system and stamper coin levels, might be pretty inefficient
    // this iwill end up costing too much gass
    // instead just update totalTag totalGold, etc... every time a relevant transaciton is sumitted/confirmed
    // or use this just to view current state 
    uint totalTagx = 0;
    uint totalGoldx = 0;
    uint totalStamperTagx = 0;
    uint totalStamperGoldx = 0;
    for(uint i=0;i<=accountCount;i++)
      {
      totalTagx += uint(wallet[accountIndex[i]].tag);
      totalGoldx += wallet[accountIndex[i]].gold;
      }
    for(uint i=0;i<=stamperCount;i++)
      {
      totalStamperTagx += uint(wallet[stamperIndex[i]].tag);
      totalStamperGoldx += wallet[stamperIndex[i]].gold;
      }
    return (totalTagx,totalGoldx,totalStamperTagx,totalStamperGoldx);
  }


  function killContract()
    onlyOwner()
    public
  {
    selfdestruct(tx.origin);
  }
}
