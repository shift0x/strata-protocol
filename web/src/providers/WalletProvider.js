import { AptosWalletAdapterProvider } from "@aptos-labs/wallet-adapter-react";
import { Network } from "@aptos-labs/ts-sdk";

export const WalletProvider = ({ children }) => {

  return (
    <AptosWalletAdapterProvider 
        autoConnect={true} 
        dappConfig={{ network: Network.TESTNET }}
        onError={(error) => { console.log("error", error);}}
    >
      {children}
    </AptosWalletAdapterProvider>
  );
};