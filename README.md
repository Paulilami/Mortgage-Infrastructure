# Mortgages, decentralized. 

Enable buy-now-pay-later for your marketplace in minutes. Our protocol handles all the mortgage logistics while you focus on your core marketplace experience. 

### Update Jan.2025
I'm currently in the process of integrating a flag as bytes32 value to initialze the mortgages feature, making it much simpler to integrate. 

## Why use on-chain mortgages? 

- 🚀 Increase transaction volume by making expensive assets accessible
- 💰 Enable sellers to reach more buyers
- ⚡ Zero infrastructure changes required
- 🔒 Secure, audited, and battle-tested contracts
- 🛠 Developer-friendly SDK

## Quick Start
1. Install the SDK 

```bash 
npm install @trusset-mortgage-infrastructure/sdk
# or
yarn add @trusset-mortgage-infrastructure/sdk
```

2. Initialize in your app:

```typescript
import { MortgageSDK } from '@mortgage-protocol/sdk';

const mortgageSDK = new MortgageSDK({
  chainId: 1, // or your preferred network
  settings: SETTINGS_ADDRESS,
  escrows: {
    ERC721: NFT_ESCROW_ADDRESS,
    ERC20: TOKEN_ESCROW_ADDRESS
  }
}, provider);
```

### Integration Example
Add mortgage support to your existing listing flow:

```typescript
// 1. When seller creates a listing
async function createListingWithMortgage(nft, price, mortgageEnabled) {
  if (mortgageEnabled) {
    const { loanId } = await mortgageSDK.createLoan({
      asset: {
        type: 'ERC721',
        address: nft.address,
        tokenId: nft.tokenId
      },
      amount: price,
      downPaymentPercent: 20, // Example: 20% down payment
      duration: 365 * 2 // Example: 2 year term
    });
    
    return {
      ...yourNormalListing,
      mortgageLoanId: loanId
    };
  }
  return yourNormalListing;
}

// 2. When buyer purchases with mortgage
async function purchaseWithMortgage(listing, downPayment) {
  await mortgageSDK.startLoan({
    loanId: listing.mortgageLoanId,
    assetType: 'ERC721',
    value: downPayment
  });
}
```

### Key Features

**For Your Users**
- Flexible down payments (3% - 85%)
- Loan terms up to 15 years
- Simple monthly repayments
- 3-month extension option
- Clear default handling

**For Your Platform**
- Full ownership of user experience
- Customizable parameters
- Event monitoring
- Zero maintenance required
- Comprehensive analytics

## Implementation Guide

1. Get Approved
```typescript
// One-time setup for your marketplace
await mortgageSDK.approveMarketplace(YOUR_MARKETPLACE_ADDRESS);
```

2. Add to Listing Creation
```typescript
// Add mortgage toggle to your listing form
const helper = new MarketplaceHelper(mortgageSDK);

const listing = await helper.setupListing({
  asset: {
    type: 'ERC721',
    address: nftContract,
    tokenId: tokenId
  },
  price: price,
  downPaymentPercent: 20,
  duration: 365 * 2
});

// Get info for your UI
const monthlyPayment = listing.monthlyPayment;
```

3. Handle Purchase Flow
```typescript
// Add mortgage option to your buy flow
async function buyWithMortgage(listing, downPayment) {
  // 1. Approve NFT transfer
  await mortgageSDK.approveNFT(
    listing.nftAddress,
    mortgageSDK.getEscrowAddress('ERC721'),
    listing.tokenId
  );

  // 2. Start the loan
  await mortgageSDK.startLoan({
    loanId: listing.mortgageLoanId,
    assetType: 'ERC721',
    value: downPayment
  });
}
```

3. Monitor Loan States
```typescript
const events = new MortgageEvents(mortgageSDK);

events.subscribe('LoanStarted', async (loanId, buyer) => {
  // Update listing status
});

events.subscribe('LoanCompleted', async (loanId) => {
  // Handle successful completion
});

events.startListening(['ERC721']);
```

## License 
MIT
