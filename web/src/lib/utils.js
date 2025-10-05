export const parseDecimals = (amount, decimals) => {
    const floatValue = parseFloat(amount);
    const formattedValue = floatValue / Math.pow(10, decimals);

    return formattedValue;
}

export const formatDecimals = (amount, decimals) => {
    const [integerPart, decimalPart] = String(amount).split('.');
    const paddedDecimal = (decimalPart || '').padEnd(decimals, '0').slice(0, decimals);
    const integerString = integerPart + paddedDecimal;
    let startIndex = 0;

    for(var i = 0; i < integerString.length; i++){
        if(integerString[i] != 0){
            startIndex = i;

            break
        }
    }

    return startIndex == integerString.length-1 ? "0" : integerString.substring(startIndex);
}