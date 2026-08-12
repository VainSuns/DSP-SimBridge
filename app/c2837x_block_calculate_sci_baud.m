function result = c2837x_block_calculate_sci_baud(lspclkHz, requestedBaud)
%C2837X_BLOCK_CALCULATE_SCI_BAUD Calculate the closest SCI baud setting.
%
%   result = c2837x_block_calculate_sci_baud(lspclkHz, requestedBaud)
%
%   The DSP-SimBridge V1 candidate range is BRR 1 through 65535. The
%   returned signed error is Actual Baud minus Requested Baud, in baud.
%   BRR selection minimizes the absolute error in baud; an exact tie is
%   resolved in favor of the smaller BRR.

validate_positive_scalar(lspclkHz, ...
    'C2837xBlock:SciBaud:InvalidLspclkHz', 'LSPCLK');
validate_positive_scalar(requestedBaud, ...
    'C2837xBlock:SciBaud:InvalidRequestedBaud', 'Requested Baud');
lspclkHz = double(lspclkHz);
requestedBaud = double(requestedBaud);

minimumBrr = 1;
maximumBrr = 65535;
idealBrr = lspclkHz / (8 * requestedBaud) - 1;
candidateBrr = unique([floor(idealBrr), ceil(idealBrr)]);
candidateBrr = min(max(candidateBrr, minimumBrr), maximumBrr);
candidateBrr = unique(candidateBrr);

candidateBaud = lspclkHz ./ (8 * (candidateBrr + 1));
candidateAbsoluteError = abs(candidateBaud - requestedBaud);
ranking = [candidateAbsoluteError(:), candidateBrr(:)];
[~, rankingOrder] = sortrows(ranking, [1 2]);
selectedIndex = rankingOrder(1);
selectedBrr = candidateBrr(selectedIndex);
actualBaud = candidateBaud(selectedIndex);
signedErrorBaud = actualBaud - requestedBaud;

result = struct( ...
    'brr', uint16(selectedBrr), ...
    'actual_baud', actualBaud, ...
    'signed_error_baud', signedErrorBaud, ...
    'absolute_error_baud', abs(signedErrorBaud), ...
    'signed_relative_error_ratio', signedErrorBaud / requestedBaud);
end

function validate_positive_scalar(value, identifier, name)
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
        ~isfinite(value) || value <= 0
    error(identifier, '%s must be a finite, positive numeric scalar.', name);
end
end
