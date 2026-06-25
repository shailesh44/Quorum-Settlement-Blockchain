const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("VittaGemsSettlement", function () {
  let settlement;
  let owner, treasuryAdmin, complianceOp, settlementAgent, auditor, partner1, partner2, unauthorized;

  const RESERVE_LIMIT = ethers.parseEther("10000000");
  const PER_TX_LIMIT  = ethers.parseEther("1000000");
  const DAILY_LIMIT   = ethers.parseEther("5000000");
  const MULTISIG_THR  = ethers.parseEther("500000");

  beforeEach(async function () {
    [owner, treasuryAdmin, complianceOp, settlementAgent, auditor, partner1, partner2, unauthorized] =
      await ethers.getSigners();

    const Settlement = await ethers.getContractFactory("VittaGemsSettlement");
    settlement = await Settlement.deploy(RESERVE_LIMIT, PER_TX_LIMIT, DAILY_LIMIT, MULTISIG_THR);
    await settlement.waitForDeployment();

    // Setup roles
    const TREASURY_ADMIN     = await settlement.TREASURY_ADMIN();
    const COMPLIANCE_OPERATOR = await settlement.COMPLIANCE_OPERATOR();
    const SETTLEMENT_AGENT    = await settlement.SETTLEMENT_AGENT();
    const AUDITOR_ROLE        = await settlement.AUDITOR();

    await settlement.assignRole(TREASURY_ADMIN, treasuryAdmin.address);
    await settlement.assignRole(COMPLIANCE_OPERATOR, complianceOp.address);
    await settlement.assignRole(SETTLEMENT_AGENT, settlementAgent.address);
    await settlement.assignRole(AUDITOR_ROLE, auditor.address);

    // Register partners
    await settlement.connect(treasuryAdmin).registerPartner(partner1.address, "Partner One");
    await settlement.connect(treasuryAdmin).registerPartner(partner2.address, "Partner Two");
  });

  describe("Role-Based Access Control", function () {
    it("should have correct roles assigned", async function () {
      const TREASURY_ADMIN = await settlement.TREASURY_ADMIN();
      expect(await settlement.hasRole(TREASURY_ADMIN, treasuryAdmin.address)).to.be.true;
    });

    it("should reject unauthorized mint attempts", async function () {
      await expect(
        settlement.connect(unauthorized).mintWithTreasuryApproval(
          ethers.parseEther("1000"), partner1.address, "REF-001", "US-MX"
        )
      ).to.be.reverted;
    });
  });

  describe("Minting", function () {
    it("should mint settlement value for approved partner", async function () {
      const amount = ethers.parseEther("5000");

      await expect(
        settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
          amount, partner1.address, "REF-001", "US-MX"
        )
      ).to.emit(settlement, "MintCompleted")
        .withArgs("REF-001", partner1.address, amount, await getBlockTimestamp());

      expect(await settlement.partnerBalances(partner1.address)).to.equal(amount);
      expect(await settlement.totalMinted()).to.equal(amount);
    });

    it("should reject mint exceeding per-transaction limit", async function () {
      await expect(
        settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
          ethers.parseEther("2000000"), partner1.address, "REF-002", "US-MX"
        )
      ).to.be.revertedWith("Exceeds per-transaction limit");
    });

    it("should reject mint exceeding reserve limit", async function () {
      // Set a very low reserve limit
      await settlement.connect(treasuryAdmin).setReserveLimit(ethers.parseEther("100"));

      await expect(
        settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
          ethers.parseEther("200"), partner1.address, "REF-003", "US-MX"
        )
      ).to.be.revertedWith("Insufficient reserve coverage");
    });

    it("should reject duplicate reference ID", async function () {
      await settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
        ethers.parseEther("1000"), partner1.address, "REF-DUP", "US-MX"
      );

      await expect(
        settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
          ethers.parseEther("1000"), partner1.address, "REF-DUP", "US-MX"
        )
      ).to.be.revertedWith("Reference ID already exists");
    });

    it("should reject mint for frozen partner", async function () {
      await settlement.connect(complianceOp).freeze(partner1.address, "Sanctions hit");

      await expect(
        settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
          ethers.parseEther("1000"), partner1.address, "REF-FROZEN", "US-MX"
        )
      ).to.be.revertedWith("Account is frozen");
    });
  });

  describe("Transfer", function () {
    beforeEach(async function () {
      await settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
        ethers.parseEther("5000"), partner1.address, "REF-T01", "US-MX"
      );
    });

    it("should transfer between approved partners", async function () {
      await expect(
        settlement.connect(settlementAgent).transfer(
          "REF-T01", partner2.address, ethers.parseEther("5000")
        )
      ).to.emit(settlement, "TransferSettled");

      expect(await settlement.partnerBalances(partner2.address)).to.equal(ethers.parseEther("5000"));
    });

    it("should reject transfer to unapproved address", async function () {
      await expect(
        settlement.connect(settlementAgent).transfer(
          "REF-T01", unauthorized.address, ethers.parseEther("5000")
        )
      ).to.be.revertedWith("Not an approved partner");
    });
  });

  describe("Hold & Freeze", function () {
    beforeEach(async function () {
      await settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
        ethers.parseEther("5000"), partner1.address, "REF-H01", "US-MX"
      );
    });

    it("should place and release a hold", async function () {
      await expect(
        settlement.connect(complianceOp).hold("REF-H01", "AML review")
      ).to.emit(settlement, "HoldPlaced");

      const s = await settlement.getSettlement("REF-H01");
      expect(s.status).to.equal(6); // ON_HOLD

      await expect(
        settlement.connect(complianceOp).release("REF-H01")
      ).to.emit(settlement, "HoldReleased");
    });

    it("should freeze and unfreeze an account", async function () {
      await settlement.connect(complianceOp).freeze(partner1.address, "Sanctions screening");
      expect(await settlement.frozenAccounts(partner1.address)).to.be.true;

      await settlement.connect(complianceOp).unfreeze(partner1.address);
      expect(await settlement.frozenAccounts(partner1.address)).to.be.false;
    });
  });

  describe("Burn & Reconcile", function () {
    beforeEach(async function () {
      await settlement.connect(treasuryAdmin).mintWithTreasuryApproval(
        ethers.parseEther("5000"), partner1.address, "REF-B01", "US-MX"
      );
      await settlement.connect(settlementAgent).transfer(
        "REF-B01", partner2.address, ethers.parseEther("5000")
      );
    });

    it("should reconcile and burn", async function () {
      await settlement.connect(settlementAgent).reconcile("REF-B01");
      const s1 = await settlement.getSettlement("REF-B01");
      expect(s1.status).to.equal(4); // PAYOUT_CONFIRMED

      await settlement.connect(settlementAgent).burn("REF-B01");
      const s2 = await settlement.getSettlement("REF-B01");
      expect(s2.status).to.equal(5); // CLOSED
    });
  });

  // Helper
  async function getBlockTimestamp() {
    const block = await ethers.provider.getBlock("latest");
    return block.timestamp;
  }
});
