import aptos from './chain'


export const getAddressTokenBalance = async(accountAddress, tokenAddress) => {
  try {
    const [balances, metadata] = await Promise.all([
      aptos.getCurrentFungibleAssetBalances({ 
        accountAddress,
        options: {
          where: {
            asset_type: { _eq: tokenAddress },
            owner_address: { _eq: accountAddress }
          }
        }
      }),
      aptos.getFungibleAssetMetadataByAssetType({ assetType: tokenAddress })
    ]);

    if (balances.length === 0) {
      return null;
    }

    const balance = balances[0];
    const decimals = metadata.decimals;
    const rawAmount = balance.amount;
    const floatAmount = parseFloat(rawAmount) / Math.pow(10, decimals);

    return floatAmount;
  } catch (error) {
    console.error("Error fetching token balance:", error);
    throw error;
  }
}