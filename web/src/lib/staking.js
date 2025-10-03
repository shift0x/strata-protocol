import { addresses } from "./addresses";
import aptos from "./chain";

export const stake = async(amount) => {
  const amountInBig = (amount * Math.pow(10, 6)).toString();

  const transaction = {
    data : {
        function: `${addresses.code}::staking_vault::stake`,
        functionArguments: [addresses.staking_vault, amountInBig]
    }
  }

  return transaction
}

export const unstake = async(amount) => {
    const amountOutBig = (amount * Math.pow(10, 6)).toString();

    const transaction = {
        data : {
            function: `${addresses.code}::staking_vault::unstake`,
            functionArguments: [addresses.staking_vault, amountOutBig]
        }
    }

    return transaction
}

export const getStakingBalance = async (userAddress) => {
    const stakingBalanceRequest = {
        function: `${addresses.code}::staking_vault::get_staking_balance`,
        typeArguments: [],           
        functionArguments: [addresses.staking_vault, userAddress],
    }

    const stakingBalanceAmountBig = (await aptos.view({ payload: stakingBalanceRequest }))[0];

    const unstakeAmountRequest = {
        function: `${addresses.code}::staking_vault::get_unstake_amount`,
        typeArguments: [],           
        functionArguments: [addresses.staking_vault, userAddress, stakingBalanceAmountBig],
    }

    const unstakingAmountBig = (await aptos.view({ payload: unstakeAmountRequest }))[0];
    
    const initialStakingAmount = parseDecimals(stakingBalanceAmountBig, 6);
    const currentStakingAmount = parseDecimals(unstakingAmountBig, 6);
    
    return {
        initialStakingAmount,
        currentStakingAmount
    }
}

const parseDecimals = (amount, decimals) => {
    const floatValue = parseFloat(amount);
    const formattedValue = floatValue / Math.pow(10, decimals);

    return formattedValue;
}