function [corr_ortho] = get_aec_ortho_cfn(data)
% Get orthognalized amplitude (not power) envelope correlations. For power
% use fieldtrip
%   data:       input should be a single trial (multiple time point) Hilbert
%               transformed data of size N x T, where N is the number of
%               electrodes/contacts and T is the number of
%               timepoints/windows


% useful constants
nElec = size(data,1);
nEdge = (nElec^2-nElec)/2;

% normalize
norm_data = data'.*sqrt(size(data,2))./sqrt(sum(abs(data)'.^2));

% get real value of coherency
c = real(norm_data'*norm_data)./size(data,2);

% pairwise corrs
% for each normalized pair, z1 and z2, orthogonalize z2, get corr. average across z1
% and z2 orthogonalized pairs
corr_ortho = zeros(nEdge,1);
cnt = 1;
for i = 1:nElec
    for j = (i+1):nElec
            c1 = corr(abs(norm_data(:,i)).^2, abs(norm_data(:,j) - (c(i,j)*norm_data(:,i))).^2);
            c2 = corr(abs(norm_data(:,j)).^2, abs(norm_data(:,i) - (c(i,j)*norm_data(:,j))).^2);
            corr_ortho(cnt) = mean([c1,c2]);
            cnt = cnt + 1;
    end
end

end

