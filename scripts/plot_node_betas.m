%% Plot BNV

clear
clc
close all

warning ON

addpath(genpath('/Users/stiso/Documents/Code/interictal_spikes_fc/'))
addpath('/Users/stiso/Documents/MATLAB/fieldtrip-20170830/')
addpath(genpath('/Users/stiso/Documents/MATLAB/BrainNetViewer_20171031/'))

%% load
% node data

top_dir = '/Volumes/bassett-data/Jeni/RAM/';
win = 1;
betas = readtable([top_dir, 'group_analysis/win_',  num2str(win), '/node_stats.csv']);
beta_names = betas.Properties.VariableNames(cellfun(@(x) contains(x, 'beta'), betas.Properties.VariableNames));
band_measures = unique(betas.band_measure);

% convert coords to numbers
betas.y = cellfun(@(x) str2double(x), betas.y);
betas.x = cellfun(@(x) str2double(x), betas.x);
betas.z = cellfun(@(x) str2double(x), betas.z);

% fix subject with offset
betas(strcmpi(betas.subj, 'R1004D'),:).y =  betas(strcmpi(betas.subj, 'R1004D'),:).y - 150;
betas(strcmpi(betas.subj, 'R1004D'),:).x = betas(strcmpi(betas.subj, 'R1004D'),:).x + 100;
        
for i = 1:numel(beta_names)
    curr_name = beta_names{i};
    
    for j = 1:numel(band_measures)
        curr_bm = band_measures{j};
        node_file = [top_dir, 'group_analysis/win_', num2str(win), '/', curr_name, '_', curr_bm, '.node'];
        curr_betas = betas(strcmpi(betas.band_measure,curr_bm),:);
        
        % remove nans
        curr_betas.(curr_name) = str2double(curr_betas.(curr_name));
        curr_betas = curr_betas(~isnan(curr_betas.(curr_name)),:);
        
        % z-score within subject
%         subjects = unique(curr_betas.subj);
%         for s = 1:numel(subjects)
%             idx = strcmpi(curr_betas.subj, subjects{s});
%             curr_betas.(curr_name)(idx) = zscore(curr_betas.(curr_name)(idx));
%         end

        write_bv_node(node_file, curr_betas.x, curr_betas.y, curr_betas.z, curr_betas.(curr_name), abs(curr_betas.(curr_name)), curr_betas.region);
    end
end

%% plot

for i = 1:numel(beta_names)
    for j = 1:numel(band_measures)
        cont = [beta_names{i}, '_', band_measures{j}];
        
        BrainNet_MapCfg('/Users/stiso/Documents/MATLAB/BrainNetViewer_20171031/Data/SurfTemplate/BrainMesh_ICBM152_smoothed.nv',...
            [top_dir, 'group_analysis/win_',  num2str(win), '/', cont, '.node'], '/Users/stiso/Documents/Code/interictal_spikes_fc/img/bnv_format_sparse.mat', ...
            [top_dir, 'img/bnv/', cont, '.jpg']);
    end
end