%% Prprocess RAM data
% ~300 subjects, for a total of 1073 sessions of data.
% This script saves cleaned task-free data for each session

clear
clc
close all
warning ON

addpath(genpath('/Users/stiso/Documents/Code/interictal_spikes_fc/'))
addpath('/Users/stiso/Documents/MATLAB/fieldtrip-20170830/')

%%

% global variables and packages
top_dir = '/Volumes/bassett-data/Jeni/RAM/';
eval(['cd ', top_dir])

% for removing electrodes
thr = 1.5;
releases = ['1', '2', '3'];

parfor r = 1:numel(releases)
    release = releases(r);
    
    release_dir = [top_dir, 'release', release '/'];
    
    % for catching errors
    errors = struct('files', [], 'message', []);
    warnings = struct('files', [], 'message', []);
    
    % remove parent and hidden directories, then get protocols
    folders = dir([release_dir '/protocols']);
    folders = {folders([folders.isdir]).name};
    protocols = folders(cellfun(@(x) ~contains(x, '.'), folders));

    % main preprocessing function
    preproc(thr, release_dir, top_dir, release, protocols, warnings, errors);

end

% get and concatenate errors and warnings
errors_all = struct('files', [], 'message', []);
warnings_all = struct('files', [], 'message', []);
for r = 1:numel(releases)
    release = releases(r);
    release_dir = [top_dir, 'release', release '/'];
    
    curr_err = load([release_dir, 'errors.mat']);
    curr_warn = load([release_dir, 'warnings.mat']);
    
    errors_all= [errors_all, curr_err.errors];
    warnings_all = [warnings_all, curr_warn.warnings];
end
save([top_dir, 'errors.mat'], 'errors_all')
save([top_dir, 'warnings.mat'], 'warnings_all')
