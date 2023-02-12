// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/** 
 * @title Voting
 * @dev Implements voting process : The administrator add Voters, they can vote and add proposal  
 *      different sessions of vote can be implemented. 
 *
 */
contract Voting is Ownable {

    uint sessionId = 1; 
    uint proposalId = 1;
    uint winningProposalId;     //can be checked when votes tallied is done
    uint highestVoteCount;      //used for the vote count

    mapping(address => bool) votelistAddress;

    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }

    struct Proposal {
        string description;
        uint voteCount;
    }

    uint firstProposalId;   // first proposal Id of the session 
    uint lastProposalId;    // last proposal Id of the session

    mapping(uint => mapping(uint => Proposal)) proposals;   // first uint is sessionId, second is proposalId
    mapping(uint => mapping(address => Voter)) voters;      // first uint is sessionId
    mapping(uint => uint) linkSessionAndProposal;           // first uint is proposadId, second is sessionId
    mapping(uint => uint) voteTimeStamp;                    // first uint is proposadId, second is timestamp

    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }
    WorkflowStatus workflowStatusState;
    WorkflowStatus previousStatus;

    event VoterRegistered(address voterAddress); 
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);

    uint[] voteCount;

    /** 
     * @dev allow the adminsitrator to go to the next workflowstatus, he is oblige to follow the process
     * if new session, we increment it
     * and a event is emited
     */
    function nextWorkflowStatus() public onlyOwner {
        previousStatus = workflowStatusState;
        if (workflowStatusState==WorkflowStatus.RegisteringVoters) {
            workflowStatusState = WorkflowStatus.ProposalsRegistrationStarted;
            firstProposalId = proposalId;
            highestVoteCount = 0;     
        } else if (workflowStatusState==WorkflowStatus.ProposalsRegistrationStarted) {
            workflowStatusState = WorkflowStatus.ProposalsRegistrationEnded;
            lastProposalId = proposalId;
        } else if (workflowStatusState==WorkflowStatus.ProposalsRegistrationEnded) {
            workflowStatusState = WorkflowStatus.VotingSessionStarted;
        } else if (workflowStatusState==WorkflowStatus.VotingSessionStarted) {
            workflowStatusState = WorkflowStatus.VotingSessionEnded;
        } else if (workflowStatusState==WorkflowStatus.VotingSessionEnded) {
            workflowStatusState = WorkflowStatus.VotesTallied;
            whoWin();
        } else if (workflowStatusState==WorkflowStatus.VotesTallied) {
            workflowStatusState = WorkflowStatus.RegisteringVoters;
            sessionId++;
        } else {
            revert("Something bad happened with the changing of status");
        }
        emit WorkflowStatusChange(previousStatus, workflowStatusState);
    }

    /*
     * @dev get the Id of the actual winner
     * @param returns : winning id
     */ 
    function getWinner () public view returns (string memory) {
        require (workflowStatusState==WorkflowStatus.VotesTallied,"you have to wait for the counting vote");
        if (winningProposalId == 0) {
            return "Nobody was interested by this vote";
        } else {
            return string.concat("The winning proposal number is: ",Strings.toString(winningProposalId), ", and the description is : ",proposals[sessionId][winningProposalId].description);
        }
    }

     /*
     * @dev The admin prepare the Voterlist
     * @param _address : address of the voter
     */ 
    function votelist (address _address) public onlyOwner {
        require (workflowStatusState==WorkflowStatus.RegisteringVoters,"You can only add voters during the registering voters period");
        require (!votelistAddress[_address],"This address is already in the vote list");
        votelistAddress[_address] = true;
        emit VoterRegistered(_address); 
    }

     /*
     * @dev The voter add a proposal durinf the the Proposal Registration period
     * mapping with the Session and the proposal 
     * @param _description : desciption of the proposal
     */   
    function addProposal (string memory _description) public {
        require(workflowStatusState==WorkflowStatus.ProposalsRegistrationStarted, "The proposal Resgistrate period didn't started");
        require(votelistAddress[msg.sender],"Your address is not in the vote list");

        //new proposal
        Proposal memory proposal = Proposal(_description,0);
        proposals[sessionId][proposalId] = proposal;

        //mapping with the proposalId and the dessionId
        linkSessionAndProposal[proposalId] = sessionId;
        emit ProposalRegistered(proposalId);
        proposalId++;
    }

    
     /*
     * @dev Everyone can have the description of a proposal (actual ond old session)
     * to have the proposal, we have to search the sessionId with linkSessionAndProposal[_proposalId]
     * if Proposal Id exist in mapping linkSessionAndProposal, it exist in mapping proposals
     * @param _proposalId : the proposal id
     */   
    function getProposal (uint _proposalId) public view returns (string memory) {
        require(linkSessionAndProposal[_proposalId] != 0, "This proposal Id doesn't exist");
        return proposals[linkSessionAndProposal[_proposalId]][_proposalId].description;
    }

     /*
     * @dev The function vote... first test, if ok, add the voter and the count to the proposal. voteCount is used for the vote 
     * @param _proposalId : the proposal id
     */   
    function vote (uint _proposalId) public {
        require(workflowStatusState==WorkflowStatus.VotingSessionStarted, "The proposal Resgistrate period didn't started");
        require(votelistAddress[msg.sender],"Your address is not in the vote list");

        //Voter
        require(sessionId == linkSessionAndProposal[_proposalId], "This proposal Id doesn't exist or is an Id of a previous session");
        require(!voters[sessionId][msg.sender].hasVoted, "You already voted");

        Voter memory voter = Voter(true,true,_proposalId);
        voters[sessionId][msg.sender] = voter;

        proposals[sessionId][_proposalId].voteCount++;

        //to have the highest vote count
        if (proposals[sessionId][_proposalId].voteCount > highestVoteCount) {
            highestVoteCount = proposals[sessionId][_proposalId].voteCount;
        }
        //if equality we check the timestamp
        voteTimeStamp[_proposalId] = block.timestamp;

        emit Voted (msg.sender, _proposalId);
    }

     /*
     * @dev To have the winning proposal of the actual session. the function is processed automatically by changing the WorkflowStatus
     * lastProposalId is not attribuated so it's '<' in the For
     * Set the state vraible : winningProposalId
     */  
    function whoWin() public onlyOwner {
        require (workflowStatusState==WorkflowStatus.VotesTallied,"We are not counting the vote now");

        for (uint i = firstProposalId; i < lastProposalId; i++) {
            if (proposals[sessionId][i].voteCount == highestVoteCount) {
                voteCount.push(i);
            }
        }

        if (voteCount.length == 1) {
            winningProposalId = voteCount[0];
        } else {
            winningProposalId = whichProposalWinFromEquality();
        }
        delete(voteCount);
    }

     /*
     * @dev To have the winning proposal if equality. the function is processed automatically by changing the WorkflowStatus
     * The proposal which has the smallest timestamp win
     * @param return : winning proposal
     */  
    function whichProposalWinFromEquality() public view onlyOwner returns(uint) {
        require (workflowStatusState==WorkflowStatus.VotesTallied,"We are not counting the vote now");
        uint timeStamp;
        uint winningProposalEquality;
        for (uint i = 0; i < voteCount.length; i++) {
            if (i == 0) {
                timeStamp = voteTimeStamp[voteCount[i]];
                winningProposalEquality = voteCount[i];
            } else {
                if (timeStamp > voteTimeStamp[voteCount[i]]) {
                    timeStamp = voteTimeStamp[voteCount[i]];
                    winningProposalEquality = voteCount[i];
                }
            }
        }
        return winningProposalEquality;
    }

     /*
     * @dev everyone know wich proposal was voted by who
     * @param return : string, concatenation of id and description
     * "didn't vote yet" mean that we are at the beginnig of a session so the address couldn't vote 
     */  
    function whoVotedWhat (address _address) public view returns (string memory) {
        require (votelistAddress[_address],"This address is not in registered");
        string memory concatString;

        for (uint i=1 ; i<=sessionId; i++) {
            if (voters[i][_address].hasVoted) {
                concatString = string.concat(concatString," Session ", Strings.toString(i) ," Voted for proposalId : ",Strings.toString(voters[i][_address].votedProposalId), " - ",proposals[i][voters[i][_address].votedProposalId].description,";");
            } else {
                if (i==sessionId && (workflowStatusState != WorkflowStatus.VotesTallied)) {
                    concatString = string.concat(concatString," Session ", Strings.toString(i) ," didn't vote yet");
                } else {
                    concatString = string.concat(concatString," Session ", Strings.toString(i) ," didn't vote");
                }
            }
        }
        return concatString;
    }


}