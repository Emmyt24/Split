# Split

A modern web application for splitting payments across multiple wallets on the Base blockchain. Send once, split instantly.

## 🚀 Features

- **One Payment, Multiple Wallets**: Send a single transaction that automatically distributes funds to multiple recipients
- **Base Network Integration**: Built on Base for fast, low-cost transactions
- **Modern UI**: Clean, responsive interface with dark/light theme support
- **Real-time Animations**: Dynamic visual effects showcasing token flows
- **Mobile Responsive**: Optimized for all device sizes

## 🛠 Tech Stack

- **Frontend**: Next.js 15, React 19, TypeScript
- **Styling**: Tailwind CSS, Radix UI components
- **Blockchain**: Solidity smart contracts on Base network

## 📦 Installation

1. Clone the repository:

```bash
git clone <repository-url>
cd split
```

2. Install dependencies:

```bash
pnpm install
```

3. Start the development server:

```bash
pnpm dev
```

4. Open [http://localhost:3000](http://localhost:3000) in your browser.

## 🏗 Smart Contract

The project includes a Solidity smart contract for handling payment splitting logic. The contract is located in `contract/splitContract.sol` and is currently under development.

### Contract Features (Planned)

- Multi-recipient payment distribution
- Gas-optimized splitting mechanism
- Emergency withdrawal functions
- Owner controls for security

## 🎨 UI Components

The application uses a comprehensive set of reusable UI components:

- `DecryptedText`: Animated text decryption effect
- `LineShadowText`: Text with shadow effects
- `ShimmerButton`: Button with shimmer animation
- `ThemeProvider`: Dark/light theme management

## 📱 Usage

1. Connect your wallet (MetaMask, Coinbase Wallet, etc.)
2. Enter recipient addresses and amounts
3. Confirm the transaction
4. Funds are automatically split and distributed

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- [Base Network](https://base.org)
- [Next.js Documentation](https://nextjs.org/docs)
- [Tailwind CSS](https://tailwindcss.com)
- [Radix UI](https://www.radix-ui.com)

---

Built with ❤️ for the Base ecosystem
