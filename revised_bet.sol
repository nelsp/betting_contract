// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;



//////////////////////////////////////////////////////////////////////////////*/

contract Bet {
    // ------------------------------------------------------------------ types

    enum State {
        Funding,   // waiting for one or both deposits
        Active,    // fully funded; can be conceded, ruled, or expired
        Resolved,  // a winner was determined; pot credited to winner
        Cancelled, // funding failed; deposits credited back
        Expired    // resolution deadline passed unresolved; deposits credited back
    }

    // ----------------------------------------------------------------- events

    event Deposited(address indexed player, uint256 amount);
    event Cancelled(address indexed by);
    event Conceded(address indexed loser, address indexed winner, uint256 pot);
    event Ruled(address indexed arbiter, address indexed winner, uint256 pot);
    event Expired(address indexed by);
    event Withdrawn(address indexed to, uint256 amount);

    // ---------------------------------------------------------------- storage

    // Parties and terms. Immutable: cannot change after deployment, and are
    // cheaper to read than storage.
    address public immutable bettor;
    address public immutable taker;
    address public immutable arbiter;       // address(0) means "no arbiter"
    uint256 public immutable bettorStake;   // wei the bettor must deposit
    uint256 public immutable takerStake;    // wei the taker must deposit
    bytes32 public immutable betDetailsHash; // keccak256 of the off-chain terms

    // Timeline (all UNIX timestamps).
    //   fundingDeadline    : both deposits must be in by this time
    //   eventDate          : earliest time the arbiter may rule
    //   resolutionDeadline : after this, anyone may expire an unresolved bet
    uint256 public immutable fundingDeadline;
    uint256 public immutable eventDate;
    uint256 public immutable resolutionDeadline;

    State public state;

    // Amount each player has actually deposited (0 or their stake).
    mapping(address => uint256) public deposited;

    // Pull-payment ledger. Winnings and refunds land here; owner calls withdraw().
    mapping(address => uint256) public pending;

    // Simple reentrancy guard for withdraw().
    bool private _locked;

    // -------------------------------------------------------------- modifiers

    modifier onlyPlayer() {
        require(msg.sender == bettor || msg.sender == taker, "not a player");
        _;
    }

    modifier inState(State s) {
        require(state == s, "wrong state");
        _;
    }

    modifier nonReentrant() {
        require(!_locked, "reentrant");
        _locked = true;
        _;
        _locked = false;
    }

    // ------------------------------------------------------------ constructor

    /// @param _bettor        first player
    /// @param _taker         second player
    /// @param _arbiter       trusted third party, or address(0) for none
    /// @param _bettorStake   wei the bettor must deposit (odds are encoded in
    ///                       the ratio of the two stakes)
    /// @param _takerStake    wei the taker must deposit
    /// @param _betDetailsHash keccak256 of the agreed terms text
    /// @param _fundingWindow seconds from now during which deposits are accepted
    /// @param _timeToEvent   seconds from now until the outcome is knowable
    /// @param _graceWindow   seconds after eventDate during which the winner can
    ///                       obtain a concession or arbiter ruling before the
    ///                       bet can be expired and refunded
    constructor(
        address _bettor,
        address _taker,
        address _arbiter,
        uint256 _bettorStake,
        uint256 _takerStake,
        bytes32 _betDetailsHash,
        uint256 _fundingWindow,
        uint256 _timeToEvent,
        uint256 _graceWindow
    ) {
        // Original had none of these checks. Each one closes a real hole:
        require(_bettor != address(0) && _taker != address(0), "zero address");
        require(_bettor != _taker, "players must differ");
        require(_arbiter != _bettor && _arbiter != _taker, "arbiter is a player");
        require(_bettorStake > 0 && _takerStake > 0, "zero stake");
        require(_fundingWindow > 0, "funding window");
        // Funding must close no later than the event, otherwise one side could
        // wait to see the outcome before deciding whether to fund.
        require(_fundingWindow <= _timeToEvent, "funding after event");
        // Grace window is what prevents the "loser refunds himself the moment
        // the deadline hits" race. Must be non-trivial.
        require(_graceWindow >= 1 hours, "grace too short");

        bettor = _bettor;
        taker = _taker;
        arbiter = _arbiter;
        bettorStake = _bettorStake;
        takerStake = _takerStake;
        betDetailsHash = _betDetailsHash;

        fundingDeadline = block.timestamp + _fundingWindow;
        eventDate = block.timestamp + _timeToEvent;
        resolutionDeadline = eventDate + _graceWindow;

        state = State.Funding;
    }

    // NOTE: no receive() and no fallback(). ETH can only enter via deposit().
    // The original's receive() was the source of the double-deposit /
    // wrong-amount / trapped-ether problems.

    // ---------------------------------------------------------------- funding

    /// @notice Deposit your stake. Exactly once, exactly the right amount,
    ///         only during the funding window.
    function deposit() external payable onlyPlayer inState(State.Funding) {
        require(block.timestamp <= fundingDeadline, "funding closed");
        require(deposited[msg.sender] == 0, "already deposited");

        // Tie the amount to the ROLE, not "either amount". The original let
        // the bettor put up takerStake and vice versa.
        uint256 required = msg.sender == bettor ? bettorStake : takerStake;
        require(msg.value == required, "wrong amount");

        deposited[msg.sender] = msg.value;
        emit Deposited(msg.sender, msg.value);

        if (deposited[bettor] != 0 && deposited[taker] != 0) {
            state = State.Active;
        }
    }

    /// @notice Unwind a bet that never became fully funded.
    ///         - A player who has deposited may cancel at any time while the
    ///           other side has not (no waiting on a ghost).
    ///         - After the funding deadline, anyone may cancel.
    ///         Deposits are credited to `pending`, not sent, so a reverting
    ///         receiver cannot block the cancellation.
    function cancel() external inState(State.Funding) {
        bool deadlinePassed = block.timestamp > fundingDeadline;
        bool fundedPlayer =
            (msg.sender == bettor || msg.sender == taker) && deposited[msg.sender] != 0;
        require(deadlinePassed || fundedPlayer, "not allowed");

        state = State.Cancelled;
        _creditRefunds();
        emit Cancelled(msg.sender);
    }

    // ------------------------------------------------------------- settlement

    /// @notice Concede the bet to the other player. This is the ONLY voluntary
    ///         settlement path. You can never pay yourself; a single concession
    ///         is final. This removes the original's "either party pays
    ///         themselves in two calls" exploit and its "winner called first"
    ///         footgun in one stroke.
    ///         Allowed any time while Active, including before eventDate, in
    ///         case the outcome is known early.
    function concede() external onlyPlayer inState(State.Active) {
        address winner = msg.sender == bettor ? taker : bettor;
        uint256 pot = _resolve(winner);
        emit Conceded(msg.sender, winner, pot);
    }

    /// @notice Arbiter rules a winner. Only after the event date, only while
    ///         Active. The arbiter cannot act during Funding (nothing to rule
    ///         on) and cannot reverse a concession (state is Resolved).
    function rule(address winner) external inState(State.Active) {
        require(arbiter != address(0), "no arbiter");
        require(msg.sender == arbiter, "not arbiter");
        require(block.timestamp >= eventDate, "event not yet occurred");
        require(winner == bettor || winner == taker, "winner not a player");

        uint256 pot = _resolve(winner);
        emit Ruled(msg.sender, winner, pot);
    }

    /// @notice If the bet is still unresolved after the resolution deadline,
    ///         anyone can expire it and both stakes are refunded.
    ///         This is deliberately the LAST resort: the grace window between
    ///         eventDate and resolutionDeadline exists so the winner has time
    ///         to obtain a concession or a ruling before the loser can force a
    ///         refund. Without an arbiter, a loser who refuses to concede will
    ///         reach this state; that is the price of trustless two-party
    ///         betting with no oracle, and the contract does not pretend
    ///         otherwise.
    function expire() external inState(State.Active) {
        require(block.timestamp > resolutionDeadline, "not yet expirable");
        state = State.Expired;
        _creditRefunds();
        emit Expired(msg.sender);
    }

    // ------------------------------------------------------------- withdrawal

    /// @notice Pull whatever is credited to you (winnings or refund).
    ///         Effects before interaction: balance is zeroed BEFORE the call,
    ///         and the function is guarded, so reentrancy cannot double-pull.
    function withdraw() external nonReentrant {
        uint256 amount = pending[msg.sender];
        require(amount > 0, "nothing to withdraw");

        pending[msg.sender] = 0;
        emit Withdrawn(msg.sender, amount);

        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
        // If the call fails the whole tx reverts, pending[] is restored, and
        // the caller can try again later. Nobody else is affected.
    }

    // -------------------------------------------------------------- internals

    /// @dev Move to Resolved and credit the full pot to `winner`.
    ///      Uses `deposited` (what actually came in via deposit()) rather than
    ///      address(this).balance, so any ETH forced in via selfdestruct is
    ///      simply ignored rather than becoming a reentrancy target.
    function _resolve(address winner) internal returns (uint256 pot) {
        pot = deposited[bettor] + deposited[taker];
        deposited[bettor] = 0;
        deposited[taker] = 0;
        state = State.Resolved;
        pending[winner] += pot;
    }

    /// @dev Credit each player exactly what they deposited.
    function _creditRefunds() internal {
        uint256 b = deposited[bettor];
        uint256 t = deposited[taker];
        deposited[bettor] = 0;
        deposited[taker] = 0;
        if (b > 0) pending[bettor] += b;
        if (t > 0) pending[taker] += t;
    }

    // ------------------------------------------------------------------ views

    /// @notice Convenience read for front-ends.
    function summary()
        external
        view
        returns (
            State _state,
            uint256 _bettorDeposited,
            uint256 _takerDeposited,
            uint256 _pendingBettor,
            uint256 _pendingTaker
        )
    {
        return (state, deposited[bettor], deposited[taker], pending[bettor], pending[taker]);
    }
}

/*//////////////////////////////////////////////////////////////////////////////
                                     FACTORY
////////////////////////////////////////////////////////////////////////////////

Changes from the original:
  * Not payable, no receive(): the original factory silently swallowed any ETH
    sent with createBet() and had no way to get it out.
  * Only one of the two named players may create the bet. This does not stop a
    counterparty from deploying a lookalike with different terms (the other
    party must still read the instance's immutables before depositing), but it
    stops arbitrary third parties from spamming bets in your name.
  * Per-player index so each party can find bets they are named in.

//////////////////////////////////////////////////////////////////////////////*/

contract BetFactory {
    event BetCreated(
        address indexed bet,
        address indexed bettor,
        address indexed taker,
        address arbiter,
        uint256 bettorStake,
        uint256 takerStake,
        bytes32 betDetailsHash
    );

    Bet[] public allBets;
    mapping(address => Bet[]) public betsByPlayer;

    function createBet(
        address _bettor,
        address _taker,
        address _arbiter,
        uint256 _bettorStake,
        uint256 _takerStake,
        bytes32 _betDetailsHash,
        uint256 _fundingWindow,
        uint256 _timeToEvent,
        uint256 _graceWindow
    ) external returns (Bet bet) {
        require(msg.sender == _bettor || msg.sender == _taker, "creator must be a player");

        bet = new Bet(
            _bettor,
            _taker,
            _arbiter,
            _bettorStake,
            _takerStake,
            _betDetailsHash,
            _fundingWindow,
            _timeToEvent,
            _graceWindow
        );

        allBets.push(bet);
        betsByPlayer[_bettor].push(bet);
        betsByPlayer[_taker].push(bet);

        emit BetCreated(
            address(bet),
            _bettor,
            _taker,
            _arbiter,
            _bettorStake,
            _takerStake,
            _betDetailsHash
        );
    }

    function betCount() external view returns (uint256) {
        return allBets.length;
    }

    function betCountFor(address player) external view returns (uint256) {
        return betsByPlayer[player].length;
    }
}
