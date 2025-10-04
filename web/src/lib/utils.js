export const parseDecimals = (amount, decimals) => {
    const floatValue = parseFloat(amount);
    const formattedValue = floatValue / Math.pow(10, decimals);

    return formattedValue;
}