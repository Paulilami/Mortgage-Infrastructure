import { BigNumber, ethers } from 'ethers';
import type { Provider } from '@ethersproject/providers';
import type { Signer } from '@ethersproject/abstract-signer';
import { ERC20_ABI, ERC721_ABI, MORTGAGE_SETTINGS_ABI, ERC20_ESCROW_ABI, ERC721_ESCROW_ABI } from './abi';

export type AssetType = 'ERC20' | 'ERC721';
export type LoanState = 'Inactive' | 'Active' | 'Extended' | 'Completed' | 'Defaulted';

export interface LoanCore {
  seller: string;
  buyer: string;
  amount: BigNumber;
  state: LoanState;
  token: string;
}

export interface LoanTerms {
  downPayment: BigNumber;
  loanAmount: BigNumber;
  duration: number;
  startTime: number;
  totalRepaid: BigNumber;
  interestRate: number;
  extensions: number;
}

export interface MortgageConfig {
  chainId: number;
  rpcUrl: string;
  settings: string;
  escrows: {
    ERC20: string;
    ERC721: string;
  };
}

export class MortgageSDK {
  private provider: Provider;
  private signer?: Signer;
  private settings: ethers.Contract;
  private escrows: Record<AssetType, ethers.Contract>;

  constructor(config: MortgageConfig, signerOrProvider: Signer | Provider) {
    if (Signer.isSigner(signerOrProvider)) {
      this.signer = signerOrProvider;
      this.provider = signerOrProvider.provider!;
    } else {
      this.provider = signerOrProvider;
    }

    this.settings = new ethers.Contract(config.settings, MORTGAGE_SETTINGS_ABI, this.provider);
    this.escrows = {
      ERC20: new ethers.Contract(config.escrows.ERC20, ERC20_ESCROW_ABI, this.provider),
      ERC721: new ethers.Contract(config.escrows.ERC721, ERC721_ESCROW_ABI, this.provider)
    };
  }

  async approveMarketplace(marketplace: string): Promise<ethers.ContractTransaction> {
    if (!this.signer) throw new Error('Signer required');
    return await this.settings.connect(this.signer).setMarketplace(marketplace, true);
  }

  async isApprovedMarketplace(marketplace: string): Promise<boolean> {
    return await this.settings.marketplaces(marketplace);
  }

  async getConstants(): Promise<{
    MIN_DOWNPAYMENT: number;
    MAX_DOWNPAYMENT: number;
    MIN_DURATION: number;
    MAX_DURATION: number;
    DEFAULT_FEE: number;
  }> {
    const [min, max, minDur, maxDur, fee] = await Promise.all([
      this.settings.MIN_DOWNPAYMENT(),
      this.settings.MAX_DOWNPAYMENT(),
      this.settings.MIN_DURATION(),
      this.settings.MAX_DURATION(),
      this.settings.DEFAULT_FEE()
    ]);
    return { MIN_DOWNPAYMENT: min, MAX_DOWNPAYMENT: max, MIN_DURATION: minDur, MAX_DURATION: maxDur, DEFAULT_FEE: fee };
  }

  private getEscrowContract(assetType: AssetType): ethers.Contract {
    return this.escrows[assetType];
  }

  getEscrowAddress(assetType: AssetType): string {
    return this.escrows[assetType].address;
  }

  async createLoan(params: {
    asset: { type: AssetType; address: string; tokenId?: string };
    amount: BigNumber | string;
    downPaymentPercent: number;
    duration: number;
  }): Promise<{ loanId: string; tx: ethers.ContractTransaction }> {
    if (!this.signer) throw new Error('Signer required');
    const escrow = this.getEscrowContract(params.asset.type).connect(this.signer);
    
    const tx = await escrow.createLoan(
      params.asset.address,
      params.asset.tokenId || 0,
      params.amount,
      params.downPaymentPercent,
      params.duration
    );
    
    const receipt = await tx.wait();
    const loanId = receipt.events?.find(e => e.event === 'LoanCreated')?.args?.loanId;
    return { loanId, tx };
  }

  async getLoanDetails(loanId: string, assetType: AssetType): Promise<{ core: LoanCore; terms: LoanTerms }> {
    const escrow = this.getEscrowContract(assetType);
    const [core, terms] = await Promise.all([
      escrow.loans(loanId),
      escrow.terms(loanId)
    ]);
    return { core, terms };
  }

  async startLoan(params: {
    loanId: string;
    assetType: AssetType;
    value: BigNumber | string;
  }): Promise<ethers.ContractTransaction> {
    if (!this.signer) throw new Error('Signer required');
    const escrow = this.getEscrowContract(params.assetType).connect(this.signer);
    return await escrow.startLoan(params.loanId, { value: params.value });
  }

  async makePayment(params: {
    loanId: string;
    assetType: AssetType;
    value: BigNumber | string;
  }): Promise<ethers.ContractTransaction> {
    if (!this.signer) throw new Error('Signer required');
    const escrow = this.getEscrowContract(params.assetType).connect(this.signer);
    return await escrow.makePayment(params.loanId, { value: params.value });
  }

  async extendLoan(loanId: string, assetType: AssetType): Promise<ethers.ContractTransaction> {
    if (!this.signer) throw new Error('Signer required');
    const escrow = this.getEscrowContract(assetType).connect(this.signer);
    return await escrow.extendLoan(loanId);
  }

  async defaultLoan(loanId: string, assetType: AssetType): Promise<ethers.ContractTransaction> {
    if (!this.signer) throw new Error('Signer required');
    const escrow = this.getEscrowContract(assetType).connect(this.signer);
    return await escrow.defaultLoan(loanId);
  }

  async getTotalDue(loanId: string, assetType: AssetType): Promise<BigNumber> {
    const escrow = this.getEscrowContract(assetType);
    return await escrow.getTotalDue(loanId);
  }

  async approveToken(tokenAddress: string, spender: string, amount: BigNumber | string): Promise<ethers.ContractTransaction> {
    if (!this.signer) throw new Error('Signer required');
    const token = new ethers.Contract(tokenAddress, ERC20_ABI, this.signer);
    return await token.approve(spender, amount);
  }

  async approveNFT(nftAddress: string, spender: string, tokenId: string): Promise<ethers.ContractTransaction> {
    if (!this.signer) throw new Error('Signer required');
    const nft = new ethers.Contract(nftAddress, ERC721_ABI, this.signer);
    return await nft.approve(spender, tokenId);
  }

  async calculateMonthlyPayment(params: {
    amount: BigNumber | string;
    downPaymentPercent: number;
    durationDays: number;
  }): Promise<BigNumber> {
    const amount = BigNumber.from(params.amount);
    const loanAmount = amount.mul(100 - params.downPaymentPercent).div(100);
    const interestRate = await this.settings.getInterestRate(params.durationDays);
    const months = params.durationDays / 30;
    const monthlyInterest = BigNumber.from(interestRate).div(12);
    return loanAmount.mul(monthlyInterest).div(BigNumber.from(1).sub(monthlyInterest.pow(months)));
  }
}

export class MarketplaceHelper {
  private sdk: MortgageSDK;

  constructor(sdk: MortgageSDK) {
    this.sdk = sdk;
  }

  async setupListing(params: {
    asset: { type: AssetType; address: string; tokenId?: string };
    price: BigNumber | string;
    downPaymentPercent: number;
    duration: number;
  }): Promise<{ loanId: string; monthlyPayment: BigNumber }> {
    const { loanId } = await this.sdk.createLoan(params);
    const monthlyPayment = await this.sdk.calculateMonthlyPayment({
      amount: params.price,
      downPaymentPercent: params.downPaymentPercent,
      durationDays: params.duration
    });
    return { loanId, monthlyPayment };
  }

  async processLoanStart(params: {
    asset: { type: AssetType; address: string; tokenId?: string };
    loanId: string;
    downPayment: BigNumber | string;
  }): Promise<ethers.ContractTransaction> {
    if (params.asset.type === 'ERC20') {
      await this.sdk.approveToken(params.asset.address, this.sdk.getEscrowAddress('ERC20'), params.downPayment);
    } else {
      await this.sdk.approveNFT(params.asset.address, this.sdk.getEscrowAddress('ERC721'), params.asset.tokenId!);
    }
    return await this.sdk.startLoan({
      loanId: params.loanId,
      assetType: params.asset.type,
      value: params.downPayment
    });
  }
}

export class MortgageEvents {
  private sdk: MortgageSDK;
  private callbacks: Map<string, Function[]>;

  constructor(sdk: MortgageSDK) {
    this.sdk = sdk;
    this.callbacks = new Map();
  }

  subscribe(event: string, callback: Function): void {
    if (!this.callbacks.has(event)) {
      this.callbacks.set(event, []);
    }
    this.callbacks.get(event)!.push(callback);
  }

  startListening(assetTypes: AssetType[]): void {
    assetTypes.forEach(type => {
      const escrow = this.sdk.getEscrowContract(type);
      escrow.on('LoanCreated', (...args) => this.handleEvent('LoanCreated', args));
      escrow.on('LoanStarted', (...args) => this.handleEvent('LoanStarted', args));
      escrow.on('PaymentMade', (...args) => this.handleEvent('PaymentMade', args));
      escrow.on('LoanCompleted', (...args) => this.handleEvent('LoanCompleted', args));
      escrow.on('LoanDefaulted', (...args) => this.handleEvent('LoanDefaulted', args));
    });
  }

  private handleEvent(eventName: string, args: any[]): void {
    const callbacks = this.callbacks.get(eventName) || [];
    callbacks.forEach(callback => callback(...args));
  }
}

export default MortgageSDK;