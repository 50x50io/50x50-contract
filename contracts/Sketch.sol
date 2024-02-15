// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

enum YieldMode {
    AUTOMATIC,
    VOID,
    CLAIMABLE
}

enum GasMode {
    VOID,
    CLAIMABLE
}

interface IBlast {
    // configure
    function configureContract(
        address contractAddress,
        YieldMode _yield,
        GasMode gasMode,
        address governor
    ) external;

    function configure(
        YieldMode _yield,
        GasMode gasMode,
        address governor
    ) external;

    // base configuration options
    function configureClaimableYield() external;

    function configureClaimableYieldOnBehalf(address contractAddress) external;

    function configureAutomaticYield() external;

    function configureAutomaticYieldOnBehalf(address contractAddress) external;

    function configureVoidYield() external;

    function configureVoidYieldOnBehalf(address contractAddress) external;

    function configureClaimableGas() external;

    function configureClaimableGasOnBehalf(address contractAddress) external;

    function configureVoidGas() external;

    function configureVoidGasOnBehalf(address contractAddress) external;

    function configureGovernor(address _governor) external;

    function configureGovernorOnBehalf(
        address _newGovernor,
        address contractAddress
    ) external;

    // claim yield
    function claimYield(
        address contractAddress,
        address recipientOfYield,
        uint256 amount
    ) external returns (uint256);

    function claimAllYield(
        address contractAddress,
        address recipientOfYield
    ) external returns (uint256);

    // claim gas
    function claimAllGas(
        address contractAddress,
        address recipientOfGas
    ) external returns (uint256);

    function claimGasAtMinClaimRate(
        address contractAddress,
        address recipientOfGas,
        uint256 minClaimRateBips
    ) external returns (uint256);

    function claimMaxGas(
        address contractAddress,
        address recipientOfGas
    ) external returns (uint256);

    function claimGas(
        address contractAddress,
        address recipientOfGas,
        uint256 gasToClaim,
        uint256 gasSecondsToConsume
    ) external returns (uint256);

    // read functions
    function readClaimableYield(
        address contractAddress
    ) external view returns (uint256);

    function readYieldConfiguration(
        address contractAddress
    ) external view returns (uint8);

    function readGasParams(
        address contractAddress
    )
        external
        view
        returns (
            uint256 etherSeconds,
            uint256 etherBalance,
            uint256 lastUpdated,
            GasMode
        );
}

contract Fiftyxfifty is ERC1155("https://50x50.io/api/art/{id}"), Ownable {
    IBlast public blast = IBlast(0x4300000000000000000000000000000000000002);
    uint256 public immutable totalSupply;
    uint256 public immutable epochDuration = 2 hours;

    constructor(uint256 _totalSupply) Ownable(msg.sender) {
        IBlast(0x4300000000000000000000000000000000000002)
            .configureClaimableYield();
        totalSupply = _totalSupply;
    }

    // Enums
    enum PaintingState {
        DRAWING,
        MINTING
    }

    // Storage
    struct Drawing {
        uint256 id;
        uint256 endTime;
        PaintingState state;
        bool claimed;
        uint256 totalContributions;
        uint256 totalParticipants;
        mapping(address => uint256) contributions;
        address[] contributors;
        mapping(address => uint256) royalties;
        address winner;
        bytes metadataUri;
        bytes editionMetadataUri;
        uint256 yield;
        uint256 editionMints;
    }

    uint256 public constant MAX_PIXELS = 50;
    uint256 public constant MAX_EDITION_MINTS = 50;
    address[] public totalContributors;
    mapping(address => uint256) public totalContributions;
    mapping(uint256 => Drawing) public drawings;
    mapping(uint256 => uint256) public yieldRights;
    mapping(uint256 => uint256) public yieldBalances;
    uint256 public mintedSupply;
    uint256 public totalYield;
    uint256 public startedAt;
    uint256 public mintFee = 0.01 ether;
    uint256 public editionMintFee = 0.01 ether;
    uint256 public lastYieldSnapshot;
    uint256 public totalClaimedYield;

    uint256 public ownerYieldRightsPerMillion = 200_000;
    uint256 public ogYieldAllocation = 800_000;
    uint256 public firstOgTokenYieldAllocation = 100_000;

    // Events
    event PixelsDrawn(
        address indexed painter,
        bytes pixels,
        uint256 indexed drawingId
    );
    event DrawingFinished(
        uint256 indexed drawingId,
        address indexed winner,
        uint256 indexed nextYield
    );
    event OgMinted(address indexed winner, uint256 indexed drawingId);
    event EditionMinted(address indexed minter, uint256 indexed drawingId);

    // Functions
    function drawPixels(bytes calldata pixels, uint256 drawingId) public {
        require(pixels.length % 3 == 0, "Invalid pixel data");
        require(pixels.length > 0, "No pixel data");
        require(pixels.length / 3 <= MAX_PIXELS, "Too many pixels");
        require(drawings[drawingId].id == drawingId, "Invalid drawing id");
        require(
            drawings[drawingId].state == PaintingState.DRAWING,
            "Drawing is not active"
        );

        uint256 drawn = pixels.length / 3;
        totalContributions[msg.sender] += drawn;
        drawings[drawingId].contributions[msg.sender] += drawn;
        drawings[drawingId].totalContributions += drawn;
        if (drawings[drawingId].contributions[msg.sender] == drawn) {
            drawings[drawingId].totalParticipants += 1;
            drawings[drawingId].contributors.push(msg.sender);
        }
        if (totalContributions[msg.sender] == drawn) {
            totalContributors.push(msg.sender);
        }

        emit PixelsDrawn(msg.sender, pixels, drawingId);
    }

    function mint(uint256 drawingId) public payable {
        require(msg.value >= mintFee, "Not enough Ether provided.");
        require(startedAt > 0, "Not started");
        require(msg.sender == drawings[drawingId].winner, "Not the winner");
        require(
            drawings[drawingId].state == PaintingState.MINTING,
            "Drawing is not mintable"
        );
        require(!drawings[drawingId].claimed, "Already claimed");
        mintedSupply = mintedSupply + 1;
        drawings[drawingId].claimed = true;

        _mint(msg.sender, mintedSupply, 1, drawings[drawingId].metadataUri);
    }

    function mintEdition(uint256 drawingId, uint256 amount) public payable {
        require(
            msg.value >= editionMintFee * amount,
            "Not enough Ether provided."
        );
        require(
            drawings[drawingId].state == PaintingState.MINTING,
            "Drawing is not mintable"
        );
        require(
            drawings[drawingId].editionMints <= MAX_EDITION_MINTS,
            "Already minted"
        );
        require(
            drawings[drawingId].editionMints + amount <= MAX_EDITION_MINTS,
            "Too many mints"
        );

        drawings[drawingId].editionMints += 1;

        for (uint256 i = 0; i < drawings[drawingId].contributors.length; i++) {
            address contributor = drawings[drawingId].contributors[i];
            uint256 contributions = drawings[drawingId].contributions[
                contributor
            ];
            uint256 royalties = (msg.value * contributions) /
                drawings[drawingId].totalContributions;
            drawings[drawingId].royalties[contributor] += royalties;
        }

        _mint(
            msg.sender,
            mintedSupply + drawings[drawingId].editionMints,
            1,
            drawings[drawingId].editionMetadataUri
        );
    }

    function accumulateYield() public {
        uint256 currentYield = blast.readClaimableYield(address(this));
        uint256 newYield = currentYield -
            (lastYieldSnapshot - totalClaimedYield);
        lastYieldSnapshot = currentYield;
        for (uint256 i = 1; i <= mintedSupply; i++) {
            yieldBalances[i] += (newYield * yieldRights[i]) / 1_000_000;
        }
    }

    function claimYield(uint256 drawingId) public {
        require(isOwnerOf(msg.sender, drawingId), "Not the owner");
        uint256 yield = yieldBalances[drawingId];
        yieldBalances[drawingId] = 0;
        totalClaimedYield += yield;
        blast.claimYield(address(this), _msgSender(), yield);
    }

    function claimRoyalties(uint256 drawingId) public {
        require(
            drawings[drawingId].royalties[msg.sender] > 0,
            "No royalties to claim"
        );
        uint256 royalties = drawings[drawingId].royalties[msg.sender];
        drawings[drawingId].royalties[msg.sender] = 0;
        payable(msg.sender).transfer(royalties);
    }

    function totalUnclaimedRoyalties(
        address user
    ) public view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 1; i <= mintedSupply; i++) {
            total += drawings[i].royalties[user];
        }
        return total;
    }

    function unclaimedRoyalties(
        uint256 drawingId,
        address user
    ) public view returns (uint256) {
        return drawings[drawingId].royalties[user];
    }

    function start() public onlyOwner {
        require(startedAt == 0, "Already started");
        lastYieldSnapshot = blast.readClaimableYield(address(this));
        startedAt = block.timestamp;

        uint256 nextDrawingId = 1;
        drawings[nextDrawingId].id = nextDrawingId;
        drawings[nextDrawingId].state = PaintingState.DRAWING;
        drawings[nextDrawingId].endTime = block.timestamp + epochDuration;
        drawings[nextDrawingId].yield = firstOgTokenYieldAllocation;
    }

    function setURI(string calldata newuri) public onlyOwner {
        _setURI(newuri);
    }

    function setMintFee(uint256 newPrice) public onlyOwner {
        mintFee = newPrice;
    }

    function isOwnerOf(
        address account,
        uint256 tokenId
    ) public view returns (bool) {
        return balanceOf(account, tokenId) > 0;
    }

    function prepareDrawing(
        uint256 drawingId,
        bytes calldata tokenURI,
        bytes calldata editionTokenURI
    ) public onlyOwner {
        require(drawings[drawingId].id == drawingId, "Invalid drawing id");
        require(
            drawings[drawingId].totalParticipants >= 1,
            "Not enough participants"
        );

        address winner;
        uint256 maxContributions = 0;
        for (uint256 i = 0; i < drawings[drawingId].contributors.length; i++) {
            address contributor = drawings[drawingId].contributors[i];
            uint256 contributions = drawings[drawingId].contributions[
                contributor
            ];
            if (contributions > maxContributions) {
                maxContributions = contributions;
                winner = contributor;
            }
        }

        drawings[drawingId].winner = winner;
        drawings[drawingId].state = PaintingState.MINTING;
        drawings[drawingId].metadataUri = tokenURI;
        drawings[drawingId].editionMetadataUri = editionTokenURI;

        uint256 nextDrawingId = drawingId + 1;
        drawings[nextDrawingId].id = nextDrawingId;
        drawings[nextDrawingId].state = PaintingState.DRAWING;
        drawings[nextDrawingId].endTime = block.timestamp + epochDuration;
        drawings[nextDrawingId].yield = calculateTokenAllocation(
            nextDrawingId,
            ogYieldAllocation - firstOgTokenYieldAllocation
        );

        emit DrawingFinished(drawingId, winner, drawings[nextDrawingId].yield);
    }

    function today() public view returns (uint256) {
        return ((block.timestamp - startedAt) / epochDuration) + 1;
    }

    function pow(
        uint256 base,
        uint256 exponent
    ) internal pure returns (uint256) {
        uint256 result = 1_000_000;
        for (uint256 i = 0; i < exponent; i++) {
            result = (result * base) / 1_000_000;
        }
        return result;
    }

    function calculateTokenAllocation(
        uint256 tokenId,
        uint256 total_yield
    ) public pure returns (uint256) {
        uint256 tokens = 49;
        uint256 coefficient = 950_000;
        require(coefficient <= 1_000_000, "Coefficient must be <= 1_000_000");
        uint256 first_token_allocation = (total_yield *
            (1_000_000 - coefficient)) / (1_000_000 - pow(coefficient, tokens));
        uint256 allocation = (first_token_allocation *
            pow(coefficient, tokenId - 1)) / 1_000_000;
        return allocation;
    }
}
